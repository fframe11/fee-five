import os
import sys
import cv2
import numpy as np
from ultralytics import YOLOWorld

try:
    sys.stdout.reconfigure(line_buffering=True, encoding='utf-8')
except Exception:
    pass

model = YOLOWorld("yolov8s-world.pt")

# ทดสอบกลุ่มคำเดี่ยว (Single-word classes) ที่ CLIP เข้าใจง่ายกว่า
vocab_tests = [
    "pole", "pillar", "column", "fan", "wall", "building",
    "floor", "ground", "tiles", "curb", "step", "sidewalk",
    "tree", "plant", "bush", "grass"
]

model.set_classes(vocab_tests)

test_files = [
    ("เสา.jpg", "c:\\feefive\\เสา.jpg"),
    ("พื้นต่างระดับ.jpg", "c:\\feefive\\พื้นต่างระดับ.jpg")
]

for filename, filepath in test_files:
    print(f"\n=======================================================")
    print(f" 🔍 วิเคราะห์คำศัพท์ที่โมเดลตรวจพบบนภาพ: {filename}")
    print(f"=======================================================")
    
    img_data = np.fromfile(filepath, dtype=np.uint8)
    frame = cv2.imdecode(img_data, cv2.IMREAD_COLOR)
    frame_h, frame_w = frame.shape[:2]
    
    # Predict with conf=0.10
    results = model.predict(frame, conf=0.10, verbose=False)
    boxes = results[0].boxes
    
    if len(boxes) == 0:
        print("   ❌ ไม่พบวัตถุใดๆ แม้ใช้คำศัพท์เดี่ยวที่ conf >= 0.10")
    else:
        for idx, b in enumerate(boxes):
            cid = int(b.cls[0])
            cname = vocab_tests[cid]
            conf = float(b.conf[0])
            x1, y1, x2, y2 = map(int, b.xyxy[0])
            cx = (x1 + x2) / 2
            dir_str = "ด้านซ้าย" if cx < frame_w * 0.35 else ("ด้านขวา" if cx > frame_w * 0.65 else "ตรงหน้า")
            area = ((x2 - x1) * (y2 - y1)) / (frame_w * frame_h) * 100
            print(f"   [{idx+1}] ตรวจพบ: '{cname}' | ความมั่นใจ: {conf:.1%} | ตำแหน่ง: {dir_str} | ขนาด: {area:.1f}% ของจอ")
