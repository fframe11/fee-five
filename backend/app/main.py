import os
from typing import List, Optional
from datetime import datetime, timedelta

from fastapi import FastAPI, Depends, HTTPException, status, Security
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from sqlalchemy import func

from .database import engine, get_db, Base, SessionLocal
from .models import User, UserPreference, EmergencyContact, AccessibilityPoint, Barrier, NavigationSession, EmergencyEvent, GTFSRoute, GTFSStop, GTFSTrip, GTFSStopTime, GTFSVehiclePosition
from .schemas import (
    UserCreate, UserResponse, UserUpdate,
    UserPreferenceResponse, UserPreferenceUpdate,
    EmergencyContactCreate, EmergencyContactResponse,
    AccessibilityPointCreate, AccessibilityPointResponse, CoordinateSchema,
    BarrierCreate, BarrierResponse,
    RouteRequestSchema, RouteResponseSchema,
    NavigationSessionResponse, NavigationSessionCreate,
    EmergencyEventCreate, EmergencyEventResponse,
    Token
)

from pydantic import BaseModel

# Initialize database schemas on startup (if local SQLite or DB is ready)
try:
    Base.metadata.create_all(bind=engine)
except Exception as e:
    print(f"Database auto-creation warning: {e}. Ensure target DB has PostGIS extension enabled.")

app = FastAPI(
    title="AI for Better Society - Accessible Mobile System Backend",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc"
)

# CORS setup
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# OAuth2 setup
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")

# Simple mock user authentication function (for prototype purposes)
def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)):
    # Prototype credential bypass: returns the first user or mock user
    user = db.query(User).first()
    if not user:
        # Create a default test user if none exists
        default_user = User(
            name="Default Accessibility User",
            email="user@access.org",
            password_hash="mock_hash",
            accessibility_mode="wheelchair"
        )
        db.add(default_user)
        db.commit()
        db.refresh(default_user)
        
        # Create default preferences
        pref = UserPreference(user_id=default_user.id)
        db.add(pref)
        db.commit()
        user = default_user
    return user

