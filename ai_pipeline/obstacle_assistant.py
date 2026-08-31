"""
AI for Better Society - Zero-Shot Obstacle Detection & Scene Analysis Pipeline
Supports:
1. YOLO-World (Zero-Shot Obstacle Detection: Concrete utility pole, Stairs, Wheelchair ramp, Curb, Elevator, Door)
2. Direction & Distance Calculation (Left / Center / Right, Box Area close/far threshold)
3. Thai Voice Alert (gTTS + Pygame audio engine)
4. Vision AI Deep Scene Analysis (Groq Qwen 3.6 Vision / Gemini API)
5. Test mode on static images (e.g. พื้นต่างระดับ.jpg, เสา.jpg) and live camera mode.
"""

import os
import sys
import time
import json
import urllib.request
import urllib.error

# Ensure UTF-8 and unbuffered output on Windows
try:
    sys.stdout.reconfigure(line_buffering=True, encoding='utf-8')
    sys.stderr.reconfigure(line_buffering=True, encoding='utf-8')
except Exception:
    pass

import cv2
from PIL import Image
import torch

try:
    from ultralytics import YOLOWorld
except ImportError:
    print("[ERROR] ultralytics not installed. Run: pip install ultralytics")
    sys.exit(1)

try:
    from gtts import gTTS
    import pygame
    PYGAME_AUDIO = True
    pygame.mixer.init()
except Exception as e:
    print(f"[NOTE] Audio initialization notice: {e}")
    PYGAME_AUDIO = False

# 1. Custom Obstacle Classes & Thai Translations (Optimized for CLIP Text Embeddings)
CUSTOM_CLASSES = [
    "concrete utility pole",
    "pole",
    "pillar",
    "column",
    "stairs",
    "step",
    "wheelchair ramp",
    "ramp",
    "curb",
    "uneven ground",
    "pothole",
    "barrier",
    "elevator door",
    "door",
    "bush",
    "plant"
]

THAI_LABELS = {
    "concrete utility pole": "เสาไฟฟ้า",
    "pole": "เสา",
    "pillar": "เสา",
    "column": "เสา",
    "stairs": "บันได",
    "step": "ทางต่างระดับ",
    "wheelchair ramp": "ทางลาด",
    "ramp": "ทางลาด",
    "curb": "ทางต่างระดับ",
    "uneven ground": "พื้นต่างระดับ",
    "pothole": "หลุมบนทางเดิน",
    "barrier": "สิ่งกีดขวาง",
    "elevator door": "ประตูลิฟต์",
    "door": "ประตู",
    "bush": "พุ่มไม้",
    "plant": "พุ่มไม้"
}

def load_env():
    """Load API keys from .env file in parent directories."""
    for env_path in ['.env', '../.env', '../../.env', os.path.join(os.path.dirname(__file__), '..', '.env')]:
        if os.path.exists(env_path):
            try:
                with open(env_path, 'r', encoding='utf-8') as f:
                    for line in f:
                        if '=' in line and not line.strip().startswith('#'):
                            k, v = line.strip().split('=', 1)
                            os.environ[k.strip()] = v.strip()
            except Exception as e:
                print(f"Error loading {env_path}: {e}")

def play_sound(text: str, output_file: str = "voice_alert.mp3", play_audio: bool = True):
    """Generate and play Thai voice alert using gTTS and pygame."""
    try:
        tts = gTTS(text=text, lang='th')
        tts.save(output_file)
        if play_audio and PYGAME_AUDIO:
            try:
                pygame.mixer.music.load(output_file)
                pygame.mixer.music.play()
            except Exception as pe:
                print(f"[Audio Playback] {pe}")
        return output_file
    except Exception as e:
        print(f"[gTTS Warning] {e}")
        return None

