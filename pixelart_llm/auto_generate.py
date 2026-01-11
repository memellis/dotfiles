import requests
import time
import sys
import os
import threading
import re
import base64
import signal
from PIL import Image
from io import BytesIO

# Configuration
BASE_URL = "http://127.0.0.1:7860"
API_URL = f"{BASE_URL}/sdapi/v1/txt2img"
PROG_URL = f"{BASE_URL}/sdapi/v1/progress"
PROMPTS_FILE = "prompts.txt"
OUTPUT_DIR = "outputs/pixelart"

os.makedirs(OUTPUT_DIR, exist_ok=True)

# Global flag for the main loop
keep_running = True

def signal_handler(sig, frame):
    """Handles Ctrl-C to stop the script gracefully."""
    global keep_running
    print("\n\n[!] Interrupt detected (Ctrl-C). Cleaning up and exiting...")
    keep_running = False
    # We don't sys.exit(0) here so the current loop can finish its cleanup

# Register the signal handler
signal.signal(signal.SIGINT, signal_handler)

def slugify(text):
    return re.sub(r'[^\w\s-]', '', text).strip().lower().replace(' ', '_')[:50]

def is_valid_image(filepath):
    if not os.path.exists(filepath):
        return False
    try:
        with Image.open(filepath) as img:
            img.verify()  
        return True
    except:
        return False

def track_progress(stop_event):
    """Background thread for progress and ETA."""
    while not stop_event.is_set():
        try:
            res = requests.get(PROG_URL, timeout=2)
            if res.status_code == 200:
                data = res.json()
                progress = data.get("progress", 0)
                eta = data.get("eta_relative", 0.0)
                
                percent = progress * 100
                bar = "█" * int(20 * progress) + "-" * (20 - int(20 * progress))
                sys.stdout.write(f"\r[GPU Working] |{bar}| {percent:.1f}% | ETA: {eta:.1f}s    ")
                sys.stdout.flush()
        except:
            pass
        time.sleep(1)

def generate_images():
    global keep_running
    if not os.path.exists(PROMPTS_FILE):
        print(f"[!] Error: {PROMPTS_FILE} not found.")
        return

    with open(PROMPTS_FILE, "r") as f:
        prompts = [line.strip() for line in f if line.strip()]

    print(f"[*] Found {len(prompts)} prompts. Ctrl-C to stop safely.")

    for i, prompt in enumerate(prompts):
        if not keep_running:
            break

        filename = f"{slugify(prompt)}.png"
        filepath = os.path.join(OUTPUT_DIR, filename)

        if is_valid_image(filepath):
            continue

        print(f"\n[*] Generating {i+1}/{len(prompts)}: {prompt}")
        
        payload = {
            "prompt": f"pixel art, {prompt}, vibrant colors",
            "negative_prompt": "blurry, low quality, photo, realistic",
            "steps": 20, "width": 512, "height": 512, "cfg_scale": 7, "sampler_name": "Euler a"
        }

        stop_event = threading.Event()
        progress_thread = threading.Thread(target=track_progress, args=(stop_event,))
        progress_thread.start()

        try:
            response = requests.post(API_URL, json=payload, timeout=1200)
            
            stop_event.set()
            progress_thread.join()

            if response.status_code == 200 and keep_running:
                r_json = response.json()
                image_data = base64.b64decode(r_json['images'][0])
                with Image.open(BytesIO(image_data)) as img:
                    img.save(filepath)
                print(f"\n[✓] Saved: {filepath}")
            
        except Exception as e:
            stop_event.set()
            if progress_thread.is_alive():
                progress_thread.join()
            if keep_running: # Don't print error if we are just shutting down
                print(f"\n[!] Error: {e}")

    print("\n[*] Engine processing stopped.")

if __name__ == "__main__":
    try:
        # Wait for API with a check for keep_running
        print(f"[*] Connecting to engine...")
        while keep_running:
            try:
                if requests.get(f"{BASE_URL}/sdapi/v1/options", timeout=2).status_code == 200:
                    break
            except:
                sys.stdout.write(".")
                sys.stdout.flush()
                time.sleep(2)
        
        if keep_running:
            generate_images()
    except KeyboardInterrupt:
        pass # Handled by signal_handler
