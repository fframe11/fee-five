import sys
import os
from ultralytics import YOLO

def test_inference(image_path):
    # Use best.pt if it exists, otherwise best.onnx
    model_path = "runs/detect/train4/weights/best.pt"
    if not os.path.exists(model_path):
        model_path = "runs/detect/train4/weights/best.onnx"
        
    if not os.path.exists(model_path):
        print("Error: Trained model weights not found. Please train the model first.")
        return

    print(f"Loading model: {model_path}...")
    model = YOLO(model_path)

    print(f"Running inference on image: {image_path}...")
    results = model(image_path)

    # Show results
    for result in results:
        boxes = result.boxes
        print(f"\nDetections found: {len(boxes)}")
        for box in boxes:
            class_id = int(box.cls[0])
            label = model.names[class_id]
            conf = float(box.conf[0])
            coords = [round(float(c), 2) for c in box.xyxy[0]]
            print(f"  - Class: {label} (ID: {class_id}) | Confidence: {conf:.2f} | Bounding Box: {coords}")

        # Save annotated image
        output_img = "detection_result_" + os.path.basename(image_path)
        result.save(filename=output_img)
        print(f"\nSaved annotated image to: {os.path.abspath(output_img)}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python ai_pipeline/test_inference.py <path_to_image>")
        sys.exit(1)
    test_inference(sys.argv[1])
