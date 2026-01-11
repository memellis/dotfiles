import requests
import time
import sys
import os
import threading
import re
import base64
import signal
import subprocess
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
    print("\n\n[!] Interrupt detected (Ctrl-C). Finishing current task...")
    keep_running = False

# Register the signal handler
signal.signal(signal.SIGINT, signal_handler)

def get_vram_total():
    """Detects VRAM to adjust pacing for GTX 780 vs RTX 4070."""
    try:
        res = subprocess.check_output(["nvidia-smi", "--query-gpu=memory.total", "--format=csv,noheader,nounits"])
        return int(res.decode().strip())
    except:
        return 0

def slugify(text):
    """Converts prompt to a safe filename."""
    return re.sub(r'[^\w\s-]', '', text).strip().lower().replace(' ', '_')[:50]

def is_valid_image(filepath):
    """Regression protection: ensures we don't skip over a corrupt or 0-byte file."""
    if not os.path.exists(filepath) or os.path.getsize(filepath) == 0:
        return False
    try:
        with Image.open(filepath) as img:
            img.verify()  
        return True
    except:
        return False

def track_progress(stop_event):
    """Background thread for live progress bars without blocking the GPU call."""
    while not stop_event.is_set() and keep_running:
        try:
            res = requests.get(PROG_URL, timeout=1)
            if res.status_code == 200:
                data = res.json()
                progress = data.get("progress", 0)
                eta = data.get("eta_relative", 0.0)
                
                percent = progress * 100
                bar = "█" * int(20 * progress) + "-" * (20 - int(20 * progress))
                sys.stdout.write(f"\r    [GPU Working] |{bar}| {percent:.1f}% | ETA: {eta:.1f}s    ")
                sys.stdout.flush()
        except:
            pass
        time.sleep(1)

def generate_images():
    global keep_running
    if not os.path.exists(PROMPTS_FILE):
        print(f"[!] Error: {PROMPTS_FILE} not found.")
        return

    vram = get_vram_total()
    with open(PROMPTS_FILE, "r") as f:
        prompts = [line.strip() for line in f if line.strip()]

    print(f"[*] Total Prompts: {len(prompts)}. Hardware Pacing: {'Active' if vram < 4000 else 'Disabled'}")

    for i, raw_line in enumerate(prompts):
        if not keep_running:
            break

        # Regression Fix: Handle "CATEGORY: prompt" format without breaking filenames
        prompt_text = raw_line.split(": ", 1)[-1] if ": " in raw_line else raw_line
        filename = f"{slugify(prompt_text)}.png"
        filepath = os.path.join(OUTPUT_DIR, filename)

        if is_valid_image(filepath):
            continue

        print(f"\n[*] Generating {i+1}/{len(prompts)}: {prompt_text}")
        
        payload = {
            "prompt": f"pixel art, {prompt_text}, vibrant colors, 16-bit aesthetic",
            "negative_prompt": "blurry, low quality, photo, realistic, 3d render",
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
            # Long timeout for GTX 780 swaps
            response = requests.post(API_URL, json=payload, timeout=1200)
            
            stop_event.set()
            progress_thread.join()

            if response.status_code == 200 and keep_running:
                r_json = response.json()
                image_data = base64.b64decode(r_json['images'][0])
                
                # Verified saving logic (prevents regression crashes)
                with Image.open(BytesIO(image_data)) as img:
                    img.save(filepath)
                print(f"\n[✓] Saved: {filename}")
            
            # Pacing: Keep the GTX 780 from overheating
            if vram < 4000:
                time.sleep(5)
            
        except Exception as e:
            stop_event.set()
            if progress_thread.is_alive():
                progress_thread.join()
            if keep_running:
                print(f"\n[!] Error on prompt '{prompt_text}': {e}")
                time.sleep(5)

    print("\n[*] Engine processing stopped.")

if __name__ == "__main__":
    try:
        # Pre-flight: Wait for the API to be fully responsive
        print(f"[*] Connecting to engine at {BASE_URL}...")
        while keep_running:
            try:
                if requests.get(f"{BASE_URL}/sdapi/v1/options", timeout=2).status_code == 200:
                    print("[✓] Connection established.")
                    break
            except:
                sys.stdout.write(".")
                sys.stdout.flush()
                time.sleep(2)
        
        if keep_running:
            generate_images()
    except KeyboardInterrupt:
        pass
