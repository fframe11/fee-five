# AI for a Better Society — Mobile Application System Design

## 1. Project Scope

This document defines the detailed system setup for the **mobile application only**.

The system targets three user groups:

1. People with visual impairments
2. Wheelchair users / people with mobility impairments
3. People with speech or hearing impairments

The prototype does **not** include a government dashboard, city command center, administrator dashboard, or government-side workflow.

The mobile application focuses on:

- Personal safety
- Accessible navigation
- Real-time hazard awareness
- Emergency SOS
- Personalized accessibility settings
- Privacy-first processing

The source brief describes the core problems as reactive assistance, sudden visual hazards, inaccessible routes such as broken elevators or damaged sidewalks, and difficulty making voice emergency calls. It proposes proactive mobile AI, dynamic rerouting, and gesture-based SOS. 

---

# 2. Product Vision

The application acts as a **personal accessibility and safety assistant** on the user's smartphone.

Instead of requiring the user to manually search for every problem, the application continuously uses available smartphone capabilities such as:

- Camera
- GPS
- Accelerometer
- Gyroscope
- Haptic feedback
- Text-to-speech
- Microphone / user interaction where appropriate

The application should detect or receive accessibility information and provide the user with an immediate, understandable action.

Core principle:

> **Detect → Understand → Alert → Assist → Recover**

Example:

```text
Obstacle detected
      ↓
Estimate risk
      ↓
Notify user
      ↓
User avoids obstacle
```

For navigation:

```text
Destination selected
      ↓
Check accessible route
      ↓
Start navigation
      ↓
Barrier detected
      ↓
Calculate alternative route
      ↓
Continue navigation
```

For emergency:

```text
SOS triggered
      ↓
3-second confirmation
      ↓
Get GPS location
      ↓
Create emergency event
      ↓
Send emergency information
      ↓
Notify emergency contact
```

---

# 3. User Personas

## 3.1 Visual Impairment User

Primary needs:

- Detect obstacles ahead
- Receive audio warnings
- Receive haptic warnings
- Navigate without relying heavily on visual UI
- Trigger SOS quickly

Primary interface:

- Voice
- Spatial/audio feedback
- Haptic feedback
- Large high-contrast controls

Example:

```text
AI detects:
"Low obstacle — 2 meters ahead"

Output:
Audio: "สิ่งกีดขวางด้านหน้า 2 เมตร"
Haptic: Short repeated vibration
```

The source brief specifically proposes on-device visual hazard prediction and notification 2–3 seconds before a potential collision.

---

## 3.2 Wheelchair / Mobility User

Primary needs:

- Accessible routes
- Avoid stairs
- Avoid broken sidewalks
- Detect unavailable elevators
- Automatically reroute when a route becomes inaccessible

Primary interface:

- Map
- Large route controls
- Clear accessibility status
- Visual and optional voice navigation

Example:

```text
Destination: BTS Station

Route A
⚠ Elevator unavailable

Route B
♿ Accessible
18 min

→ Select Route B
```

The source brief explicitly describes dynamic barrier interception and automatic rerouting when barriers or unavailable elevators are detected.

---

## 3.3 Speech / Hearing Impairment User

Primary needs:

- Non-voice emergency interaction
- Visual emergency status
- Gesture-based SOS
- Text-based information
- Haptic notifications

Primary interface:

- Visual alerts
- Large buttons
- Gesture recognition
- Haptic feedback

Example:

```text
User performs SOS gesture
        ↓
AI detects gesture
        ↓
3-second confirmation
        ↓
SOS activated
        ↓
GPS location attached
```

The source brief proposes front-camera gesture detection for emergency SOS.

---

# 4. Application Information Architecture

The application should use a simple four-part bottom navigation structure:

```text
Home
Navigate
SOS
Profile
```

## Home

Purpose:

- Current status
- Quick access to assistance mode
- Current location
- Recent destination
- Quick SOS

## Navigate

Purpose:

- Search destination
- Select accessible route
- Start navigation
- Receive rerouting alerts

## SOS

Purpose:

- Manual emergency SOS
- Gesture SOS
- Emergency countdown
- Emergency contact status

## Profile

Purpose:

- User disability/accessibility mode
- Emergency contacts
- Accessibility preferences
- Voice/haptic settings
- Privacy settings

