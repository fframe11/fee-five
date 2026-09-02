"""
Fee Five — Agent API Router
Endpoints:
  POST /api/v1/agent/event   — main entry: all 5 event types
  POST /api/v1/agent/push    — server-push shortcut (BTS elevator down, etc.)
  GET  /api/v1/agent/status/{user_id} — session summary
  DELETE /api/v1/agent/session/{user_id} — clear session memory
"""
from __future__ import annotations

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, Field
from typing import Optional, Any
import traceback

from ..agent.event_classifier import classify_event, EventType
from ..agent.accessibility_agent import run_agent
from ..agent.memory import agent_memory

router = APIRouter(prefix="/api/v1/agent", tags=["Smart Agent"])


# ---------------------------------------------------------------------------
# Request / Response schemas
# ---------------------------------------------------------------------------

class AgentEventRequest(BaseModel):
    """
    Universal event payload from the mobile app.
    event_type must be one of: gps_barrier | voice_command | push_event | camera_scan | motion_anomaly
    """
    event_type: str = Field(..., description="gps_barrier | voice_command | push_event | camera_scan | motion_anomaly")
    user_id: int
    user_mode: str = Field(..., description="wheelchair | visual | hearing")
    lat: float = Field(..., ge=-90,  le=90)
    lng: float = Field(..., ge=-180, le=180)

    # Optional per event-type
    barrier_info:    Optional[dict[str, Any]] = None   # gps_barrier
    voice_text:      Optional[str]            = None   # voice_command
    push_payload:    Optional[dict[str, Any]] = None   # push_event
    camera_frame_b64:Optional[str]            = None   # camera_scan (on-demand only)
    motion_data:     Optional[dict[str, Any]] = None   # motion_anomaly

    # Navigation context (if active)
    route_id:    Optional[str] = None
    destination: Optional[str] = None


class PushEventRequest(BaseModel):
    """Shortcut for server-push infrastructure events (e.g. BTS elevator down)."""
    user_id: int
    user_mode: str
    lat: float
    lng: float
    push_type: str   # elevator_down | barrier_new | ramp_closed | route_disruption
    message: str
    location_name: Optional[str] = None
    route_id:    Optional[str] = None
    destination: Optional[str] = None


class AgentResponse(BaseModel):
    decision: str
    action_args: dict = {}
    confidence: float
    thought: str
    user_message: str
    tool_result: dict
    event_type: str
    urgency: str
    user_mode: str
    timestamp: str


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.post("/event", response_model=AgentResponse, summary="Process any accessibility event")
def process_event(body: AgentEventRequest):
    """
    Main agent entry point.
    Mobile app sends this whenever any of the 5 event triggers fires.
    Camera events include camera_frame_b64 only if the user has the camera open.
    """
    try:
        event = classify_event(body.model_dump())
        result = run_agent(event)
        return result
    except ValueError as ve:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(ve))
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Agent processing failed: {traceback.format_exc(limit=3)}",
        )


@router.post("/push", response_model=AgentResponse, summary="Server push infrastructure event")
def process_push_event(body: PushEventRequest):
    """
    Convenience endpoint for backend-initiated push events.
    Example: BTS system notifies that elevator at Exit 5 is under maintenance.
    """
    raw = {
        "event_type": EventType.PUSH_EVENT.value,
        "user_id": body.user_id,
        "user_mode": body.user_mode,
        "lat": body.lat,
        "lng": body.lng,
        "push_payload": {
            "type": body.push_type,
            "message": body.message,
            "location": body.location_name,
        },
        "route_id": body.route_id,
        "destination": body.destination,
    }
    try:
        event = classify_event(raw)
        result = run_agent(event)
        return result
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Push event processing failed: {traceback.format_exc(limit=3)}",
        )


@router.get("/status/{user_id}", summary="Get agent session summary")
def get_agent_status(user_id: int):
    """Returns the current session memory summary for a user."""
    sessions = agent_memory._sessions
    session = sessions.get(user_id)
    if not session:
        return {"user_id": user_id, "session": "no active session"}
    return {
        "user_id": user_id,
        "user_mode": session.user_mode,
        "created_at": session.created_at.isoformat(),
        "last_active": session.last_active.isoformat(),
        "turn_count": len(session.turns),
        "current_route_id": session.current_route_id,
        "destination": session.current_destination,
        "recent_context": session.get_context_summary(),
    }


@router.delete("/session/{user_id}", summary="Clear agent session memory")
def clear_session(user_id: int):
    """Clears the agent session memory for a user (e.g. when navigation ends)."""
    agent_memory.clear(user_id)
    return {"user_id": user_id, "status": "session cleared"}


@router.post("/session/purge-expired", summary="Purge all expired sessions (admin)")
def purge_expired():
    """Removes all idle sessions older than TTL. Call periodically from a scheduler."""
    count = agent_memory.purge_expired()
    return {"purged": count}
