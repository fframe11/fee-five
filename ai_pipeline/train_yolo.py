import os
import argparse
import torch
from ultralytics import YOLO

# Allow MLFlow to use the filesystem backend without throwing exception
os.environ["MLFLOW_ALLOW_FILE_STORE"] = "true"

def train_and_export():
    # Parse command line arguments
    parser = argparse.ArgumentParser(description="Train YOLO11n on merged accessibility datasets.")
    parser.add_argument("--epochs", type=int, default=50, help="Number of training epochs")
    args = parser.parse_args()

    # 1. Resolve project root paths
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.abspath(os.path.join(script_dir, ".."))
    dataset_yaml = os.path.join(project_root, "datasets", "merged", "data.yaml")
    if not os.path.exists(dataset_yaml):
        print(f"Error: Merged dataset config not found at {dataset_yaml}. Run merge_labels.py first.")
        return

    # 2. Load a pretrained lightweight YOLO11n model
    model_weight = os.path.join(project_root, "yolo11n.pt")
    model = YOLO(model_weight if os.path.exists(model_weight) else "yolo11n.pt")

    # Check device availability
    device = 0 if torch.cuda.is_available() else "cpu"
    workers = 8 if device == 0 else 0
    print(f"Using device: {device} (workers: {workers})")

    print(f"Starting YOLO11n fine-tuning for {args.epochs} epochs...")
    model.train(
        data=dataset_yaml,
        epochs=args.epochs,
        imgsz=640,
        batch=16,
        device=device,
        workers=workers
    )

    # 3. Validate performance
    print("Validating model performance...")
    metrics = model.val()
    print(f"Validation mAP50-95: {metrics.box.map}")

    # 4. Export the fine-tuned model to ONNX format for Mobile/Edge Inference
    print("Exporting model to ONNX format...")
    try:
        onnx_path = model.export(format="onnx", data=dataset_yaml)
        print(f"Model successfully exported to ONNX: {onnx_path}")
    except Exception as e:
        print(f"Warning: ONNX export failed: {e}")

    # 5. Attempt to export to TFLite format
    print("Attempting to export model to INT8 Quantized TFLite format...")
    try:
        tflite_path = model.export(format="tflite", int8=True, data=dataset_yaml)
        print(f"Model successfully exported to TFLite: {tflite_path}")
    except Exception as e:
        print("\n" + "="*50)
        print("Note: TFLite export requires TensorFlow, which is currently not supported on Python 3.13 on Windows.")
        print(f"Error details: {e}")
        print("We will use the ONNX model instead for on-device inference.")
        print("="*50 + "\n")

if __name__ == "__main__":
    train_and_export()