---

# 5. First-Time Onboarding

## Screen 1 — Welcome

```text
Welcome

Your personal
Accessibility & Safety Assistant

[ Get Started ]
```

## Screen 2 — Select User Mode

```text
How should the app assist you?

[ 👁 Visual Assistance ]

[ ♿ Wheelchair Assistance ]

[ 🖐 Speech / Hearing Assistance ]
```

The selected mode changes the default interface and available assistance features.

## Screen 3 — Permissions

Request permissions only when needed.

```text
Location
→ Navigation and emergency location

Camera
→ Hazard / gesture detection

Notifications
→ Safety alerts

Microphone
→ Optional voice interaction
```

The application should explain why each permission is needed before requesting it.

## Screen 4 — Emergency Contact

```text
Emergency Contact

Name
Phone

[ Save Contact ]
```

---

# 6. Home Screen System

The Home screen changes according to the user's selected mode.

Common components:

```text
Header
Current Location
Primary Assistance Card
Quick Navigation
SOS
Recent Activity
Bottom Navigation
```

Example:

```text
┌─────────────────────────┐
│ Hello, User             │
│ 📍 Current location     │
│                         │
│ ┌─────────────────────┐ │
│ │ Safety Status        │ │
│ │ ✓ Ready              │ │
│ └─────────────────────┘ │
│                         │
│ Where do you want to go?│
│ [ Search destination ]  │
│                         │
│ [ 🧭 Navigate ] [ 🆘 ] │
│                         │
│ Recent                  │
│ • BTS Station            │
│ • University             │
│                         │
│ Home Navigate SOS Profile│
└─────────────────────────┘
```

---

# 7. Vision Assist System

## 7.1 Camera Pipeline

```text
Camera Frame
     ↓
Frame Preprocessing
     ↓
Object Detection
     ↓
Depth Estimation
     ↓
Obstacle Classification
     ↓
Risk Estimation
     ↓
Alert Decision
     ↓
Audio + Haptic
```

## 7.2 AI Components

Prototype target:

- YOLOv8-Lite or similar mobile object detector
- Monocular depth estimation
- TensorFlow Lite / Core ML depending on platform

The source brief proposes YOLOv8-Pose + monocular depth for visual hazard prediction.

## 7.3 Risk Model

A simple prototype can calculate:

```text
Risk = Distance × Direction × ObjectType × Movement
```

Example:

```text
Distance: 2.0 m
Object: Low branch
Direction: Center
Movement: User moving toward object

Risk = HIGH
```

## 7.4 Alert Levels

```text
LOW
→ Optional haptic

MEDIUM
→ Haptic + audio

HIGH
→ Immediate haptic + audio
```

Example output:

```text
"ระวัง สิ่งกีดขวางด้านหน้า 2 เมตร"
```

---

# 8. Accessible Navigation System

## 8.1 Navigation Input

User enters:

```text
Current location
+
Destination
+
Accessibility mode
```

The system then evaluates route constraints.

## 8.2 Accessibility Constraints

For wheelchair mode:

```text
Avoid:
- Stairs
- Inaccessible sidewalks
- Broken paths
- Closed elevators

Prefer:
- Ramps
- Accessible entrances
- Working elevators
- Accessible crossings
```

## 8.3 Route Engine

```text
User
 ↓
Destination
 ↓
Routing API
 ↓
Accessibility Filter
 ↓
Route Scoring
 ↓
Best Accessible Route
 ↓
Navigation
```

## 8.4 Route Score

Prototype scoring:

```text
Route Score =
Travel Time
+ Accessibility Penalty
+ Barrier Penalty
+ Risk Penalty
```

Lower score = better route.

---

# 9. Dynamic Rerouting

The application should monitor route conditions while navigation is active.

```text
Navigation Active
       ↓
Monitor Accessibility Data
       ↓
Barrier Found?
   ↙          ↘
 NO           YES
 ↓             ↓
Continue     Recalculate
              ↓
          Accessible Route
              ↓
          Notify User
```

Example:

```text
⚠️ Route Update

The elevator at Entrance A
is unavailable.

A new accessible route
has been calculated.

[ Continue ]
```

The source brief specifically gives an example in which the system detects a broken BTS elevator and automatically reroutes the wheelchair user.

---

