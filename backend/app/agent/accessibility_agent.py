"""
Fee Five — Smart Accessibility Agent (ReAct Orchestrator)
Mode-aware: wheelchair | visual | hearing
Event-driven: GPS barrier / Voice command / Server push / Camera (on-demand) / Motion anomaly
"""
from __future__ import annotations

import json
import os
import urllib.request
import urllib.error
from datetime import datetime
from typing import Optional

from .event_classifier import AgentEvent, EventType, Urgency
from .memory import agent_memory, AgentTurn
from .tools import TOOL_REGISTRY, TOOL_DEFINITIONS


# ---------------------------------------------------------------------------
# Mode-Specific System Prompts
# ---------------------------------------------------------------------------
_BASE_SYSTEM = """\
You are the TAM Smart Accessibility Agent — the AI Voice Navigator for blind users in Thailand.

CRITICAL RULES:
1. LINGUISTIC UNDERSTANDING:
   Accurately understand colloquial Thai and regional dialects (Isan, Northern, Southern, e.g. "พาข้อยไปหาหมอแหน่", "ส่องให้แหน่", "ไปเซเว่น", "ข้อยอยู่ไส").

2. ACTION MAPPING:
   - "start_navigation": user mentions a destination or place ("เซเว่น", "ไปหาหมอ", "พาไป...") -> action_args: {"destination": "..."}
   - "open_camera": user wants to check obstacles or see ahead ("ส่องให้แหน่", "ดูข้างหน้า", "เปิดกล้อง")
   - "trigger_sos": user fell down, injured, or asks for emergency help ("ช่วยด้วย", "ล้ม", "ฉุกเฉิน")
   - "get_location_context": user is lost ("อยู่ที่ไหน", "ข้อยอยู่ไส")
   - "toggle_voice": silence / mute ("เซาเว่า", "ปิดเสียง") -> action_args: {"mute": true}

3. SPOKEN OUTPUT (STRICTLY CONCISE):
   - "user_message" MUST be ONLY ONE short sentence (under 6 words in Thai).
   - NEVER talk about yourself, dialects, or internal reasoning.
   - Example: "กำลังนำทางไป 7-Eleven ค่ะ"

Available tools: {tool_names}, start_navigation, open_camera, get_location_context, toggle_voice

Respond ONLY with JSON:
{
  "thought": "<brief>",
  "action": "<tool_name>",
  "action_args": { ... },
  "confidence": 0.95,
  "user_message": "<Short Thai sentence>"
}
"""

_MODE_ADDENDUM = {
    "visual": "Focus: obstacle alerts and direct navigation execution.",
}


def _build_system_prompt(user_mode: str = "visual") -> str:
    tool_names = ", ".join(TOOL_REGISTRY.keys())
    base = _BASE_SYSTEM.format(tool_names=tool_names)
    addendum = _MODE_ADDENDUM.get(user_mode, _MODE_ADDENDUM["visual"])
    return f"{base}\nGuidance: {addendum}"


# ---------------------------------------------------------------------------
# Event → LLM User Message Builder
# ---------------------------------------------------------------------------
def _build_user_message(event: AgentEvent, context_summary: str) -> str:
    parts = [
        f"User Mode: {event.user_mode}",
        f"Event: {event.event_type.value}",
        f"Urgency: {event.urgency.value}",
        f"Location: lat={event.lat}, lng={event.lng}",
    ]

    if event.route_id:
        parts.append(f"Active Route: {event.route_id} → {event.destination}")

    if event.event_type == EventType.GPS_BARRIER and event.barrier_info:
        b = event.barrier_info
        parts.append(
            f"Barrier detected {b.get('distance_m', '?')}m ahead: "
            f"type={b.get('type')}, severity={b.get('severity')}, "
            f"description={b.get('description', '')}"
        )

    elif event.event_type == EventType.VOICE_COMMAND:
        parts.append(f"User said: \"{event.voice_text}\"")

    elif event.event_type == EventType.PUSH_EVENT and event.push_payload:
        p = event.push_payload
        parts.append(
            f"Server push — {p.get('type')}: {p.get('message', '')} "
            f"at {p.get('location', 'unknown location')}"
        )

    elif event.event_type == EventType.CAMERA_SCAN:
        parts.append("User has opened the camera. camera_frame_b64 is available for analysis.")
        if not event.camera_frame_b64:
            parts.append("Note: no frame data provided — suggest scan only, do not analyze.")

    elif event.event_type == EventType.MOTION_ANOMALY and event.motion_data:
        m = event.motion_data
        parts.append(
            f"Motion anomaly detected: pattern={m.get('pattern')}, "
            f"magnitude={m.get('magnitude', '?')}"
        )

    if context_summary and context_summary != "No previous interactions in this session.":
        parts.append(f"\nRecent session context:\n{context_summary}")

    return "\n".join(parts)