# 15.1 Authentication Routes
@app.post("/api/v1/auth/register", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
def register(user_data: UserCreate, db: Session = Depends(get_db)):
    # Validate existing email
    existing_user = db.query(User).filter(User.email == user_data.email).first()
    if existing_user:
        raise HTTPException(status_code=400, detail="Email is already registered")
    
    # Store user
    new_user = User(
        name=user_data.name,
        email=user_data.email,
        password_hash="hashed_" + user_data.password,  # Replace with actual secure hashing (bcrypt/argon2) in production
        accessibility_mode=user_data.accessibility_mode
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    
    # Initialize default preferences
    user_prefs = UserPreference(user_id=new_user.id)
    db.add(user_prefs)
    db.commit()
    
    return new_user

@app.post("/api/v1/auth/login", response_model=Token)
def login(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == form_data.username).first()
    if not user or not user.password_hash.endswith(form_data.password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return {"access_token": f"mock_token_{user.id}", "token_type": "bearer"}

@app.post("/api/v1/auth/refresh", response_model=Token)
def refresh_token():
    return {"access_token": "mock_refreshed_token", "token_type": "bearer"}

# 15.2 User Routes
@app.get("/api/v1/users/me", response_model=UserResponse)
def get_me(current_user: User = Depends(get_current_user)):
    return current_user

@app.patch("/api/v1/users/me", response_model=UserResponse)
def update_me(user_update: UserUpdate, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if user_update.name is not None:
        current_user.name = user_update.name
    if user_update.accessibility_mode is not None:
        current_user.accessibility_mode = user_update.accessibility_mode
    db.commit()
    db.refresh(current_user)
    return current_user

@app.get("/api/v1/users/me/preferences", response_model=UserPreferenceResponse)
def get_preferences(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    pref = db.query(UserPreference).filter(UserPreference.user_id == current_user.id).first()
    if not pref:
        pref = UserPreference(user_id=current_user.id)
        db.add(pref)
        db.commit()
        db.refresh(pref)
    return pref

@app.patch("/api/v1/users/me/preferences", response_model=UserPreferenceResponse)
def update_preferences(pref_update: UserPreferenceUpdate, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    pref = db.query(UserPreference).filter(UserPreference.user_id == current_user.id).first()
    if not pref:
        pref = UserPreference(user_id=current_user.id)
        db.add(pref)
    
    for key, value in pref_update.model_dump(exclude_unset=True).items():
        setattr(pref, key, value)
    
    db.commit()
    db.refresh(pref)
    return pref

# 15.3 Emergency (SOS) Routes
@app.post("/api/v1/emergency/events", response_model=EmergencyEventResponse)
def trigger_sos(event_data: EmergencyEventCreate, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    point_wkt = f"SRID=4326;POINT({event_data.location.longitude} {event_data.location.latitude})"
    db_event = EmergencyEvent(
        user_id=current_user.id,
        event_type=event_data.event_type,
        trigger_method=event_data.trigger_method,
        geom=point_wkt,
        accuracy=event_data.accuracy,
        status="active"
    )
    db.add(db_event)
    db.commit()
    db.refresh(db_event)
    
    # Return formatted response
    return EmergencyEventResponse(
        id=db_event.id,
        user_id=db_event.user_id,
        event_type=db_event.event_type,
        trigger_method=db_event.trigger_method,
        location=event_data.location,
        accuracy=db_event.accuracy,
        status=db_event.status,
        created_at=db_event.created_at,
        resolved_at=db_event.resolved_at
    )

@app.get("/api/v1/emergency/events/{id}", response_model=EmergencyEventResponse)
def get_sos(id: int, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    db_event = db.query(EmergencyEvent).filter(EmergencyEvent.id == id, EmergencyEvent.user_id == current_user.id).first()
    if not db_event:
        raise HTTPException(status_code=404, detail="Emergency event not found")
    
    # Extract coordinates via PostGIS function calls
    coords = db.query(
        func.ST_X(EmergencyEvent.geom).label("lon"),
        func.ST_Y(EmergencyEvent.geom).label("lat")
    ).filter(EmergencyEvent.id == id).first()
    
    return EmergencyEventResponse(
        id=db_event.id,
        user_id=db_event.user_id,
        event_type=db_event.event_type,
        trigger_method=db_event.trigger_method,
        location=CoordinateSchema(latitude=coords.lat, longitude=coords.lon),
        accuracy=db_event.accuracy,
        status=db_event.status,
        created_at=db_event.created_at,
        resolved_at=db_event.resolved_at
    )

@app.post("/api/v1/emergency/events/{id}/cancel", response_model=EmergencyEventResponse)
def cancel_sos(id: int, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    db_event = db.query(EmergencyEvent).filter(EmergencyEvent.id == id, EmergencyEvent.user_id == current_user.id).first()
    if not db_event:
        raise HTTPException(status_code=404, detail="Emergency event not found")
    
    db_event.status = "resolved"
    db_event.resolved_at = datetime.utcnow()
    db.commit()
    db.refresh(db_event)
    
    coords = db.query(
        func.ST_X(EmergencyEvent.geom).label("lon"),
        func.ST_Y(EmergencyEvent.geom).label("lat")
    ).filter(EmergencyEvent.id == id).first()
    
    return EmergencyEventResponse(
        id=db_event.id,
        user_id=db_event.user_id,
        event_type=db_event.event_type,
        trigger_method=db_event.trigger_method,
        location=CoordinateSchema(latitude=coords.lat, longitude=coords.lon),
        accuracy=db_event.accuracy,
        status=db_event.status,
        created_at=db_event.created_at,
        resolved_at=db_event.resolved_at
    )

# 15.4 Navigation & Rerouting Routes
@app.post("/api/v1/navigation/routes", response_model=RouteResponseSchema)
def calculate_accessible_route(route_req: RouteRequestSchema, db: Session = Depends(get_db)):
    # Standard routing mock response incorporating accessibility scoring rules
    # In a full deployment, this queries a local OSRM or Mapbox instance filtered by PostGIS barriers.
    
    # Find nearby active barriers to adjust routing score
    point_wkt = f"SRID=4326;POINT({route_req.origin.longitude} {route_req.origin.latitude})"
    nearby_barriers_count = db.query(Barrier).filter(
        Barrier.status == "active",
        func.ST_DWithin(
            Barrier.geom,
            func.ST_GeomFromText(point_wkt),
            0.05 # roughly 5km proximity for mock weighting
        )
    ).count()
    
    score = max(0.2, 1.0 - (nearby_barriers_count * 0.15))
    
    return RouteResponseSchema(
        route_id="route_" + os.urandom(4).hex(),
        distance_m=1450.0,
        duration_sec=1200.0 if route_req.mode == "wheelchair" else 950.0,
        accessibility_score=score,
        warnings=["avoid_stairs"] if route_req.mode == "wheelchair" else [],
        geometry=[route_req.origin, route_req.destination]
    )

@app.post("/api/v1/navigation/reroute", response_model=RouteResponseSchema)
def reroute_active_session(route_req: RouteRequestSchema, db: Session = Depends(get_db)):
    return calculate_accessible_route(route_req, db)

@app.get("/api/v1/navigation/accessibility")
def get_navigation_accessibility_meta():
    return {
        "status": "operational",
        "routing_constraints": ["stairs", "elevators", "surface_roughness"],
        "updated_at": datetime.utcnow()
    }

# 15.5 Accessibility Point & Barrier Routes
@app.post("/api/v1/accessibility/points", response_model=AccessibilityPointResponse, status_code=status.HTTP_201_CREATED)
def create_accessibility_point(point_data: AccessibilityPointCreate, db: Session = Depends(get_db)):
    point_wkt = f"SRID=4326;POINT({point_data.location.longitude} {point_data.location.latitude})"
    db_point = AccessibilityPoint(
        type=point_data.type,
        name=point_data.name,
        geom=point_wkt,
        status=point_data.status,
        accessibility_level=point_data.accessibility_level
    )
    db.add(db_point)
    db.commit()
    db.refresh(db_point)
    
    return AccessibilityPointResponse(
        id=db_point.id,
        type=db_point.type,
        name=db_point.name,
        location=point_data.location,
        status=db_point.status,
        accessibility_level=db_point.accessibility_level,
        updated_at=db_point.updated_at
    )

@app.get("/api/v1/accessibility/points", response_model=List[AccessibilityPointResponse])
def list_accessibility_points(db: Session = Depends(get_db)):
    # Query accessibility points and retrieve coordinates via ST_X/ST_Y
    points = db.query(AccessibilityPoint).all()
    response_list = []
    for p in points:
        coords = db.query(
            func.ST_X(AccessibilityPoint.geom).label("lon"),
            func.ST_Y(AccessibilityPoint.geom).label("lat")
        ).filter(AccessibilityPoint.id == p.id).first()
        
        response_list.append(
            AccessibilityPointResponse(
                id=p.id,
                type=p.type,
                name=p.name,
                location=CoordinateSchema(latitude=coords.lat, longitude=coords.lon),
                status=p.status,
                accessibility_level=p.accessibility_level,
                updated_at=p.updated_at
            )
        )
    return response_list

@app.post("/api/v1/accessibility/barriers", response_model=BarrierResponse, status_code=status.HTTP_201_CREATED)
def create_barrier(barrier_data: BarrierCreate, db: Session = Depends(get_db)):
    point_wkt = f"SRID=4326;POINT({barrier_data.location.longitude} {barrier_data.location.latitude})"
    db_barrier = Barrier(
        type=barrier_data.type,
        geom=point_wkt,
        severity=barrier_data.severity,
        status=barrier_data.status,
        expires_at=barrier_data.expires_at
    )
    db.add(db_barrier)
    db.commit()
    db.refresh(db_barrier)
    
    return BarrierResponse(
        id=db_barrier.id,
        type=db_barrier.type,
        location=barrier_data.location,
        severity=db_barrier.severity,
        status=db_barrier.status,
        reported_at=db_barrier.reported_at
    )

@app.get("/api/v1/accessibility/barriers", response_model=List[BarrierResponse])
def list_barriers(db: Session = Depends(get_db)):
    barriers = db.query(Barrier).filter(Barrier.status == "active").all()
    response_list = []
    for b in barriers:
        coords = db.query(
            func.ST_X(Barrier.geom).label("lon"),
            func.ST_Y(Barrier.geom).label("lat")
        ).filter(Barrier.id == b.id).first()
        
        response_list.append(
            BarrierResponse(
                id=b.id,
                type=b.type,
                location=CoordinateSchema(latitude=coords.lat, longitude=coords.lon),
                severity=b.severity,
                status=b.status,
                reported_at=b.reported_at
            )
        )
    return response_list

@app.get("/api/v1/accessibility/status")
def get_general_status():
    return {
        "status": "healthy",
        "on_device_processing_status": "enabled",
        "system_time": datetime.utcnow()
    }

class VisionRequest(BaseModel):
    image_base64: str
    prompt: Optional[str] = None

def load_env():
    # Search for .env file in parent directories
    for path in ['../.env', '../../.env', '.env']:
        if os.path.exists(path):
            try:
                with open(path, 'r', encoding='utf-8') as f:
                    for line in f:
                        if '=' in line and not line.strip().startswith('#'):
                            key, val = line.strip().split('=', 1)
                            os.environ[key.strip()] = val.strip()
            except Exception as e:
                print(f"Error reading .env file: {e}")

@app.post("/api/v1/vision/analyze")
def analyze_image(payload: VisionRequest):
    import urllib.request
    import urllib.error
    import json
    
    load_env()
    api_key = os.environ.get("Groq_api") or os.environ.get("GROQ_API_KEY")
    if not api_key:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Groq API key not found in .env file. Please check your workspace configuration."
        )
        
    prompt = payload.prompt or "คุณคือผู้ช่วยคนตาบอด อธิบายภาพถ่ายนี้และเตือนสิ่งกีดขวางเป็นภาษาไทยสั้นๆ 1 ประโยค"
    
    # Ensure correct Base64 Data URL format prefix
    img_data = payload.image_base64
    if not img_data.startswith("data:image"):
        # Remove whitespace/newlines from base64 if present
        img_clean = "".join(img_data.split())
        img_data = f"data:image/jpeg;base64,{img_clean}"
        
    url = "https://api.groq.com/openai/v1/chat/completions"
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }
    body = {
        "model": "llama-3.2-11b-vision-preview",
        "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": prompt
                    },
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": img_data
                        }
                    }
                ]
            }
        ],
        "temperature": 0.2
    }
    
    try:
        req = urllib.request.Request(
            url,
            data=json.dumps(body).encode('utf-8'),
            headers=headers,
            method='POST'
        )
        with urllib.request.urlopen(req, timeout=20) as response:
            res_body = response.read().decode('utf-8')
            res_json = json.loads(res_body)
            description = res_json["choices"][0]["message"]["content"]
            return {"description": description}
    except urllib.error.HTTPError as e:
        err_msg = e.read().decode('utf-8')
        print(f"Groq API Error Response: {err_msg}")
        raise HTTPException(
            status_code=e.code,
            detail=f"Groq API Error: {err_msg}"
        )
    except Exception as e:
        print(f"Vision analysis failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Vision server error: {str(e)}"
        )


class TransitRouteRequest(BaseModel):
    origin: CoordinateSchema
    destination: CoordinateSchema

class TransitRouteResponse(BaseModel):
    route: str
    walk_to_stop: str
    vehicle: str
    current_location: CoordinateSchema
    next_stop: str
    eta_minutes: int
    stops_remaining: int
    destination: str

@app.on_event("startup")
def startup_event():
    db = SessionLocal()
    try:
        Base.metadata.create_all(bind=engine)
        if not db.query(GTFSRoute).filter(GTFSRoute.route_id == "route_1").first():
            # 1. Route
            r1 = GTFSRoute(route_id="route_1", route_short_name="สาย 1", route_long_name="สยาม - เซ็นทรัลเวิลด์", route_type=3)
            db.add(r1)
            
            # 2. Stops
            stop_a = GTFSStop(stop_id="stop_a", stop_name="ลานน้ำพุ สยามพารากอน", geom="SRID=4326;POINT(100.5348 13.7461)")
            stop_b = GTFSStop(stop_id="stop_b", stop_name="สยามเซ็นเตอร์ ฝั่งตะวันตก", geom="SRID=4326;POINT(100.5335 13.7455)")
            stop_c = GTFSStop(stop_id="stop_c", stop_name="BTS สยาม ทางออก 3", geom="SRID=4326;POINT(100.5365 13.7461)")
            stop_d = GTFSStop(stop_id="stop_d", stop_name="หน้าเซ็นทรัลเวิลด์", geom="SRID=4326;POINT(100.5380 13.7450)")
            db.add_all([stop_a, stop_b, stop_c, stop_d])
            db.commit()
            
            # 3. Trips
            t1 = GTFSTrip(trip_id="trip_102", route_id="route_1", service_id="weekday")
            db.add(t1)
            db.commit()
            
            # 4. Stop Times
            st1 = GTFSStopTime(trip_id="trip_102", stop_id="stop_a", arrival_time="14:00:00", departure_time="14:00:00", stop_sequence=1)
            st2 = GTFSStopTime(trip_id="trip_102", stop_id="stop_b", arrival_time="14:05:00", departure_time="14:05:00", stop_sequence=2)
            st3 = GTFSStopTime(trip_id="trip_102", stop_id="stop_c", arrival_time="14:10:00", departure_time="14:10:00", stop_sequence=3)
            st4 = GTFSStopTime(trip_id="trip_102", stop_id="stop_d", arrival_time="14:15:00", departure_time="14:15:00", stop_sequence=4)
            db.add_all([st1, st2, st3, st4])
            
            # 5. Vehicle Position
            v1 = GTFSVehiclePosition(
                vehicle_id="BUS-102",
                trip_id="trip_102",
                geom="SRID=4326;POINT(100.5348 13.7461)",
                current_stop_id="stop_a",
                current_status="STOPPED_AT",
                delay_seconds=180
            )
            db.add(v1)
            db.commit()
            print("Successfully seeded GTFS database.")
    except Exception as e:
        print(f"Error seeding database: {e}")
    finally:
        db.close()

@app.post("/api/v1/navigation/transit-route", response_model=TransitRouteResponse)
def calculate_transit_route(payload: TransitRouteRequest, db: Session = Depends(get_db)):
    origin_point = f"SRID=4326;POINT({payload.origin.longitude} {payload.origin.latitude})"
    dest_point = f"SRID=4326;POINT({payload.destination.longitude} {payload.destination.latitude})"
    
    try:
        nearest_stop = db.query(GTFSStop).order_by(
            func.ST_Distance(
                GTFSStop.geom,
                func.ST_GeomFromText(origin_point)
            )
        ).first()
        
        nearest_dest_stop = db.query(GTFSStop).order_by(
            func.ST_Distance(
                GTFSStop.geom,
                func.ST_GeomFromText(dest_point)
            )
        ).first()
    except Exception:
        nearest_stop = db.query(GTFSStop).filter(GTFSStop.stop_id == "stop_a").first()
        nearest_dest_stop = db.query(GTFSStop).filter(GTFSStop.stop_id == "stop_d").first()
        
    if not nearest_stop or not nearest_dest_stop:
        raise HTTPException(status_code=404, detail="No nearby stops found in GTFS database.")
        
    vehicle = db.query(GTFSVehiclePosition).first()
    if not vehicle:
        raise HTTPException(status_code=404, detail="No active vehicles found.")
        
    try:
        vehicle_lon = db.query(func.ST_X(GTFSVehiclePosition.geom)).filter(GTFSVehiclePosition.vehicle_id == vehicle.vehicle_id).scalar()
        vehicle_lat = db.query(func.ST_Y(GTFSVehiclePosition.geom)).filter(GTFSVehiclePosition.vehicle_id == vehicle.vehicle_id).scalar()
    except Exception:
        vehicle_lon, vehicle_lat = 100.5348, 13.7461
        
    route = db.query(GTFSRoute).filter(GTFSRoute.route_id == "route_1").first()
    route_name = route.route_short_name if route else "สาย 1"
    
    return TransitRouteResponse(
        route=route_name,
        walk_to_stop="180 เมตร",
        vehicle=vehicle.vehicle_id,
        current_location=CoordinateSchema(latitude=vehicle_lat, longitude=vehicle_lon),
        next_stop="สยามเซ็นเตอร์ ฝั่งตะวันตก",
        eta_minutes=6,
        stops_remaining=3,
        destination=nearest_dest_stop.stop_name
    )


def calculate_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    import math
    R = 6371.0  # Radius of earth in km
    lat1_rad = math.radians(lat1)
    lon1_rad = math.radians(lon1)
    lat2_rad = math.radians(lat2)
    lon2_rad = math.radians(lon2)
    dlon = lon2_rad - lon1_rad
    dlat = lat2_rad - lat1_rad
    a = math.sin(dlat / 2)**2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(dlon / 2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c

class MultiModalRequest(BaseModel):
    origin: CoordinateSchema
    destination: CoordinateSchema
    preference: str = "balanced"  # balanced, fastest, cheapest, least_walking

class JourneyOption(BaseModel):
    mode: str
    mode_name: str
    price: float
    price_text: str
    duration_minutes: int
    walk_distance_meters: int
    score: float
    is_recommended: bool
    reason: str
    icon: str

@app.post("/api/v1/navigation/multi-modal-recommendations", response_model=List[JourneyOption])
def get_multi_modal_recommendations(payload: MultiModalRequest, db: Session = Depends(get_db)):
    lat1, lon1 = payload.origin.latitude, payload.origin.longitude
    lat2, lon2 = payload.destination.latitude, payload.destination.longitude
    
    # Fallback to Siam Paragon to CentralWorld if coordinates are empty/zero
    if lat1 == 0.0 or lon1 == 0.0 or lat2 == 0.0 or lon2 == 0.0:
        lat1, lon1 = 13.7461, 100.5348
        lat2, lon2 = 13.7450, 100.5380
        
    d_km = calculate_distance(lat1, lon1, lat2, lon2)
    if d_km < 0.1:
        d_km = 0.37  # Siam Paragon to Siam BTS outlet distance approximation
        
    # 1. Walkability Feasibility Engine (Walkability Score formula)
    # Walk Score = Distance Score (25%) + Time Score (20%) + Sidewalk Score (20%) + Crossing Safety Score (15%) + Accessibility Score (15%) + Route Directness (5%)
    dist_score = max(0.0, 100.0 * (1.0 - d_km / 3.0)) # 3km max walk
    time_score = max(0.0, 100.0 * (1.0 - (d_km * 12.0) / 36.0)) # 36 mins max walk
    sidewalk_score = 90.0
    crossing_safety_score = 80.0
    accessibility_score = 85.0
    route_directness = 95.0
    
    walk_score = (
        (dist_score * 0.25) +
        (time_score * 0.20) +
        (sidewalk_score * 0.20) +
        (crossing_safety_score * 0.15) +
        (accessibility_score * 0.15) +
        (route_directness * 0.05)
    )
    
    if walk_score >= 90:
        walk_status = "เดินได้ดี 🟢"
    elif walk_score >= 75:
        walk_status = "แนะนำให้เดิน 🟢"
    elif walk_score >= 50:
        walk_status = "เดินได้ แต่ควรพิจารณา 🟡"
    else:
        walk_status = "ไม่แนะนำให้เดิน 🔴"

    # 2. Fare calculations based on transport rules
    # A. Bus Price: Air/Electric Bus base 15 Baht, up to 25 Baht. Hot bus: 8 Baht.
    bus_price = 15.0
    if d_km > 3.0:
        bus_price = min(25.0, 15.0 + float(int((d_km - 3.0) / 3.0) * 2))
        
    # B. BTS Train Price: 17 Baht base, up to 62 Baht max
    bts_stations = max(1, int(d_km * 1.5))
    bts_price = min(62.0, 17.0 + float((bts_stations - 1) * 4))
    
    # C. Taxi / Ride-Hailing (Grab / Bolt) Price:
    # 35 Baht base for km 1
    # km 2-10 = 6.50 Baht/km
    # km 11-20 = 7.00 Baht/km
    # km 21-40 = 8.00 Baht/km
    # Traffic jam delay time (assumed 3 mins at 3 Baht/min)
    dist_fare = 35.0
    remaining_d = d_km - 1.0
    if remaining_d > 0:
        dist_fare += min(remaining_d, 9.0) * 6.50
        remaining_d -= 9.0
    if remaining_d > 0:
        dist_fare += min(remaining_d, 10.0) * 7.00
        remaining_d -= 10.0
    if remaining_d > 0:
        dist_fare += remaining_d * 8.00
        
    traffic_delay_charge = 3.0 * 3.0
    taxi_price = dist_fare + traffic_delay_charge
    
    grab_price = round(taxi_price * 1.15, 0)
    bolt_price = round(taxi_price * 0.95, 0)

    # 3. Mode options
    options = [
        {
            "mode": "bus",
            "mode_name": f"รถเมล์แอร์ (สาย 1)",
            "price": bus_price,
            "price_text": f"{int(bus_price)} บาท (รถร้อน 8 บาท)",
            "duration_minutes": int(d_km * 3.0) + 12,
            "walk_distance_meters": 250,
            "icon": "directions_bus",
            "reason": ""
        },
        {
            "mode": "train",
            "mode_name": "รถไฟฟ้า (BTS / MRT)",
            "price": bts_price,
            "price_text": f"{int(bts_price)} บาท (BTS 17-62 / MRT 17-44)",
            "duration_minutes": int(d_km * 2.0) + 8,
            "walk_distance_meters": 450,
            "icon": "directions_transit",
            "reason": ""
        },
        {
            "mode": "ride_hailing",
            "mode_name": "แท็กซี่ (Grab / Bolt)",
            "price": grab_price,
            "price_text": f"Grab {int(grab_price)} บาท / Bolt {int(bolt_price)} บาท",
            "duration_minutes": int(d_km * 2.5) + 5,
            "walk_distance_meters": 50,
            "icon": "local_taxi",
            "reason": ""
        },
        {
            "mode": "walking",
            "mode_name": f"เดินเท้า ({walk_status})",
            "price": 0.0,
            "price_text": "ฟรี",
            "duration_minutes": int(d_km * 12.0),
            "walk_distance_meters": int(d_km * 1000.0),
            "icon": "directions_walk",
            "reason": ""
        }
    ]

    # 4. Multi-Modal Recommendation Priority weights scoring
    pref = payload.preference.lower()
    if pref == "fastest":
        w_price, w_time, w_walk = 0.10, 0.60, 0.30
    elif pref == "cheapest":
        w_price, w_time, w_walk = 0.60, 0.20, 0.20
    elif pref == "least_walking":
        w_price, w_time, w_walk = 0.20, 0.20, 0.60
    else: # balanced
        w_price, w_time, w_walk = 0.35, 0.35, 0.30

    max_price = 150.0
    max_time = 60.0
    max_walk = 3000.0

    scored_options = []
    for opt in options:
        s_price = 100.0 * (1.0 - (opt["price"] / max_price))
        s_time = 100.0 * (1.0 - (opt["duration_minutes"] / max_time))
        s_walk = 100.0 * (1.0 - (opt["walk_distance_meters"] / max_walk))
        
        total_score = (s_price * w_price) + (s_time * w_time) + (s_walk * w_walk)
        opt["score"] = round(total_score, 1)
        opt["is_recommended"] = False
        scored_options.append(opt)

    scored_options.sort(key=lambda x: x["score"], reverse=True)
    scored_options[0]["is_recommended"] = True

    for opt in scored_options:
        if opt["is_recommended"]:
            if opt["mode"] == "bus":
                opt["reason"] = f"แนะนำรถเมล์: ป้ายห่าง {opt['walk_distance_meters']} ม. ค่าเดินทาง {opt['price_text']} ประหยัดและเสถียรที่สุด"
            elif opt["mode"] == "train":
                opt["reason"] = f"แนะนำรถไฟฟ้า: เลี่ยงรถติด ทำเวลาได้เร็วที่สุดใน {opt['duration_minutes']} นาที ปลอดภัยตลอดชานชาลา"
            elif opt["mode"] == "ride_hailing":
                opt["reason"] = f"แนะนำแท็กซี่/Grab: ลดระยะการเดินเหลือ {opt['walk_distance_meters']} ม. ส่งตรงจุดหมาย สะดวกกับผู้ต้องการสิ่งอำนวยความสะดวก"
            elif opt["mode"] == "walking":
                opt["reason"] = f"แนะนำเดินเท้า: ระยะทางใกล้เพียง {opt['walk_distance_meters']} ม. เส้นทาง {walk_status} ไม่มีค่าใช้จ่ายและปลอดภัย"
        else:
            opt["reason"] = f"ตัวเลือกสำรอง: ใช้เวลา {opt['duration_minutes']} นาที ราคา {opt['price_text']}"

    return scored_options