# 10. SOS System

SOS is a core feature available to every user mode.

## 10.1 Manual SOS

```text
SOS Screen

       🆘

   EMERGENCY

Press and hold for 2 seconds
```

Use press-and-hold rather than a single tap to reduce accidental activation.

## 10.2 Confirmation

```text
Emergency SOS

Are you sure?

3

2

1

[ Cancel ]
```

## 10.3 SOS Data

The emergency event should contain:

```json
{
  "user_id": "USER_ID",
  "event_type": "SOS",
  "timestamp": "ISO_TIMESTAMP",
  "latitude": 0,
  "longitude": 0,
  "accuracy": 0,
  "trigger_method": "manual",
  "device_status": "available"
}
```

Do not store unnecessary camera frames or sensitive data by default.

---

# 11. Gesture SOS

For users who cannot rely on voice communication:

```text
Front Camera
      ↓
Hand Detection
      ↓
Landmark Extraction
      ↓
Gesture Classification
      ↓
Confidence Check
      ↓
3-second Confirmation
      ↓
SOS
```

Prototype technology:

- MediaPipe Hands
- Gesture classification model

The source brief proposes MediaPipe + spatial-temporal gesture recognition for emergency gesture detection.

Important prototype rule:

> Never activate SOS from a single low-confidence gesture detection.

Use:

```text
Gesture confidence
+
Temporal consistency
+
3-second confirmation
```

---

# 12. Backend Architecture

The mobile app should not send all AI processing to the backend.

Recommended architecture:

```text
                 MOBILE APP
                     │
       ┌─────────────┼─────────────┐
       │             │             │
       ↓             ↓             ↓
    Camera          GPS         User Input
       │             │             │
       ↓             │             ↓
  ON-DEVICE AI      │       Application Logic
       │             │             │
       └─────────────┼─────────────┘
                     ↓
                API Gateway
                     │
                 FastAPI
                     │
       ┌─────────────┼─────────────┐
       ↓             ↓             ↓
   PostgreSQL    Routing API   Accessibility
   + PostGIS                     Data
       │
       ↓
 Emergency Service
```

The source brief proposes FastAPI, PostgreSQL/PostGIS, Mapbox/routing services, WebSockets/MQTT, and mobile edge AI.

---

# 13. Backend Services

## 13.1 Authentication Service

Responsibilities:

- Register
- Login
- Token refresh
- User session

Suggested:

```text
JWT Access Token
+
Refresh Token
```

## 13.2 User Service

Stores:

```text
User
Accessibility mode
Preferences
Emergency contacts
```

## 13.3 Navigation Service

Responsibilities:

- Route request
- Accessibility filtering
- Barrier checking
- Rerouting

## 13.4 Emergency Service

Responsibilities:

- Receive SOS
- Create emergency event
- Store location
- Notify emergency contacts
- Track emergency status

## 13.5 Accessibility Data Service

Responsibilities:

- Elevator status
- Accessible entrances
- Barriers
- Road/sidewalk conditions

---

# 14. Database Design

Recommended PostgreSQL + PostGIS.

## users

```text
id
name
email
password_hash
accessibility_mode
created_at
updated_at
```

## user_preferences

```text
id
user_id
voice_enabled
haptic_enabled
high_contrast
font_scale
language
created_at
updated_at
```

## emergency_contacts

```text
id
user_id
name
phone
relationship
created_at
```

## accessibility_points

```text
id
type
name
latitude
longitude
status
accessibility_level
updated_at
```

## barriers

```text
id
type
latitude
longitude
severity
status
reported_at
expires_at
```

## navigation_sessions

```text
id
user_id
origin
destination
route
started_at
ended_at
status
```

## emergency_events

```text
id
user_id
event_type
trigger_method
latitude
longitude
accuracy
status
created_at
resolved_at
```

---

# 15. API Design

Base URL:

```text
/api/v1
```

## Authentication

```http
POST /auth/register
POST /auth/login
POST /auth/refresh
```

## User

```http
GET /users/me
PATCH /users/me
GET /users/me/preferences
PATCH /users/me/preferences
```

## Emergency

```http
POST /emergency/events
GET /emergency/events/{id}
POST /emergency/events/{id}/cancel
```

## Navigation

```http
POST /navigation/routes
POST /navigation/reroute
GET /navigation/accessibility
```