# ---------------------------------------------------------------------------
# LLM Call (Groq)
# ---------------------------------------------------------------------------
def _load_api_key(name: str, alt_names: list[str] = None) -> str:
    all_keys = [name] + (alt_names or [])
    for k in all_keys:
        val = os.environ.get(k)
        if val:
            return val
    env_paths = [
        os.path.join(os.getcwd(), ".env"),
        os.path.join(os.path.dirname(__file__), "..", "..", "..", ".env"),
        os.path.join(os.path.dirname(__file__), "..", "..", ".env"),
        r"c:\feefive\.env",
    ]
    for p in env_paths:
        if os.path.exists(p):
            try:
                with open(p, "r", encoding="utf-8") as f:
                    for line in f:
                        if "=" in line and not line.strip().startswith("#"):
                            k, v = line.strip().split("=", 1)
                            if k.strip() in all_keys:
                                return v.strip().strip("'\"")
            except Exception:
                pass
    return ""

def _load_gemini_key() -> str:
    return _load_api_key("gemini_api_key", ["GEMINI_API_KEY", "GOOGLE_API_KEY", "gemini_api"])

def _rule_based_fallback(user_message: str) -> dict:
    """Universal rule-based intent fallback with Thai dialect understanding when offline."""
    msg = user_message.lower()
    for noise in ["กำลังฟังเสียง", "พูดได้เลยครับ", "พูดได้เลย", "ครับ", "ค่ะ", "แหน่"]:
        msg = msg.replace(noise.lower(), " ")
    msg = msg.strip()
    
    # 1. Navigation intent (supports standard Thai & Isan/Northern/Southern dialects)
    if any(w in msg for w in ["พาไป", "นำทาง", "ไปที่", "ไป", "เดินทาง", "กลับบ้าน", "พาข้อย", "พาเฮา", "เซเว่น", "seven", "7-eleven", "7-11", "หมอ", "โรงพยาบาล", "ตึก", "อาคาร"]):
        dest = "7-Eleven" if any(w in msg for w in ["เซเว่น", "seven", "7-eleven", "7-11"]) else ("โรงพยาบาล" if any(w in msg for w in ["หมอ", "โรงพยาบาล"]) else "จุดหมาย")
        if dest == "จุดหมาย":
            for w in ["พาไป", "นำทางไป", "ไปที่", "เดินทางไป", "พาข้อยไป", "พาเฮาไป", "ไป"]:
                if w in msg:
                    dest = msg.split(w, 1)[1].strip()
                    break
        if not dest or dest == "จุดหมาย":
            dest = msg
        return {
            "thought": f"นำทางไปยัง {dest}",
            "action": "start_navigation",
            "action_args": {"destination": dest},
            "confidence": 0.95,
            "user_message": f"กำลังนำทางไป {dest} ค่ะ"
        }
        
    elif any(w in msg for w in ["หยุดนำทาง", "ยกเลิก", "หยุด", "พอแล้ว", "เซานำทาง"]):
        return {
            "thought": "หยุดนำทาง",
            "action": "stop_navigation",
            "action_args": {},
            "confidence": 0.98,
            "user_message": "หยุดการนำทางแล้วค่ะ"
        }

    elif any(w in msg for w in ["ส่อง", "ดูข้างหน้า", "มีหยัง", "เปิดกล้อง", "มืด", "มองรอบๆ", "อ่านป้าย", "มีอะไรขวาง"]):
        return {
            "thought": "เปิดกล้อง",
            "action": "open_camera",
            "action_args": {"reason": "สแกนสิ่งกีดขวาง"},
            "confidence": 0.95,
            "user_message": "เปิดกล้องส่องทางให้แล้วค่ะ"
        }
        
    elif any(w in msg for w in ["ช่วยด้วย", "ช่วยข้อย", "ฉุกเฉิน", "ล้ม", "เจ็บ", "sos", "เกิดอุบัติเหตุ", "โทรหา", "บ่ไหว"]):
        return {
            "thought": "ตรวจพบคำสั่งขอความช่วยเหลือฉุกเฉิน",
            "action": "trigger_sos",
            "action_args": {"reason": "ผู้ใช้ร้องขอความช่วยเหลือฉุกเฉิน", "trigger_method": "voice"},
            "confidence": 0.99,
            "user_message": "กำลังส่งสัญญาณขอความช่วยเหลือและแจ้งผู้ดูแลให้ทันทีครับ ไม่ต้องกังวลนะครับ"
        }

    elif any(w in msg for w in ["อยู่ไส", "อยู่ไหน", "หลงทาง", "ที่นี่คือ", "ตรงไหน"]):
        return {
            "thought": "ผู้ใช้ต้องการทราบตำแหน่งปัจจุบันและจุดสังเกต",
            "action": "get_location_context",
            "action_args": {},
            "confidence": 0.95,
            "user_message": "กำลังตรวจสอบพิกัดและจุดสังเกตใกล้เคียงให้ครับ"
        }

    elif any(w in msg for w in ["เซาเว่า", "ปิดเสียง", "หนวกหู", "เงียบ", "อย่าเพิ่งพูด"]):
        return {
            "thought": "ผู้ใช้ต้องการปิดเสียงนำทางชั่วคราว",
            "action": "toggle_voice",
            "action_args": {"mute": True},
            "confidence": 0.95,
            "user_message": "ได้ครับ เดี๋ยวผมปิดเสียงเงียบก่อนนะครับ"
        }
        
    elif any(w in msg for w in ["ลิฟต์", "ลิฟท์", "ทางลาด", "ห้องน้ำ", "สถานี"]):
        f_type = "elevator" if ("ลิฟต์" in msg or "ลิฟท์" in msg) else ("ramp" if "ทางลาด" in msg else ("toilet" if "ห้องน้ำ" in msg else "bts"))
        return {
            "thought": f"ผู้ใช้กำลังค้นหาสิ่งอำนวยความสะดวก: {f_type}",
            "action": "find_nearest_facility",
            "action_args": {"facility_type": f_type},
            "confidence": 0.92,
            "user_message": f"กำลังค้นหา{f_type}ที่ใกล้ที่สุดและเข้าถึงสะดวกให้ครับ"
        }
        
    return {
        "thought": "คำสั่งทั่วไป เข้าใจภาษาพูด",
        "action": "none",
        "action_args": {},
        "confidence": 0.80,
        "user_message": "รับทราบครับ Fee Five พร้อมเป็นนิ้วและดวงตานำทางช่วยเหลือคุณเสมอครับ"
    }

