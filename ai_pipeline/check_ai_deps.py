import sys

modules = ['cv2', 'ultralytics', 'gtts', 'pygame', 'torch', 'PIL']
for m in modules:
    try:
        mod = __import__(m)
        print(f"[OK] {m}: {getattr(mod, '__version__', 'loaded')}")
    except Exception as e:
        print(f"[MISSING] {m}: {e}")
