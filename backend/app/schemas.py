from pydantic import BaseModel, EmailStr, Field
from typing import List, Optional
from datetime import datetime

# Common Geospatial Schemas
class CoordinateSchema(BaseModel):
    latitude: float = Field(..., ge=-90, le=90, description="Latitude range: -90 to 90")
    longitude: float = Field(..., ge=-180, le=180, description="Longitude range: -180 to 180")

class RouteSchema(BaseModel):
    coordinates: List[CoordinateSchema]

# Authentication / User Schemas
class UserBase(BaseModel):
    name: str = Field(..., min_length=2, max_length=100)
    email: EmailStr
    accessibility_mode: str = Field(default="visual", description="Mode: 'visual'")

class UserCreate(UserBase):
    password: str = Field(..., min_length=6, max_length=100)

class UserUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=2, max_length=100)
    accessibility_mode: Optional[str] = Field(default="visual", description="Mode: 'visual'")

class UserResponse(UserBase):
    id: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True

# Token Schemas
class Token(BaseModel):
    access_token: str
    token_type: str

class TokenData(BaseModel):
    email: Optional[str] = None

# Preferences Schemas
class UserPreferenceBase(BaseModel):
    voice_enabled: bool = True
    haptic_enabled: bool = True
    high_contrast: bool = False
    font_scale: float = 1.0
    language: str = "th"

class UserPreferenceUpdate(BaseModel):
    voice_enabled: Optional[bool] = None
    haptic_enabled: Optional[bool] = None
    high_contrast: Optional[bool] = None
    font_scale: Optional[float] = None
    language: Optional[str] = None

class UserPreferenceResponse(UserPreferenceBase):
    id: int
    user_id: int
    updated_at: datetime

    class Config:
        from_attributes = True

# Emergency Contact Schemas
class EmergencyContactBase(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    phone: str = Field(..., min_length=9, max_length=20)
    relationship: str = Field(..., min_length=1, max_length=50)

class EmergencyContactCreate(EmergencyContactBase):
    pass

class EmergencyContactResponse(EmergencyContactBase):
    id: int
    user_id: int
    created_at: datetime

    class Config:
        from_attributes = True

# Accessibility Point Schemas
class AccessibilityPointBase(BaseModel):
    type: str = Field(..., description="elevator, ramp, crossing")
    name: str
    status: str = "available"
    accessibility_level: Optional[str] = None

class AccessibilityPointCreate(AccessibilityPointBase):
    location: CoordinateSchema

class AccessibilityPointResponse(AccessibilityPointBase):
    id: int
    location: CoordinateSchema
    updated_at: datetime

    class Config:
        from_attributes = True

# Barrier Schemas
class BarrierBase(BaseModel):
    type: str = Field(..., description="broken_sidewalk, flooding, obstacle")
    severity: str = "medium"
    status: str = "active"
    expires_at: Optional[datetime] = None

class BarrierCreate(BarrierBase):
    location: CoordinateSchema

class BarrierResponse(BarrierBase):
    id: int
    location: CoordinateSchema
    reported_at: datetime

    class Config:
        from_attributes = True

# Navigation Schemas
class RouteRequestSchema(BaseModel):
    origin: CoordinateSchema
    destination: CoordinateSchema
    mode: str = "wheelchair"  # wheelchair, visual, speech_hearing

class RouteResponseSchema(BaseModel):
    route_id: str
    distance_m: float
    duration_sec: float
    accessibility_score: float
    warnings: List[str]
    geometry: List[CoordinateSchema]

class NavigationSessionCreate(BaseModel):
    origin: CoordinateSchema
    destination: CoordinateSchema

class NavigationSessionResponse(BaseModel):
    id: int
    user_id: int
    origin: CoordinateSchema
    destination: CoordinateSchema
    started_at: datetime
    ended_at: Optional[datetime] = None
    status: str

    class Config:
        from_attributes = True

# Emergency Event Schemas
class EmergencyEventCreate(BaseModel):
    event_type: str = "SOS"
    trigger_method: str = Field(..., description="manual, gesture")
    location: CoordinateSchema
    accuracy: Optional[float] = None

class EmergencyEventResponse(BaseModel):
    id: int
    user_id: int
    event_type: str
    trigger_method: str
    location: CoordinateSchema
    accuracy: Optional[float] = None
    status: str
    created_at: datetime
    resolved_at: Optional[datetime] = None

    class Config:
        from_attributes = True
