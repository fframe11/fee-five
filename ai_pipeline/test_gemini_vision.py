import os
import sys
import json
import base64
import urllib.request
import urllib.error

try:
    sys.stdout.reconfigure(line_buffering=True, encoding='utf-8')
except Exception:
    pass

def load_env():
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

def test_gemini_image(image_path: str, model_name: str = "gemini-flash-latest"):
    load_env()
    api_key = (
        os.environ.get("GOOGLE_API_KEY") or
        os.environ.get("GEMINI_API_KEY") or
        os.environ.get("GEMINI_API") or
        os.environ.get("Google_api") or
        os.environ.get("gemini_api")
    )

    with open(image_path, "rb") as f:
        img_b64 = base64.b64encode(f.read()).decode('utf-8')

    prompt = (
        "คุณคือ AI ผู้ช่วยนำทางคนตาบอดในประเทศไทย จงวิเคราะห์ภาพถ่ายทางนี้ "
        "บอกสิ่งกีดขวางที่เป็นอันตรายที่อยู่ข้างหน้าอย่างกระชับ เช่น เสาไฟฟ้า หลุม บันได หรือทางต่างระดับ "
        "ระบุตำแหน่ง ซ้าย-กลาง-ขวา และแนะนำสั้นๆ ว่าควรเดินหลบไปทางไหน "
        "ข้อกำหนด: ตอบเป็นภาษาไทยสั้นๆ 1-2 ประโยคเท่านั้น เพื่อความปลอดภัยในการเดิน"
    )

    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model_name}:generateContent?key={api_key}"
    payload = {
        "contents": [
            {
                "parts": [
                    {"text": prompt},
                    {
                        "inline_data": {
                            "mime_type": "image/jpeg",
                            "data": img_b64
                        }
                    }
                ]
            }
        ],
        "generationConfig": {
            "temperature": 0.2,
            "maxOutputTokens": 500
        }
    }

    try:
        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode('utf-8'),
            headers={"Content-Type": "application/json", "User-Agent": "FeeFive/1.0"},
            method='POST'
        )
        with urllib.request.urlopen(req, timeout=25) as res:
            data = json.loads(res.read().decode('utf-8'))
            candidates = data.get("candidates", [])
            if candidates:
                text = candidates[0]["content"]["parts"][0]["text"].strip()
                import re
                clean_text = re.sub(r'<think>.*?</think>', '', text, flags=re.DOTALL).strip()
                print(f"\n=======================================================")
                print(f" 🎉 ผลการวิเคราะห์จาก Google Gemini [{model_name}]:")
                print(f" 📸 ภาพ: {os.path.basename(image_path)}")
                print(f"=======================================================")
                print(f"\"{clean_text}\"")
                return True
    except urllib.error.HTTPError as e:
        print(f"HTTP Error ({e.code}): {e.read().decode('utf-8')}")
    except Exception as e:
        print(f"Error: {e}")
    return False

if __name__ == "__main__":
    print("=======================================================")
    print(" 🚀 ทดสอบเรียกใช้ Google Gemini API")
    print("=======================================================")
    
    for img in ["เสา.jpg", "พื้นต่างระดับ.jpg"]:
        full_path = os.path.join(os.path.dirname(__file__), "..", img)
        if not os.path.exists(full_path):
            full_path = img
        test_gemini_image(full_path, "gemini-flash-latest")
