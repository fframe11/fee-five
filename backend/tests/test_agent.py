"""
Fee Five — Smart Accessibility Agent: Unit + Integration Tests
Run: pytest backend/tests/test_agent.py -v
"""
import pytest
import sys
import os

# Ensure backend/app is importable
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from app.agent.event_classifier import classify_event, EventType, Urgency
from app.agent.memory import AgentMemoryStore, AgentTurn
from app.agent.tools import (
    obstacle_alert, reroute_navigation, trigger_sos,
    suggest_camera_scan, get_route_barriers, get_infrastructure_status, speak_instruction,
)
from datetime import datetime


# ============================================================
# Event Classifier Tests
# ============================================================

class TestEventClassifier:

    def test_gps_barrier_high_severity(self):
        raw = {
            "event_type": "gps_barrier",
            "user_id": 1,
            "user_mode": "wheelchair",
            "lat": 13.7456,
            "lng": 100.5355,
            "barrier_info": {"id": 1, "type": "construction", "severity": "high", "distance_m": "45.2"},
        }
        event = classify_event(raw)
        assert event.event_type == EventType.GPS_BARRIER
        assert event.urgency == Urgency.HIGH
        assert event.user_mode == "wheelchair"

    def test_gps_barrier_medium_severity(self):
        raw = {
            "event_type": "gps_barrier",
            "user_id": 1,
            "user_mode": "visual",
            "lat": 13.7448,
            "lng": 100.5332,
            "barrier_info": {"severity": "medium"},
        }
        event = classify_event(raw)
        assert event.urgency == Urgency.MEDIUM

    def test_voice_command_sos_keyword(self):
        raw = {
            "event_type": "voice_command",
            "user_id": 2,
            "user_mode": "visual",
            "lat": 13.7460,
            "lng": 100.5350,
            "voice_text": "ช่วยด้วย",
        }
        event = classify_event(raw)
        assert event.event_type == EventType.VOICE_COMMAND
        assert event.urgency == Urgency.CRITICAL

    def test_voice_command_normal(self):
        raw = {
            "event_type": "voice_command",
            "user_id": 2,
            "user_mode": "wheelchair",
            "lat": 13.7460,
            "lng": 100.5350,
            "voice_text": "ข้างหน้าเป็นอะไร",
        }
        event = classify_event(raw)
        assert event.urgency == Urgency.MEDIUM

    def test_push_elevator_down(self):
        raw = {
            "event_type": "push_event",
            "user_id": 3,
            "user_mode": "wheelchair",
            "lat": 13.7461,
            "lng": 100.5365,
            "push_payload": {"type": "elevator_down", "message": "ลิฟต์ BTS ทางออก 3 ปิด"},
        }
        event = classify_event(raw)
        assert event.event_type == EventType.PUSH_EVENT
        assert event.urgency == Urgency.HIGH

    def test_camera_scan_medium_urgency(self):
        raw = {
            "event_type": "camera_scan",
            "user_id": 1,
            "user_mode": "visual",
            "lat": 13.7460,
            "lng": 100.5350,
        }
        event = classify_event(raw)
        assert event.event_type == EventType.CAMERA_SCAN
        assert event.urgency == Urgency.MEDIUM
        assert event.camera_frame_b64 is None

    def test_motion_fall_detected(self):
        raw = {
            "event_type": "motion_anomaly",
            "user_id": 4,
            "user_mode": "hearing",
            "lat": 13.7455,
            "lng": 100.5340,
            "motion_data": {"pattern": "fall_detected", "magnitude": 32.5},
        }
        event = classify_event(raw)
        assert event.event_type == EventType.MOTION_ANOMALY
        assert event.urgency == Urgency.CRITICAL

    def test_unknown_event_type_raises(self):
        raw = {
            "event_type": "unknown_event",
            "user_id": 1,
            "user_mode": "wheelchair",
            "lat": 0.0,
            "lng": 0.0,
        }
        with pytest.raises(ValueError, match="Unknown event_type"):
            classify_event(raw)


# ============================================================
# Agent Memory Tests
# ============================================================