def _call_llm(system_prompt: str, user_message: str) -> dict:
    import re
    # ─── PRIMARY & SOLE AGENT BRAIN: Google Gemini (3.6-flash / flash-latest / 3.7-flash) ───
    # Note: Groq is strictly reserved exclusively for Camera Vision analysis in /api/v1/vision/analyze
    gemini_key = _load_gemini_key()
    if gemini_key:
        for model_name in ["gemini-3.6-flash", "gemini-flash-latest", "gemini-3.7-flash"]:
            try:
                url = f"https://generativelanguage.googleapis.com/v1beta/models/{model_name}:generateContent?key={gemini_key}"
                full_prompt = f"{system_prompt}\n\nUser Event / Voice Command:\n{user_message}\n\nRespond strictly with JSON matching the required schema."
                payload = {
                    "contents": [{"parts": [{"text": full_prompt}]}],
                    "generationConfig": {
                        "temperature": 0.1,
                        "responseMimeType": "application/json"
                    }
                }
                req = urllib.request.Request(
                    url,
                    data=json.dumps(payload).encode("utf-8"),
                    headers={"Content-Type": "application/json", "User-Agent": "TAM-Agent/1.0"},
                    method="POST"
                )
                with urllib.request.urlopen(req, timeout=6) as resp:
                    data = json.loads(resp.read().decode("utf-8"))
                    text = data["candidates"][0]["content"]["parts"][0]["text"].strip()
                    if text.startswith("```"):
                        text = re.sub(r"^```[a-zA-Z]*\n", "", text)
                        text = re.sub(r"\n```$", "", text)
                    return json.loads(text)
            except Exception as e:
                print(f"[Agent Brain] Gemini ({model_name}) error: {e}")

    # ─── LOCAL OFFLINE FALLBACK: Zero-Latency Dialect Intent Engine ───
    print("[Agent Brain] Switching to Zero-Latency Local Dialect Intent Fallback.")
    return _rule_based_fallback(user_message)