## Accessibility

```http
GET /accessibility/points
GET /accessibility/barriers
GET /accessibility/status
```

---

# 16. API Example — Navigation

Request:

```json
{
  "origin": {
    "latitude": 14.88,
    "longitude": 102.01
  },
  "destination": {
    "latitude": 13.74,
    "longitude": 100.52
  },
  "mode": "wheelchair"
}
```

Response:

```json
{
  "route_id": "route_001",
  "distance_m": 1200,
  "duration_sec": 1080,
  "accessibility_score": 0.94,
  "warnings": [
    "elevator_available"
  ],
  "geometry": []
}
```

---

# 17. API Example — SOS

Request:

```json
{
  "event_type": "SOS",
  "trigger_method": "gesture",
  "location": {
    "latitude": 14.88,
    "longitude": 102.01,
    "accuracy": 8.2
  }
}
```

Response:

```json
{
  "event_id": "SOS-2026-001",
  "status": "ACTIVE",
  "created_at": "2026-08-17T14:00:00+07:00"
}
```

---

# 18. Mobile State Management

Recommended states:

```text
INITIALIZING
    ↓
READY
    ↓
ASSISTANCE_ACTIVE
    ↓
ALERT
    ↓
NAVIGATING
    ↓
SOS_ACTIVE
```

Example:

```text
READY
 ↓
User starts Vision Assist
 ↓
ASSISTANCE_ACTIVE
 ↓
Obstacle detected
 ↓
ALERT
 ↓
Obstacle cleared
 ↓
ASSISTANCE_ACTIVE
```

---

# 19. Offline / Poor Network Strategy

The app should degrade gracefully.

## Online

```text
AI
+
GPS
+
Maps
+
Accessibility API
+
Backend
```

## Poor Network

```text
On-device AI
+
GPS
+
Cached maps
+
Cached accessibility data
+
Local SOS preparation
```

## Offline

At minimum:

```text
On-device hazard detection
+
GPS
+
Haptic/audio alert
+
Manual SOS preparation
```

The source brief explicitly identifies on-device processing as a way to maintain low latency and continue functioning when internet connectivity is poor.

---

# 20. Privacy & Security

## Privacy Principles

1. Process camera frames on-device whenever possible.
2. Do not upload continuous camera streams by default.
3. Store only necessary user information.
4. Encrypt communication using HTTPS.
5. Protect authentication tokens.
6. Request permissions only when needed.
7. Allow users to control accessibility and notification settings.
8. Provide clear data deletion options.

## Camera Processing

Preferred:

```text
Camera
 ↓
On-device AI
 ↓
Detection result
 ↓
Discard frame
```

Avoid:

```text
Camera
 ↓
Upload every frame
 ↓
Cloud AI
```

The source brief explicitly emphasizes Privacy-First and PDPA compliance through on-device video processing.

---

# 21. Accessibility UI Requirements

The UI should follow the source brief's WCAG 2.1 Level AA direction.

Important principles:

### Visual

- Large touch targets
- High contrast
- Scalable text
- Avoid color-only information

### Hearing

- Do not rely only on audio
- Visual alerts
- Haptic feedback

### Speech

- Do not require voice communication for emergency
- Manual SOS
- Gesture SOS

### Motor

- Large controls
- Simple gestures
- Avoid precise small buttons

### Vision

- Screen reader support
- Voice feedback
- Haptic feedback
- Logical focus order

---

# 22. Recommended Mobile Screen List

The prototype should contain approximately these screens:

```text
01 Splash
02 Welcome
03 Select Accessibility Mode
04 Permission Setup
05 Emergency Contact Setup

06 Home — Vision Mode
07 Vision Assist
08 Hazard Alert

09 Home — Wheelchair Mode
10 Destination Search
11 Accessible Route Selection
12 Navigation
13 Rerouting Alert

14 Home — Speech/Hearing Mode
15 Gesture SOS
16 SOS Confirmation
17 SOS Active
18 Emergency Status

19 Profile
20 Accessibility Settings
21 Emergency Contacts
22 Privacy Settings
```

For a competition prototype, not every screen needs a fully working backend. The important flows should be demonstrable.

---

# 23. Prototype Priority

## P0 — Must Work

