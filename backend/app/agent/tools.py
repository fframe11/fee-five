"""
Fee Five — Agent Tool Registry
8 tools the LLM agent can call. Each tool is a pure function returning a dict result.
Camera-related tools are ONLY available when the camera event is explicitly triggered.
"""
from __future__ import annotations
import os
import json
import math
import urllib.request
import urllib.error
from datetime import datetime
from typing import Optional

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _load_api_key() -> Optional[str]:
    for path in ["../.env", "../../.env", ".env"]:
        if os.path.exists(path):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    for line in f:
                        if "=" in line and not line.strip().startswith("#"):
                            k, v = line.strip().split("=", 1)
                            if k.strip() in ("Groq_api", "GROQ_API_KEY"):
                                return v.strip()
            except Exception:
                pass
    return os.environ.get("Groq_api") or os.environ.get("GROQ_API_KEY")


def _haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Return distance in metres between two GPS coordinates."""
    R = 6_371_000
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlam = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlam / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


# ---------------------------------------------------------------------------
# Mock infrastructure data (prototype — replace with real DB query in production)
# ---------------------------------------------------------------------------
MOCK_BARRIERS = [
    {"id": 1, "type": "construction",  "lat": 13.7456, "lng": 100.5355, "severity": "high",   "description": "งานซ่อมทางเท้า พระราม 1"},
    {"id": 2, "type": "broken_sidewalk", "lat": 13.7448, "lng": 100.5332, "severity": "medium", "description": "พื้นทางเท้าแตกร้าว หน้า MBK"},
    {"id": 3, "type": "stairs",         "lat": 13.7465, "lng": 100.5340, "severity": "high",   "description": "บันได BTS สยาม ทางออก 2 (ไม่มีทางลาด)"},
]

MOCK_INFRASTRUCTURE = [
    {"id": "elev_bts_siam_3",  "type": "elevator", "name": "ลิฟต์ BTS สยาม ทางออก 3", "lat": 13.7461, "lng": 100.5365, "status": "operational"},
    {"id": "elev_bts_siam_5",  "type": "elevator", "name": "ลิฟต์ BTS สยาม ทางออก 5", "lat": 13.7452, "lng": 100.5342, "status": "under_maintenance"},
    {"id": "ramp_paragon_main", "type": "ramp",     "name": "ทางลาดสยามพารากอน ประตูหลัก",  "lat": 13.7463, "lng": 100.5350, "status": "operational"},
]


# ---------------------------------------------------------------------------
# Tool 1 — obstacle_alert
# ---------------------------------------------------------------------------
def obstacle_alert(
    message: str,
    risk_level: str,            # low | medium | high
    user_mode: str,
    lat: Optional[float] = None,
    lng: Optional[float] = None,
) -> dict:
    """
    Format and return an alert payload to be pushed to the mobile app.
    Does NOT call audio/haptic directly — mobile app decides output channel based on user_mode.
    """
    modality = {
        "wheelchair": {"visual": True,  "audio": True,  "haptic": True},
        "visual":     {"visual": False, "audio": True,  "haptic": True},
        "hearing":    {"visual": True,  "audio": False, "haptic": True},
    }.get(user_mode, {"visual": True, "audio": True, "haptic": True})

    return {
        "tool": "obstacle_alert",
        "status": "ok",
        "alert": {
            "message": message,
            "risk_level": risk_level,
            "modality": modality,
            "location": {"lat": lat, "lng": lng} if lat and lng else None,
            "timestamp": datetime.utcnow().isoformat(),
        },
    }


# ---------------------------------------------------------------------------
# Tool 2 — reroute_navigation
# ---------------------------------------------------------------------------
def reroute_navigation(
    user_id: int,
    reason: str,
    current_lat: float,
    current_lng: float,
    destination: str,
    user_mode: str,
) -> dict:
    """
    Signal the navigation service to compute an alternative accessible route.
    Returns a mock reroute response (prototype).
    In production: calls the FastAPI /navigation/route endpoint internally.
    """
    # Prototype: return canned reroute confirmation
    accessible_alternatives = {
        "wheelchair": "ใช้ทางลาดสยามพารากอน → ลิฟต์ BTS ทางออก 3 แทน (เพิ่ม 4 นาที)",
        "visual":     "เดินตามทางเสียงนำทางด้านซ้าย ห่างจากเสา 1.5 เมตร",
        "hearing":    "ปฏิบัติตามลูกศรบนแผนที่ → เลี่ยงโซนก่อสร้าง",
    }
    return {
        "tool": "reroute_navigation",
        "status": "ok",
        "reroute": {
            "reason": reason,
            "user_mode": user_mode,
            "new_instruction": accessible_alternatives.get(user_mode, "กรุณาค้นหาเส้นทางใหม่"),
            "estimated_extra_minutes": 4,
            "from": {"lat": current_lat, "lng": current_lng},
            "to": destination,
        },
    }


# ---------------------------------------------------------------------------
# Tool 3 — trigger_sos
# ---------------------------------------------------------------------------
def trigger_sos(
    user_id: int,
    lat: float,
    lng: float,
    trigger_method: str,   # manual | gesture | voice
    reason: str = "",
) -> dict:
    """
    Creates an SOS event. In production: writes to DB + notifies emergency contacts.
    """
    return {
        "tool": "trigger_sos",
        "status": "ok",
        "sos_event": {
            "user_id": user_id,
            "event_type": "SOS",
            "trigger_method": trigger_method,
            "reason": reason,
            "location": {"lat": lat, "lng": lng},
            "timestamp": datetime.utcnow().isoformat(),
            "action": "notify_emergency_contacts",
        },
    }


# ---------------------------------------------------------------------------
# Tool 4 — suggest_camera_scan
# ---------------------------------------------------------------------------
def suggest_camera_scan(reason: str, risk_zone_description: str) -> dict:
    """
    Prompts the mobile app to suggest the user open the camera.
    Camera is ON-DEMAND — this tool only sends a suggestion, never forces activation.
    """
    return {
        "tool": "suggest_camera_scan",
        "status": "ok",
        "suggestion": {
            "prompt": f"แนะนำเปิดกล้องตรวจสอบ: {reason}",
            "zone": risk_zone_description,
            "dismissable": True,
        },
    }


# ---------------------------------------------------------------------------
# Tool 5 — analyze_camera_frame  (only called when camera is already open)
# ---------------------------------------------------------------------------
def analyze_camera_frame(image_b64: str, user_mode: str) -> dict:
    """
    Sends a camera frame to Groq Vision for scene analysis.
    Called ONLY when the user has already opened the camera.
    """
    api_key = _load_api_key()
    if not api_key:
        return {"tool": "analyze_camera_frame", "status": "error", "error": "No API key"}

    mode_prompts = {
        "wheelchair": (
            "คุณคือ AI ช่วยผู้ใช้รถเข็น วิเคราะห์ภาพถ่ายนี้ "
            "บอกว่ามีบันได ทางต่างระดับ หรืออุปสรรคสำหรับรถเข็นไหม "
            "ระบุทิศทาง ซ้าย-กลาง-ขวา และแนะนำสั้นๆ ไม่เกิน 2 ประโยค ภาษาไทย"
        ),
        "visual": (
            "คุณคือ AI ช่วยผู้พิการทางสายตา วิเคราะห์ภาพถ่ายนี้ "
            "บอกสิ่งกีดขวางอันตราย เช่น เสา หลุม บันได "
            "ระบุตำแหน่ง และแนะนำว่าควรหลบไปทางไหน ไม่เกิน 2 ประโยค ภาษาไทย"
        ),
        "hearing": (
            "วิเคราะห์ภาพถ่ายนี้ บอกอุปสรรคที่มองเห็น "
            "ตอบเป็นภาษาไทยสั้นๆ ไม่เกิน 2 ประโยค"
        ),
    }
    prompt = mode_prompts.get(user_mode, mode_prompts["visual"])

    img_data = image_b64 if image_b64.startswith("data:image") else f"data:image/jpeg;base64,{image_b64}"
    payload = {
        "model": "qwen/qwen3.6-27b",
        "messages": [{"role": "user", "content": [
            {"type": "text", "text": prompt},
            {"type": "image_url", "image_url": {"url": img_data}},
        ]}],
        "temperature": 0.2,
    }
    try:
        req = urllib.request.Request(
            "https://api.groq.com/openai/v1/chat/completions",
            data=json.dumps(payload).encode("utf-8"),
            headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            description = data["choices"][0]["message"]["content"].strip()
            return {"tool": "analyze_camera_frame", "status": "ok", "description": description}
    except Exception as e:
        return {"tool": "analyze_camera_frame", "status": "error", "error": str(e)}


# ---------------------------------------------------------------------------
# Tool 6 — get_route_barriers
# ---------------------------------------------------------------------------
def get_route_barriers(lat: float, lng: float, radius_m: float = 200.0) -> dict:
    """
    Returns barriers within radius_m metres of a GPS coordinate.
    Prototype: uses MOCK_BARRIERS. Production: queries PostgreSQL/PostGIS.
    """
    nearby = []
    for b in MOCK_BARRIERS:
        dist = _haversine_m(lat, lng, b["lat"], b["lng"])
        if dist <= radius_m:
            nearby.append({**b, "distance_m": round(dist, 1)})

    nearby.sort(key=lambda x: x["distance_m"])
    return {
        "tool": "get_route_barriers",
        "status": "ok",
        "barriers": nearby,
        "count": len(nearby),
    }


# ---------------------------------------------------------------------------
# Tool 7 — get_infrastructure_status
# ---------------------------------------------------------------------------
def get_infrastructure_status(lat: float, lng: float, radius_m: float = 300.0) -> dict:
    """
    Returns elevators / ramps within radius_m with their operational status.
    """
    nearby = []
    for item in MOCK_INFRASTRUCTURE:
        dist = _haversine_m(lat, lng, item["lat"], item["lng"])
        if dist <= radius_m:
            nearby.append({**item, "distance_m": round(dist, 1)})

    nearby.sort(key=lambda x: x["distance_m"])
    unavailable = [x for x in nearby if x["status"] != "operational"]
    return {
        "tool": "get_infrastructure_status",
        "status": "ok",
        "infrastructure": nearby,
        "unavailable_count": len(unavailable),
        "unavailable": unavailable,
    }


# ---------------------------------------------------------------------------
# Tool 8 — speak_instruction
# ---------------------------------------------------------------------------
def speak_instruction(message: str, user_mode: str, haptic: bool = True) -> dict:
    """
    Returns a TTS payload for the mobile app to speak / display.
    For hearing mode: returns text-only (no audio flag).
    """
    use_audio = user_mode != "hearing"
    return {
        "tool": "speak_instruction",
        "status": "ok",
        "instruction": {
            "text": message,
            "language": "th",
            "audio": use_audio,
            "haptic": haptic,
            "display": True,
        },
    }


# ---------------------------------------------------------------------------
# Tool dispatcher — maps LLM tool name → Python function
# ---------------------------------------------------------------------------
TOOL_REGISTRY: dict[str, callable] = {
    "obstacle_alert":         obstacle_alert,
    "reroute_navigation":     reroute_navigation,
    "trigger_sos":            trigger_sos,
    "suggest_camera_scan":    suggest_camera_scan,
    "analyze_camera_frame":   analyze_camera_frame,
    "get_route_barriers":     get_route_barriers,
    "get_infrastructure_status": get_infrastructure_status,
    "speak_instruction":      speak_instruction,
}

TOOL_DEFINITIONS = [
    {"name": "obstacle_alert",         "description": "Send an accessibility alert to the user with appropriate modality (audio/visual/haptic) based on their disability mode."},
    {"name": "reroute_navigation",     "description": "Request an alternative accessible route when a barrier blocks the current path."},
    {"name": "trigger_sos",            "description": "Activate emergency SOS and notify emergency contacts. Use only when there is HIGH confidence of an emergency."},
    {"name": "suggest_camera_scan",    "description": "Suggest the user opens the camera for a manual environment scan. Camera is always on-demand — never force-activate."},
    {"name": "analyze_camera_frame",   "description": "Analyze a camera frame using Vision AI. Only call this tool when camera_frame_b64 is provided in the event."},
    {"name": "get_route_barriers",     "description": "Query barriers on or near the current route within a given radius."},
    {"name": "get_infrastructure_status", "description": "Check the status of nearby elevators, ramps, and accessible infrastructure."},
    {"name": "speak_instruction",      "description": "Send a voice/text instruction to the user. For hearing-impaired users: text-only, no audio."},
]
