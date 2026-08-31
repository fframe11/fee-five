import os
import sys
import cv2
import numpy as np
from ultralytics import YOLOWorld

try:
    sys.stdout.reconfigure(line_buffering=True, encoding='utf-8')
except Exception:
    pass

print("=================================================================")
print("  🚀 กำลังรันโมเดล YOLO-World (yolov8s-world.pt) ทดสอบภาพทั้ง 2 ภาพ")
print("=================================================================")

# 1. โหลดโมเดล
model = YOLOWorld("yolov8s-world.pt")

# 2. คลาสตามที่ระบุในโค้ดของคุณเป๊ะๆ 100%
custom_classes = [
    "concrete utility pole",     # เสาไฟฟ้าคอนกรีต
    "stairs",                    # บันได
    "wheelchair ramp",           # ทางลาด
    "curb",                      # ทางต่างระดับ/ขอบฟุตบาท
    "elevator door",             # ประตูลิฟต์
    "door"                       # ประตูทั่วไป
]

thai_labels = {
    "concrete utility pole": "เสาไฟฟ้าคอนกรีต",
    "stairs": "บันได",
    "wheelchair ramp": "ทางลาด",
    "curb": "ทางต่างระดับ/ขอบฟุตบาท",
    "elevator door": "ประตูลิฟต์",
    "door": "ประตู"
}

model.set_classes(custom_classes)

test_files = [
    ("เสา.jpg", "c:\\feefive\\เสา.jpg"),
    ("พื้นต่างระดับ.jpg", "c:\\feefive\\พื้นต่างระดับ.jpg")
]

for filename, filepath in test_files:
    print(f"\n" + "="*65)
    print(f" 📸 [ทดสอบภาพที่ 1]: {filename}")
    print("="*65)

    if not os.path.exists(filepath):
        print(f"❌ ไม่พบไฟล์: {filepath}")
        continue

    # โหลดภาพ UTF-8 safe
    img_data = np.fromfile(filepath, dtype=np.uint8)
    frame = cv2.imdecode(img_data, cv2.IMREAD_COLOR)
    frame_h, frame_w = frame.shape[:2]
    print(f"ขนาดภาพ: กว้าง {frame_w} x สูง {frame_h} พิกเซล")

    # ทดสอบที่ค่า Confidence ตามโค้ด (conf=0.25)
    print(f"\n--- [1] รันด้วยค่าความมั่นใจ conf=0.25 (ตามโค้ดต้นฉบับ) ---")
    results = model.predict(frame, conf=0.25, verbose=False)
    boxes = results[0].boxes

    if len(boxes) == 0:
        print(f"❌ ผลลัพธ์: ตรวจไม่พบวัตถุใดๆ ใน 6 คลาสข้างต้นที่ conf >= 0.25 (25%)")
    else:
        print(f"✅ ตรวจพบ {len(boxes)} วัตถุ:")
        for idx, b in enumerate(boxes):
            cid = int(b.cls[0])
            cname = custom_classes[cid]
            tname = thai_labels[cname]
            conf = float(b.conf[0])
            x1, y1, x2, y2 = map(int, b.xyxy[0])
            cx = (x1 + x2) / 2
            dir_str = "ด้านซ้าย" if cx < frame_w * 0.35 else ("ด้านขวา" if cx > frame_w * 0.65 else "ตรงหน้า")
            area_pct = ((x2 - x1) * (y2 - y1)) / (frame_w * frame_h) * 100
            print(f"   [{idx+1}] {tname} ({cname}) | ความมั่นใจ: {conf:.1%} | พิกัด: [{x1}, {y1}, {x2}, {y2}] | ทิศทาง: {dir_str} | ขนาด: {area_pct:.1f}% ของจอ")

    # ทดสอบเชิงลึกที่ conf=0.05 เพื่อดูว่าโมเดลมองเห็นอะไรบ้างที่ความมั่นใจต่ำลง
    print(f"\n--- [2] ตรวจสอบคะแนนความเป็นไปได้ของทุกคลาส (Low threshold conf=0.05) ---")
    res_low = model.predict(frame, conf=0.05, verbose=False)
    boxes_low = res_low[0].boxes
    if len(boxes_low) == 0:
        print(f"   (ไม่มีวัตถุใดใน 6 คลาสนี้ที่มีค่าคะแนนเกิน 5%)")
    else:
        for idx, b in enumerate(boxes_low):
            cid = int(b.cls[0])
            cname = custom_classes[cid]
            tname = thai_labels[cname]
            conf = float(b.conf[0])
            x1, y1, x2, y2 = map(int, b.xyxy[0])
            cx = (x1 + x2) / 2
            dir_str = "ด้านซ้าย" if cx < frame_w * 0.35 else ("ด้านขวา" if cx > frame_w * 0.65 else "ตรงหน้า")
            print(f"   • พบสัญญาณ: {tname} ({cname}) ที่ความมั่นใจ {conf:.1%} (ตำแหน่ง: {dir_str})")

    # วาดและเซฟรูปผลลัพธ์
    annotated = results[0].plot()
    out_name = f"c:\\feefive\\test_result_{filename}"
    _, enc = cv2.imencode('.jpg', annotated)
    enc.tofile(out_name)
    print(f"💾 บันทึกรูปภาพผลลัพธ์พร้อมกรอบที่: {out_name}")

print("\n" + "="*65)
print("  สรุปผลการรันเรียบร้อย")
print("="*65)
