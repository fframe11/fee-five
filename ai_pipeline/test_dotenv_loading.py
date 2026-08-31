import os
import dotenv

def test_dotenv():
    # Load .env file
    current_dir = os.path.dirname(os.path.abspath(__file__))
    parent_dir = os.path.dirname(current_dir)
    loaded = False
    for env_path in [os.path.join(current_dir, ".env"), os.path.join(parent_dir, ".env")]:
        if os.path.exists(env_path):
            dotenv.load_dotenv(env_path)
            loaded = True
            print(f"Loaded .env from {env_path}")
            break
            
    if not loaded:
        print("Error: .env file not found")
        exit(1)
        
    api_key = os.environ.get("Roboflow_api") or os.environ.get("ROBOFLOW_API")
    if not api_key:
        print("Error: Roboflow_api key not found in environment variables")
        exit(1)
        
    if len(api_key) < 15:
        print("Error: API key is too short")
        exit(1)
        
    print(f"API key successfully loaded: {api_key[:5]}...{api_key[-5:]}")
    print("Verification passed!")
    exit(0)

if __name__ == "__main__":
    test_dotenv()
