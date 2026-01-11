import requests
import time
import sys
import os
import threading
import re
import base64
from PIL import Image
from io import BytesIO

# Configuration
BASE_URL = "http://127.0.0.1:7860"
API_URL = f"{BASE_URL}/sdapi/v1/txt2img"
PROG_URL = f"{BASE_URL}/sdapi/v1/progress"
PROMPTS_FILE = "prompts.txt"
OUTPUT_DIR = "outputs/pixelart"

os.makedirs(OUTPUT_DIR, exist_ok=True)

def slugify(text):
    """Converts a prompt into a safe filename."""
    return re.sub(r'[^\w\s-]', '', text).strip().lower().replace(' ', '_')[:50]

def is_valid_image(filepath):
    """Uses Pillow to verify the image exists and is not corrupt."""
    if not os.path.exists(filepath):
        return False
    try:
        with Image.open(filepath) as img:
            img.verify()  
        return True
    except Exception:
        return False

def wait_for_api():
    """Waits until the API is responsive."""
    print(f"[*] Connecting to engine at {BASE_URL}...")
    while True:
        try:
            response = requests.get(f"{BASE_URL}/sdapi/v1/options", timeout=2)
            if response.status_code == 200:
                print("[✓] Connection Established!")
                break
        except requests.exceptions.ConnectionError:
            sys.stdout.write(".")
            sys.stdout.flush()
            time.sleep(2)

def track_progress(stop_event):
    """Background thread to poll the API and display progress bar + ETA."""
    while not stop_event.is_set():
        try:
            # Poll the progress endpoint
            res = requests.get(PROG_URL, timeout=2)
            if res.status_code == 200:
                data = res.json()
                progress = data.get("progress", 0)
                # Ensure we get the ETA (seconds remaining)
                eta = data.get("eta_relative", 0.0)
                
                percent = progress * 100
                bar_len = 20
                filled = int(bar_len * progress)
                bar = "█" * filled + "-" * (bar_len - filled)
                
                # FIXED: Formatted string to show both % and ETA in seconds
                sys.stdout.write(f"\r[GPU Working] |{bar}| {percent:.1f}% | ETA: {eta:.1f}s    ")
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

    print(f"[*] Found {len(prompts)} prompts. Syncing with {OUTPUT_DIR}...")

    for i, prompt in enumerate(prompts):
        filename = f"{slugify(prompt)}.png"
        filepath = os.path.join(OUTPUT_DIR, filename)

        if is_valid_image(filepath):
            print(f"[-] Skipping {i+1}/{len(prompts)}: '{prompt}' (Valid image exists)")
            continue

        print(f"\n[*] Generating {i+1}/{len(prompts)}: {prompt}")
        
        payload = {
            "prompt": f"pixel art, {prompt}, vibrant colors",
            "negative_prompt": "blurry, low quality, photo, realistic",
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
            # POST request blocks until the image is generated
            response = requests.post(API_URL, json=payload, timeout=1200)
            
            # Signal the background thread to stop
            stop_event.set()
            progress_thread.join()

            if response.status_code == 200:
                r_json = response.json()
                image_data = base64.b64decode(r_json['images'][0])
                
                # Open with Pillow to ensure it's valid before saving
                with Image.open(BytesIO(image_data)) as img:
                    img.save(filepath)
                print(f"\n[✓] Saved: {filepath}")
            else:
                print(f"\n[!] API Error: {response.status_code}")
                
        except Exception as e:
            stop_event.set()
            print(f"\n[!] Error during {prompt}: {e}")

if __name__ == "__main__":
    wait_for_api()
    generate_images()
    