def analyze_scene_with_vision_ai(image_path: str, prompt: str = None) -> str:
    """Analyze image using Vision AI (Groq Qwen 3.6 / Gemini) for deep scene understanding."""
    load_env()
    api_key = os.environ.get("Groq_api") or os.environ.get("GROQ_API_KEY") or os.environ.get("GEMINI_API_KEY")
    if not api_key:
        return "ไม่มี API Key สำหรับการวิเคราะห์ภาพเชิงลึก (Groq_api / GEMINI_API_KEY)"

    if prompt is None:
        prompt = (
            "คุณคือ AI ผู้ช่วยนำทางคนตาบอดในประเทศไทย จงวิเคราะห์ภาพถ่ายทางนี้ "
            "บอกสิ่งกีดขวางที่เป็นอันตรายที่อยู่ข้างหน้าอย่างกระชับ เช่น เสาไฟฟ้า หลุม บันได หรือทางต่างระดับ "
            "ระบุตำแหน่ง ซ้าย-กลาง-ขวา และแนะนำสั้นๆ ว่าควรเดินหลบไปทางไหน "
            "ข้อกำหนด: ตอบเป็นภาษาไทยสั้นๆ ไม่เกิน 2 ประโยค เพื่อความปลอดภัยในการเดิน"
        )

    # Read and encode image as base64 data url
    try:
        import base64
        with open(image_path, "rb") as img_file:
            b64_str = base64.b64encode(img_file.read()).decode('utf-8')
        img_data_url = f"data:image/jpeg;base64,{b64_str}"
    except Exception as e:
        return f"เกิดข้อผิดพลาดในการโหลดรูปภาพ: {e}"

    url = "https://api.groq.com/openai/v1/chat/completions"
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "User-Agent": "FeeFive-AI-Obstacle-Detector/1.0"
    }
    payload = {
        "model": "qwen/qwen3.6-27b",
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": prompt},
                    {"type": "image_url", "image_url": {"url": img_data_url}}
                ]
            }
        ],
        "temperature": 0.2
    }

    try:
        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode('utf-8'),
            headers=headers,
            method='POST'
        )
        with urllib.request.urlopen(req, timeout=25) as response:
            res_json = json.loads(response.read().decode('utf-8'))
            raw_text = res_json["choices"][0]["message"]["content"]
            import re
            clean_text = re.sub(r'<think>.*?</think>', '', raw_text, flags=re.DOTALL).strip()
            return clean_text if clean_text else raw_text.strip()
    except urllib.error.HTTPError as e:
        err_msg = e.read().decode('utf-8')
        return f"Vision API HTTP Error ({e.code}): {err_msg}"
    except Exception as e:
        return f"Vision API Error: {str(e)}"

