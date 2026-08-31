"""
Fee Five — Agent Session Memory
Stores per-user conversation context for the ReAct reasoning loop.
In-memory for prototype; extend to Redis for production.
"""
from __future__ import annotations
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Optional
import threading

MAX_MESSAGES_PER_SESSION = 10   # keep last N agent turns
SESSION_TTL_MINUTES = 60        # auto-expire idle sessions


@dataclass
class AgentTurn:
    """A single Thought → Action → Observation cycle."""
    timestamp: datetime
    event_type: str          # gps_barrier, voice_command, push_event, camera_scan, motion_anomaly
    user_mode: str           # wheelchair, visual, hearing
    thought: str
    action: str
    action_args: dict
    outcome: str
    location: Optional[tuple[float, float]] = None  # (lat, lng)


@dataclass
class AgentSession:
    user_id: int
    user_mode: str
    created_at: datetime = field(default_factory=datetime.utcnow)
    last_active: datetime = field(default_factory=datetime.utcnow)
    turns: list[AgentTurn] = field(default_factory=list)
    current_route_id: Optional[str] = None
    current_destination: Optional[str] = None

    def add_turn(self, turn: AgentTurn) -> None:
        self.turns.append(turn)
        self.last_active = datetime.utcnow()
        # Keep only the last N turns to bound context window
        if len(self.turns) > MAX_MESSAGES_PER_SESSION:
            self.turns = self.turns[-MAX_MESSAGES_PER_SESSION:]

    def get_context_summary(self) -> str:
        """Return a compact string summary of recent turns for LLM context."""
        if not self.turns:
            return "No previous interactions in this session."
        lines = []
        for t in self.turns[-3:]:  # send last 3 turns to LLM
            lines.append(
                f"[{t.event_type}] Thought: {t.thought} | Action: {t.action} | Outcome: {t.outcome}"
            )
        return "\n".join(lines)

    def is_expired(self) -> bool:
        return datetime.utcnow() - self.last_active > timedelta(minutes=SESSION_TTL_MINUTES)


class AgentMemoryStore:
    """Thread-safe in-memory store for all active agent sessions."""

    def __init__(self) -> None:
        self._sessions: dict[int, AgentSession] = {}
        self._lock = threading.Lock()

    def get_or_create(self, user_id: int, user_mode: str) -> AgentSession:
        with self._lock:
            session = self._sessions.get(user_id)
            if session is None or session.is_expired():
                session = AgentSession(user_id=user_id, user_mode=user_mode)
                self._sessions[user_id] = session
            else:
                # Update mode if user switched
                session.user_mode = user_mode
                session.last_active = datetime.utcnow()
            return session

    def update_route(self, user_id: int, route_id: str, destination: str) -> None:
        with self._lock:
            session = self._sessions.get(user_id)
            if session:
                session.current_route_id = route_id
                session.current_destination = destination

    def record_turn(self, user_id: int, turn: AgentTurn) -> None:
        with self._lock:
            session = self._sessions.get(user_id)
            if session:
                session.add_turn(turn)

    def clear(self, user_id: int) -> None:
        with self._lock:
            self._sessions.pop(user_id, None)

    def purge_expired(self) -> int:
        """Remove all expired sessions. Returns count purged."""
        with self._lock:
            expired = [uid for uid, s in self._sessions.items() if s.is_expired()]
            for uid in expired:
                del self._sessions[uid]
            return len(expired)


# Singleton store — shared across all request handlers
agent_memory = AgentMemoryStore()
