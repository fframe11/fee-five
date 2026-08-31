import os
import dotenv
from roboflow import Roboflow

# Load .env
dotenv.load_dotenv(os.path.abspath(".env"))
api_key = os.environ.get("Roboflow_api")

rf = Roboflow(api_key=api_key)

projects = [
    ("vision-assistant-fvhqw", "accessibility-object-detection-lrrth-aoakw"),
    ("clc-u0mtm", "ds-pgsa"),
    ("drone-accessibility-mapping", "allenatrium")
]

for ws, proj in projects:
    print(f"\nChecking {ws}/{proj}...")
    try:
        project_obj = rf.workspace(ws).project(proj)
        versions = project_obj.versions()
        for v in versions:
            # print version number and format representation
            print(f"  - Version: {getattr(v, 'version', None)} | ID: {v.id} | model_format: {v.model_format}")
    except Exception as e:
        print(f"Error checking project: {e}")
