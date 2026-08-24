# AI for a Better Society — Mobile System Design Backend

This is the FastAPI backend skeleton for the accessible mobile application prototype. It includes SQL schemas mapping to the requirements for visually, mobility, and speech/hearing impaired users, integrated with PostGIS geometry fields via GeoAlchemy2.

## Features Included

1. **Authentication Service**: Token generation and refresh endpoints with registration validations.
2. **User Profiles & Preferences**: Large controls, voice guidance toggles, and high contrast settings storage.
3. **Emergency SOS System**: Trigger mechanisms accepting coordinates for geolocation reporting. Supports manual and front-camera gesture alerts.
4. **Accessible Navigation & Proximity Analysis**: Geolocation proximity calculation on active barriers near routing paths using PostGIS spatial functions (`ST_DWithin`).
5. **Accessibility points & barrier tracking**: Reports broken elevators, damaged sidewalks, and updates map layouts.

## Technical Architecture

- **Web framework**: FastAPI
- **ORM / Database Engine**: SQLAlchemy & GeoAlchemy2 mapping to PostgreSQL with the PostGIS extension.
- **WGS 84 (GPS)** spatial reference coordinate standard is mapped with **SRID 4326**.

## Getting Started

### Prerequisites
- Python 3.10+
- PostgreSQL database instance with the PostGIS extension installed.

### Setup and Running

1. **Install requirements**:
   ```bash
   pip install -r requirements.txt
   ```

2. **Configure Database connection**:
   Set the `DATABASE_URL` environment variable:
   ```bash
   # Windows PowerShell
   $env:DATABASE_URL="postgresql://username:password@localhost:5432/accessibility_db"
   
   # Linux/macOS
   export DATABASE_URL="postgresql://username:password@localhost:5432/accessibility_db"
   ```

3. **Start backend development server**:
   ```bash
   uvicorn app.main:app --reload
   ```

4. **Verify Endpoint API**:
   Open browser at `http://localhost:8000/docs` to access Swagger interactive OpenAPI specs.
