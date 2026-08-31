import os
import argparse
from roboflow import Roboflow
import dotenv

def setup_roboflow(api_key):
    rf = Roboflow(api_key=api_key)
    return rf

def download_dataset(rf, workspace, project, version, output_dir):
    print(f"Downloading {workspace}/{project} version {version}...")
    project_obj = rf.workspace(workspace).project(project)
    dataset = project_obj.version(version).download("yolov8", location=output_dir)
    print(f"Dataset downloaded successfully to {dataset.location}")

if __name__ == "__main__":
    # Load .env file from the current or parent directory
    current_dir = os.path.dirname(os.path.abspath(__file__))
    parent_dir = os.path.dirname(current_dir)
    for env_path in [os.path.join(current_dir, ".env"), os.path.join(parent_dir, ".env")]:
        if os.path.exists(env_path):
            dotenv.load_dotenv(env_path)

    parser = argparse.ArgumentParser(description="Download Roboflow accessibility datasets.")
    parser.add_argument("--api-key", required=False, help="Roboflow API Key")
    args = parser.parse_args()

    api_key = args.api_key or os.environ.get("Roboflow_api") or os.environ.get("ROBOFLOW_API")
    if not api_key:
        print("Error: Roboflow API key not found. Please provide --api-key or define Roboflow_api in .env file.")
        exit(1)

    rf = setup_roboflow(api_key)
    
    # 1. Accessibility Object Detection Dataset (CC BY 4.0)
    # https://universe.roboflow.com/vision-assistant-fvhqw/accessibility-object-detection-lrrth-aoakw
    download_dataset(rf, "vision-assistant-fvhqw", "accessibility-object-detection-lrrth-aoakw", 2, "datasets/accessibility_obj")
    
    # 2. DS-PGSA Object Detection Dataset
    # https://universe.roboflow.com/clc-u0mtm/ds-pgsa
    download_dataset(rf, "clc-u0mtm", "ds-pgsa", 1, "datasets/ds_pgsa")
    
    # 3. AllenAtrium Dataset (CC BY 4.0)
    # https://universe.roboflow.com/drone-accessibility-mapping/allenatrium
    download_dataset(rf, "drone-accessibility-mapping", "allenatrium", 1, "datasets/allen_atrium")

    print("\nAll datasets downloaded successfully! Proceed to merge_labels.py.")
