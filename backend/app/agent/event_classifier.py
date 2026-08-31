"""
Fee Five — Event Classifier
Maps raw incoming events to structured AgentEvent objects,
determines urgency, and pre-loads user context before handing off to the agent.
"""
from __future__ import annotations
from dataclasses import dataclass
from enum import Enum
from typing import Optional


class EventType(str, Enum):
    GPS_BARRIER     = "gps_barrier"       # GPS proximity alert: user near a known barrier
    VOICE_COMMAND   = "voice_command"     # User spoke a command
    PUSH_EVENT      = "push_event"        # Server push: infrastructure status changed
    CAMERA_SCAN     = "camera_scan"       # User opened camera (on-demand)
    MOTION_ANOMALY  = "motion_anomaly"    # Accelerometer: sudden stop / irregular pattern


class Urgency(str, Enum):
    LOW      = "low"
    MEDIUM   = "medium"
    HIGH     = "high"
    CRITICAL = "critical"


@dataclass
class AgentEvent:
    event_type: EventType
    urgency: Urgency
    user_id: int
    user_mode: str            # wheelchair | visual | hearing
    lat: float
    lng: float

    # Optional payloads per event type
    barrier_info: Optional[dict]   = None   # gps_barrier
    voice_text: Optional[str]      = None   # voice_command
    push_payload: Optional[dict]   = None   # push_event
    camera_frame_b64: Optional[str]= None   # camera_scan
    motion_data: Optional[dict]    = None   # motion_anomaly

    # Route context (populated if navigation is active)
    route_id: Optional[str]        = None
    destination: Optional[str]     = None


# ---------------------------------------------------------------------------
# Urgency resolution matrix
# ---------------------------------------------------------------------------
_GPS_SEVERITY_TO_URGENCY = {
    "high":   Urgency.HIGH,
    "medium": Urgency.MEDIUM,
    "low":    Urgency.LOW,
}

_PUSH_TYPE_TO_URGENCY = {
    "elevator_down":   Urgency.HIGH,
    "barrier_new":     Urgency.MEDIUM,
    "ramp_closed":     Urgency.HIGH,
    "route_disruption":Urgency.CRITICAL,
}

_MOTION_PATTERN_TO_URGENCY = {
    "sudden_stop":       Urgency.MEDIUM,   # May have encountered obstacle
    "erratic_movement":  Urgency.MEDIUM,
    "fall_detected":     Urgency.CRITICAL,
    "wandering":         Urgency.LOW,
}


def classify_event(raw: dict) -> AgentEvent:
    """
    Parse a raw API request body into a structured AgentEvent.

    Expected raw fields:
        event_type: str
        user_id: int
        user_mode: str
        lat: float
        lng: float
        + type-specific optional fields
    """
    try:
        etype = EventType(raw["event_type"])
    except (KeyError, ValueError):
        raise ValueError(f"Unknown event_type: {raw.get('event_type')}")

    user_id   = int(raw["user_id"])
    user_mode = str(raw.get("user_mode", "wheelchair"))
    lat       = float(raw.get("lat", 0.0))
    lng       = float(raw.get("lng", 0.0))

    # Determine urgency
    urgency = Urgency.LOW
    if etype == EventType.GPS_BARRIER:
        barrier = raw.get("barrier_info", {})
        urgency = _GPS_SEVERITY_TO_URGENCY.get(
            barrier.get("severity", "low"), Urgency.LOW
        )

    elif etype == EventType.PUSH_EVENT:
        push = raw.get("push_payload", {})
        urgency = _PUSH_TYPE_TO_URGENCY.get(push.get("type", ""), Urgency.MEDIUM)

    elif etype == EventType.CAMERA_SCAN:
        # Camera scans are inherently medium urgency — user requested info
        urgency = Urgency.MEDIUM

    elif etype == EventType.VOICE_COMMAND:
        text = str(raw.get("voice_text", "")).lower()
        if any(kw in text for kw in ("sos", "ช่วยด้วย", "ฉุกเฉิน", "help")):
            urgency = Urgency.CRITICAL
        else:
            urgency = Urgency.MEDIUM

    elif etype == EventType.MOTION_ANOMALY:
        motion = raw.get("motion_data", {})
        urgency = _MOTION_PATTERN_TO_URGENCY.get(
            motion.get("pattern", "sudden_stop"), Urgency.MEDIUM
        )

    return AgentEvent(
        event_type=etype,
        urgency=urgency,
        user_id=user_id,
        user_mode=user_mode,
        lat=lat,
        lng=lng,
        barrier_info=raw.get("barrier_info"),
        voice_text=raw.get("voice_text"),
        push_payload=raw.get("push_payload"),
        camera_frame_b64=raw.get("camera_frame_b64"),
        motion_data=raw.get("motion_data"),
        route_id=raw.get("route_id"),
        destination=raw.get("destination"),
    )