```text
User onboarding
        ↓
Select user mode
        ↓
Home
        ↓
Core assistance
        ↓
SOS
```

## P1 — Important

```text
Navigation
Accessibility route
Rerouting
Emergency contacts
```

## P2 — AI Enhancement

```text
Real-time object detection
Depth estimation
Gesture recognition
```

## P3 — Future

```text
Advanced prediction
More accessibility datasets
Additional transportation integrations
Advanced personalization
```

---

# 24. Recommended MVP

For a student-year-3 prototype, the strongest MVP is:

### Feature 1 — Accessible Navigation

```text
Search destination
→ Accessible route
→ Start navigation
→ Barrier detected
→ Reroute
```

### Feature 2 — Vision Hazard Detection

```text
Camera
→ Detect obstacle
→ Estimate distance
→ Audio/Haptic warning
```

### Feature 3 — Universal SOS

```text
Manual SOS
+
Gesture SOS
→ Confirmation
→ GPS
→ Emergency Contact
```

This provides a coherent story rather than three unrelated AI demos.

---

# 25. Suggested Project Structure

```text
accessible-ai-app/
│
├── mobile/
│   ├── lib/
│   │   ├── core/
│   │   ├── features/
│   │   │   ├── auth/
│   │   │   ├── home/
│   │   │   ├── navigation/
│   │   │   ├── vision_assist/
│   │   │   ├── gesture_sos/
│   │   │   ├── emergency/
│   │   │   └── profile/
│   │   ├── services/
│   │   ├── models/
│   │   └── widgets/
│   └── test/
│
├── backend/
│   ├── app/
│   │   ├── api/
│   │   ├── core/
│   │   ├── models/
│   │   ├── schemas/
│   │   ├── services/
│   │   └── repositories/
│   ├── migrations/
│   └── tests/
│
├── ai/
│   ├── vision/
│   ├── depth/
│   └── gesture/
│
├── database/
│   └── migrations/
│
├── docs/
│   ├── architecture/
│   ├── api/
│   └── prototype/
│
└── README.md
```

---

# 26. System Development Phases

## Phase 1 — UX Prototype

Build:

- Onboarding
- User mode selection
- Home
- Navigation
- SOS
- Profile

## Phase 2 — Backend

Build:

- Authentication
- User profile
- Emergency contacts
- SOS API
- Navigation API

## Phase 3 — Maps

Build:

- GPS
- Destination search
- Route display
- Accessibility filtering
- Rerouting

## Phase 4 — AI

Build:

- Object detection
- Distance estimation
- Gesture detection

## Phase 5 — Integration

Connect:

```text
Mobile
 ↕
FastAPI
 ↕
PostgreSQL/PostGIS
 ↕
Routing / Accessibility Data
```

## Phase 6 — Testing

Test:

- Accessibility
- False SOS
- GPS accuracy
- Network failure
- AI latency
- Navigation failure
- Permission denial

---

# 27. Success Criteria for Prototype

The prototype is considered successful when a user can demonstrate:

### Scenario A

```text
Visual user
→ Start Vision Assist
→ Obstacle appears
→ App detects it
→ User receives warning
```

### Scenario B

```text
Wheelchair user
→ Select destination
→ App selects accessible route
→ Barrier appears
→ App reroutes
```

### Scenario C

```text
Speech/hearing user
→ Performs SOS gesture
→ App detects gesture
→ Countdown
→ GPS captured
→ Emergency event created
```

---

# 28. Important Scope Decision

The current version intentionally excludes:

```text
❌ Government dashboard
❌ City command center
❌ Government employee interface
❌ Government analytics
❌ Public administration workflow
```

These can be added later as a separate system.

Current architecture is therefore:

```text
                 USER
                  │
                  ↓
          ┌───────────────┐
          │ Mobile App    │
          ├───────────────┤
          │ Navigation    │
          │ Vision AI     │
          │ Gesture SOS   │
          │ Emergency     │
          │ Profile       │
          └───────┬───────┘
                  │
                  ↓
          ┌───────────────┐
          │ Backend API   │
          └───────┬───────┘
                  │
        ┌─────────┼─────────┐
        ↓         ↓         ↓
    Database   Routing   Emergency
    PostGIS      API       Service
```

This is the recommended **User-side Mobile System Architecture** for the current prototype scope.
