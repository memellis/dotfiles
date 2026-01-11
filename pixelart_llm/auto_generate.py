import requests
import time
import sys
import os
import threading

# Configuration
BASE_URL = "http://127.0.0.1:7860"
API_URL = f"{BASE_URL}/sdapi/v1/txt2img"
PROG_URL = f"{BASE_URL}/sdapi/v1/progress"
PROMPTS_FILE = "prompts.txt"
OUTPUT_DIR = "outputs/pixelart"

os.makedirs(OUTPUT_DIR, exist_ok=True)

def wait_for_api():
    """Knocks on the API door until it answers."""
    print(f"[*] Connecting to engine at {BASE_URL}...")
    while True:
        try:
            # We use the internal 'options' endpoint to check readiness
            response = requests.get(f"{BASE_URL}/sdapi/v1/options", timeout=1)
            if response.status_code == 200:
                print("[✓] Connection Established! Engine is ready.")
                break
        except requests.exceptions.ConnectionError:
            sys.stdout.write(".")
            sys.stdout.flush()
            time.sleep(2)

def track_progress(stop_event):
    """Polls the API for progress in the background."""
    while not stop_event.is_set():
        try:
            res = requests.get(PROG_URL, timeout=2)
            if res.status_code == 200:
                data = res.json()
                progress = data.get("progress", 0)
                eta = data.get("eta_relative", 0)
                
                percent = progress * 100
                bar = "█" * int(percent / 5) + "-" * (20 - int(percent / 5))
                sys.stdout.write(f"\r[GPU Working] |{bar}| {percent:.1f}% (ETA: {eta:.1f}s)   ")
                sys.stdout.flush()
        except:
            pass
        time.sleep(1)

def generate_images():
    if not os.path.exists(PROMPTS_FILE):
        print(f"[!] Error: {PROMPTS_FILE} not found.")
        return

    with open(PROMPTS_FILE, "r") as f:
        prompts = [line.strip() for line in f if line.strip()]

    print(f"[*] Found {len(prompts)} prompts.")

    for i, prompt in enumerate(prompts):
        print(f"\n[*] Prompt {i+1}/{len(prompts)}: {prompt}")
        
        payload = {
            "prompt": f"pixel art, {prompt}, vibrant colors",
            "negative_prompt": "blurry, low quality, photo",
            "steps": 20,
            "width": 512,
            "height": 512,
            "cfg_scale": 7,
            "sampler_name": "Euler a"
        }

        stop_event = threading.Event()
        progress_thread = threading.Thread(target=track_progress, args=(stop_event,))
        progress_thread.start()

        try:
            response = requests.post(API_URL, json=payload, timeout=900)
            stop_event.set()
            progress_thread.join()

            if response.status_code == 200:
                print(f"\n[✓] Image {i+1} saved to {OUTPUT_DIR}")
            else:
                print(f"\n[!] API Error: {response.status_code}")
        except Exception as e:
            stop_event.set()
            print(f"\n[!] Error during request: {e}")

if __name__ == "__main__":
    # 1. Wait for engine to wake up
    wait_for_api()
    # 2. Start generation
    generate_images()
    