# ---------------------------------------------------------------------------
# Main Agent Entry Point
# ---------------------------------------------------------------------------
def run_agent(event: AgentEvent) -> dict:
    """
    Full ReAct cycle for a single event.
    Returns a structured response the API router can send to mobile.
    """
    # 1. PERCEIVE — load/create session memory
    session = agent_memory.get_or_create(event.user_id, event.user_mode)
    context_summary = session.get_context_summary()

    # 2. REASON — call LLM
    system_prompt = _build_system_prompt(event.user_mode)
    user_message  = _build_user_message(event, context_summary)

    try:
        llm_response = _call_llm(system_prompt, user_message)
    except Exception as exc:
        # Graceful fallback — never crash the mobile session
        return {
            "decision": "error",
            "error": str(exc),
            "fallback_message": "ระบบ AI ไม่สามารถประมวลผลได้ขณะนี้ กรุณาดำเนินการตามปกติ",
            "event_type": event.event_type.value,
        }

    thought      = llm_response.get("thought", "")
    action_name  = llm_response.get("action", "none")
    action_args  = llm_response.get("action_args", {})
    confidence   = float(llm_response.get("confidence", 0.5))
    user_message_out = llm_response.get("user_message", "")

    # 3. ACT — execute tool (if not 'none')
    tool_result = {}
    if action_name != "none" and action_name in TOOL_REGISTRY:
        # Inject common args that tools may need
        action_args.setdefault("user_mode", event.user_mode)
        action_args.setdefault("user_id", event.user_id)
        action_args.setdefault("lat", event.lat)
        action_args.setdefault("lng", event.lng)

        # Safety gate: never trigger SOS below confidence threshold
        if action_name == "trigger_sos" and confidence < 0.85:
            action_name = "obstacle_alert"
            action_args = {
                "message": "ตรวจพบสัญญาณฉุกเฉินที่ไม่ชัดเจน กรุณายืนยันหากต้องการความช่วยเหลือ",
                "risk_level": "medium",
                "user_mode": event.user_mode,
            }

        try:
            tool_result = TOOL_REGISTRY[action_name](**action_args)
        except TypeError as te:
            tool_result = {"tool": action_name, "status": "error", "error": str(te)}

    outcome = tool_result.get("status", "none") if tool_result else "no_action"

    # 4. OBSERVE — record turn in memory
    turn = AgentTurn(
        timestamp=datetime.utcnow(),
        event_type=event.event_type.value,
        user_mode=event.user_mode,
        thought=thought,
        action=action_name,
        action_args=action_args,
        outcome=outcome,
        location=(event.lat, event.lng),
    )
    agent_memory.record_turn(event.user_id, turn)

    # 5. Return structured response to API router
    return {
        "decision": action_name,
        "action_args": action_args,
        "confidence": confidence,
        "thought": thought,
        "user_message": user_message_out,
        "tool_result": tool_result,
        "event_type": event.event_type.value,
        "urgency": event.urgency.value,
        "user_mode": event.user_mode,
        "timestamp": datetime.utcnow().isoformat(),
    }