class TestAgentMemory:

    def test_create_session(self):
        store = AgentMemoryStore()
        session = store.get_or_create(user_id=99, user_mode="wheelchair")
        assert session.user_id == 99
        assert session.user_mode == "wheelchair"
        assert len(session.turns) == 0

    def test_returns_same_session(self):
        store = AgentMemoryStore()
        s1 = store.get_or_create(user_id=99, user_mode="wheelchair")
        s2 = store.get_or_create(user_id=99, user_mode="wheelchair")
        assert s1 is s2

    def test_add_and_retrieve_turns(self):
        store = AgentMemoryStore()
        session = store.get_or_create(user_id=10, user_mode="visual")
        turn = AgentTurn(
            timestamp=datetime.utcnow(),
            event_type="gps_barrier",
            user_mode="visual",
            thought="There is a pole ahead",
            action="obstacle_alert",
            action_args={"message": "ระวังเสา", "risk_level": "high", "user_mode": "visual"},
            outcome="ok",
        )
        session.add_turn(turn)
        store.record_turn(10, turn)
        summary = session.get_context_summary()
        assert "obstacle_alert" in summary

    def test_max_turns_buffer(self):
        store = AgentMemoryStore()
        session = store.get_or_create(user_id=20, user_mode="wheelchair")
        for i in range(15):  # Add more than MAX_MESSAGES_PER_SESSION (10)
            turn = AgentTurn(
                timestamp=datetime.utcnow(),
                event_type="gps_barrier",
                user_mode="wheelchair",
                thought=f"turn {i}",
                action="obstacle_alert",
                action_args={},
                outcome="ok",
            )
            session.add_turn(turn)
        assert len(session.turns) == 10  # capped at MAX

    def test_clear_session(self):
        store = AgentMemoryStore()
        store.get_or_create(user_id=30, user_mode="hearing")
        store.clear(30)
        assert 30 not in store._sessions


# ============================================================
# Tool Tests
# ============================================================

class TestTools:

    # Tool 1: obstacle_alert
    def test_obstacle_alert_wheelchair_uses_audio(self):
        result = obstacle_alert("ระวังบันได", "high", "wheelchair")
        assert result["status"] == "ok"
        assert result["alert"]["modality"]["audio"] is True
        assert result["alert"]["modality"]["haptic"] is True

    def test_obstacle_alert_hearing_no_audio(self):
        result = obstacle_alert("ระวังสิ่งกีดขวาง", "medium", "hearing")
        assert result["alert"]["modality"]["audio"] is False
        assert result["alert"]["modality"]["visual"] is True

    def test_obstacle_alert_visual_no_visual_flag(self):
        result = obstacle_alert("ระวังเสาข้างหน้า", "high", "visual")
        assert result["alert"]["modality"]["visual"] is False
        assert result["alert"]["modality"]["audio"] is True

    # Tool 2: reroute_navigation
    def test_reroute_wheelchair(self):
        result = reroute_navigation(
            user_id=1, reason="stairs_detected",
            current_lat=13.7456, current_lng=100.5355,
            destination="BTS สยาม", user_mode="wheelchair",
        )
        assert result["status"] == "ok"
        assert "ทางลาด" in result["reroute"]["new_instruction"] or "ลิฟต์" in result["reroute"]["new_instruction"]

    # Tool 3: trigger_sos
    def test_trigger_sos(self):
        result = trigger_sos(user_id=1, lat=13.7460, lng=100.5350, trigger_method="manual")
        assert result["status"] == "ok"
        assert result["sos_event"]["trigger_method"] == "manual"
        assert result["sos_event"]["action"] == "notify_emergency_contacts"

    # Tool 4: suggest_camera_scan
    def test_suggest_camera_scan(self):
        result = suggest_camera_scan("พบโซน risk สูง", "บริเวณก่อสร้าง พระราม 1")
        assert result["status"] == "ok"
        assert result["suggestion"]["dismissable"] is True

    # Tool 6: get_route_barriers
    def test_get_route_barriers_nearby(self):
        # Should find barrier at (13.7456, 100.5355) within 200m
        result = get_route_barriers(lat=13.7456, lng=100.5355, radius_m=200.0)
        assert result["status"] == "ok"
        assert result["count"] >= 1

    def test_get_route_barriers_far(self):
        # Chiang Mai coordinates — no barriers
        result = get_route_barriers(lat=18.7883, lng=98.9853, radius_m=200.0)
        assert result["count"] == 0

    # Tool 7: get_infrastructure_status
    def test_get_infrastructure_unavailable(self):
        # BTS Siam area — should find under_maintenance elevator
        result = get_infrastructure_status(lat=13.7452, lng=100.5342, radius_m=300.0)
        assert result["status"] == "ok"
        # Should detect 'under_maintenance' elevator at exit 5
        statuses = [x["status"] for x in result["infrastructure"]]
        assert "under_maintenance" in statuses

    # Tool 8: speak_instruction
    def test_speak_instruction_hearing_no_audio(self):
        result = speak_instruction("เดินตรงไปข้างหน้า", user_mode="hearing")
        assert result["instruction"]["audio"] is False
        assert result["instruction"]["display"] is True

    def test_speak_instruction_visual_has_audio(self):
        result = speak_instruction("ระวังเสาไฟฟ้า", user_mode="visual")
        assert result["instruction"]["audio"] is True