def process_image_obstacles(
    image_path: str,
    model: YOLOWorld,
    output_path: str = None,
    conf_threshold: float = 0.20,
    area_close_threshold: float = 0.12,
    run_vision_ai: bool = True
):
    """
    Run YOLO-World zero-shot detection, direction & distance scoring on a static image.
    """
    if not os.path.exists(image_path):
        print(f"[ERROR] Image not found: {image_path}")
        return None

    # Load image with OpenCV (handles UTF-8 paths on Windows cleanly)
    import numpy as np
    img_data = np.fromfile(image_path, dtype=np.uint8)
    frame = cv2.imdecode(img_data, cv2.IMREAD_COLOR)
    if frame is None:
        frame = cv2.imread(image_path)
    if frame is None:
        print(f"[ERROR] Unable to decode image: {image_path}")
        return None

    frame_height, frame_width = frame.shape[:2]

    # Predict using YOLO-World
    results = model.predict(frame, conf=conf_threshold, verbose=False)
    boxes = results[0].boxes

    detected_items = []
    top_alert_text = None

    print(f"\n=======================================================")
    print(f" 🔍 วิเคราะห์ภาพ: {os.path.basename(image_path)} ({frame_width}x{frame_height} px)")
    print(f"=======================================================")

    for box in boxes:
        class_id = int(box.cls[0])
        conf = float(box.conf[0])
        english_name = CUSTOM_CLASSES[class_id] if class_id < len(CUSTOM_CLASSES) else "obstacle"
        thai_name = THAI_LABELS.get(english_name, english_name)

        # Bounding box coordinates [x1, y1, x2, y2]
        x1, y1, x2, y2 = map(int, box.xyxy[0])

        # 1. Direction Calculation (Left 35%, Center 30%, Right 35%)
        obj_center_x = (x1 + x2) / 2
        if obj_center_x < (frame_width * 0.35):
            direction = "ด้านซ้าย"
        elif obj_center_x > (frame_width * 0.65):
            direction = "ด้านขวา"
        else:
            direction = "ตรงหน้า"

        # 2. Metric Depth & Distance Estimation (Centimeters & Meters)
        # Using optical geometry: D = (focal_length * real_height) / bbox_height
        REAL_HEIGHTS = {
            "concrete utility pole": 3.0,
            "pole": 2.8,
            "pillar": 2.8,
            "column": 2.8,
            "stairs": 0.35,
            "step": 0.20,
            "wheelchair ramp": 0.40,
            "curb": 0.18,
            "uneven ground": 0.15,
            "pothole": 0.15,
            "barrier": 1.0,
            "elevator door": 2.1,
            "door": 2.0,
            "bush": 0.8,
            "plant": 0.6
        }
        ref_h = REAL_HEIGHTS.get(english_name, 1.0)
        focal_px = frame_height * 0.9 # Standard mobile focal length estimate
        box_height = y2 - y1
        est_distance_m = max(0.3, min(8.0, (focal_px * ref_h) / max(box_height, 1)))

        if est_distance_m < 1.0:
            dist_str = f"{int(est_distance_m * 100)} เซนติเมตร"
            dist_display = f"{int(est_distance_m * 100)} cm"
        else:
            dist_str = f"{est_distance_m:.1f} เมตร"
            dist_display = f"{est_distance_m:.1f} m"

        box_area_ratio = ( (x2 - x1) * box_height) / (frame_width * frame_height)
        is_close = est_distance_m <= 1.5 or (box_area_ratio > area_close_threshold)
        distance_status = f"ห่าง {dist_str} (อันตราย ⚠️)" if is_close else f"ห่าง {dist_str}"

        # Visual Bounding Box (Red = Close/Danger, Orange = Center, Green = Safe)
        if is_close:
            box_color = (0, 0, 255) # Red (BGR)
            dist_tag = f"DANGER: {dist_display}"
        elif direction == "ตรงหน้า":
            box_color = (0, 165, 255) # Orange (BGR)
            dist_tag = f"CENTER: {dist_display}"
        else:
            box_color = (0, 255, 0) # Green (BGR)
            dist_tag = f"SAFE: {dist_display}"

        cv2.rectangle(frame, (x1, y1), (x2, y2), box_color, 4)

        # English tag for clean font display on image
        dir_tag = "LEFT" if direction == "ด้านซ้าย" else ("RIGHT" if direction == "ด้านขวา" else "CENTER")
        label_top = f"{english_name.upper()} [{dir_tag}]"
        conf_text = f"Conf: {conf:.1%} | Dist: {dist_display} | {dist_tag}"

        # Draw filled background banner
        banner_w = min(frame_width - x1 - 10, max(300, len(conf_text) * 11))
        cv2.rectangle(frame, (x1, max(0, y1 - 44)), (x1 + banner_w, y1), box_color, -1)
        cv2.putText(frame, label_top, (x1 + 8, max(18, y1 - 24)), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (255, 255, 255), 2)
        cv2.putText(frame, conf_text, (x1 + 8, max(36, y1 - 6)), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 255, 255), 1)

        item_info = {
            "english_name": english_name,
            "thai_name": thai_name,
            "confidence": conf,
            "direction": direction,
            "box_area_ratio": box_area_ratio,
            "is_close": is_close,
            "distance_status": distance_status,
            "bbox": [x1, y1, x2, y2]
        }
        detected_items.append(item_info)

        print(f"  • ตรวจพบ: {thai_name} ({english_name}) | ทิศทาง: {direction} | {distance_status} (สัดส่วน {box_area_ratio:.1%}, ความมั่นใจ {conf:.1%})")

    # Generate Top Priority Voice Alert
    if detected_items:
        # Prioritize closest or center obstacle
        sorted_items = sorted(detected_items, key=lambda x: (x['is_close'], x['direction'] == 'ตรงหน้า', x['box_area_ratio']), reverse=True)
        top_item = sorted_items[0]
        top_alert_text = f"ระวัง {top_item['thai_name']} อยู่ {top_item['direction']} {top_item['distance_status']}"
        print(f"\n🔊 [เสียงแจ้งเตือนคนตาบอด]: \"{top_alert_text}\"")
        audio_name = f"voice_alert_{os.path.splitext(os.path.basename(image_path))[0]}.mp3"
        play_sound(top_alert_text, output_file=audio_name, play_audio=False)
    else:
        print("  ℹ️ ไม่พบสิ่งกีดขวางในคลาสที่ระบุ (ตรวจจับเพิ่มเติมด้วย Vision AI)")

    # 3. Deep Scene Analysis with Vision AI (Gemini / Qwen)
    vision_description = None
    if run_vision_ai:
        print(f"\n🧠 [วิเคราะห์ภาพเชิงลึกด้วย Vision AI]:")
        vision_description = analyze_scene_with_vision_ai(image_path)
        print(f"   \"{vision_description}\"")

    # Save Annotated Image
    if output_path is None:
        base, ext = os.path.splitext(image_path)
        output_path = f"detection_result_{os.path.basename(image_path)}"

    # Encode with UTF-8 safe write
    _, enc_img = cv2.imencode('.jpg', frame)
    enc_img.tofile(output_path)
    print(f"\n💾 บันทึกรูปภาพผลลัพธ์ที่: {output_path}")

    return {
        "image": image_path,
        "output_image": output_path,
        "detected_items": detected_items,
        "voice_alert": top_alert_text,
        "vision_ai_summary": vision_description
    }

