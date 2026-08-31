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
You are the TAM Smart Accessibility Agent — a personal safety, obstacle detection, and navigation assistant \
for visually impaired and blind users in Thailand.

Your primary focus:
- Prioritize real-time audio descriptions and voice warnings in Thai.
- Alert user about obstacle proximity (poles, steps, drop-offs, construction, uneven ground).
- Guide user along safe walking corridors and tactile paving paths.
- Provide clear, concise audio + haptic feedback.

Core rules:
1. Reason step-by-step (Thought → Action → Observation pattern).
2. NEVER trigger SOS unless confidence is HIGH and context confirms emergency.
3. Camera is on-demand: use analyze_camera_frame ONLY when camera_frame_b64 is provided.
4. If no action is needed, return action: "none" and explain why it is safe to continue.
5. Keep Thai language in any user-facing message field (message, instruction, prompt).
6. Always choose the MINIMUM intervention needed.

Available tools: {tool_names}

Respond ONLY with valid JSON in this format:
{{
  "thought": "<your reasoning>",
  "action": "<tool_name or 'none'>",
  "action_args": {{ ... }},
  "confidence": 0.0-1.0,
  "user_message": "<Thai message for the user, empty string if none>"
}}
"""

_MODE_ADDENDUM = {
    "visual": "Focus: obstacle proximity alerts (poles, drop-offs, construction), audio + haptic output, camera scan suggestions near dense obstacle zones.",
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


def _call_llm(system_prompt: str, user_message: str) -> dict:
    api_key = _load_api_key()
    if not api_key:
        raise RuntimeError("GROQ_API_KEY not found in .env")

    payload = {
        "model": "llama-3.1-70b-versatile",
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user",   "content": user_message},
        ],
        "temperature": 0.1,
        "max_tokens": 800,
        "response_format": {"type": "json_object"},
    }

    req = urllib.request.Request(
        "https://api.groq.com/openai/v1/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        body = json.loads(resp.read().decode("utf-8"))
        content = body["choices"][0]["message"]["content"]
        return json.loads(content)


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
        "confidence": confidence,
        "thought": thought,
        "user_message": user_message_out,
        "tool_result": tool_result,
        "event_type": event.event_type.value,
        "urgency": event.urgency.value,
        "user_mode": event.user_mode,
        "timestamp": datetime.utcnow().isoformat(),
    }