def main():
    print("========================================================")
    print("  AI for Better Society - Zero-Shot Obstacle Detector")
    print("  Initializing YOLO-World (yolov8s-world.pt)...")
    print("========================================================")

    # 1. Load Model
    model = YOLOWorld("yolov8s-world.pt")
    model.set_classes(CUSTOM_CLASSES)
    print(f"✅ โหลดโมเดล YOLO-World สำเร็จ พร้อมกำหนด {len(CUSTOM_CLASSES)} คลาสสิ่งกีดขวาง:")
    for c in CUSTOM_CLASSES:
        print(f"   - {c} -> {THAI_LABELS.get(c, c)}")

    # 2. Test Targets
    test_images = ["พื้นต่างระดับ.jpg", "เสา.jpg"]

    results_summary = []
    for img_name in test_images:
        img_full_path = os.path.join(os.path.dirname(__file__), "..", img_name)
        if not os.path.exists(img_full_path):
            img_full_path = img_name
        
        res = process_image_obstacles(
            image_path=img_full_path,
            model=model,
            conf_threshold=0.15,
            area_close_threshold=0.10,
            run_vision_ai=True
        )
        if res:
            results_summary.append(res)
        time.sleep(3) # Throttle to prevent Vision API rate limiting

    print("\n========================================================")
    print("  🎉 สรุปผลการทดสอบเสร็จสมบูรณ์!")
    print("========================================================")
    for r in results_summary:
        print(f"\n📁 ไฟล์: {os.path.basename(r['image'])}")
        print(f"   - ตรวจพบวัตถุ: {len(r['detected_items'])} รายการ")
        if r['voice_alert']:
            print(f"   - คำสั่งเสียง: {r['voice_alert']}")
        if r['vision_ai_summary']:
            print(f"   - คำอธิบาย Vision AI: {r['vision_ai_summary']}")

if __name__ == "__main__":
    main()
