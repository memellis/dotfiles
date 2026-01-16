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
# Import the controller to handle pixel perfection
import pixel_engine_controller as engine

# --- CONFIGURATION ---
BASE_URL = "http://127.0.0.1:7860"
API_URL = f"{BASE_URL}/sdapi/v1/txt2img"
PROG_URL = f"{BASE_URL}/sdapi/v1/progress"
PROMPTS_FILE = "prompts.txt"
OUTPUT_DIR = os.path.expanduser("~/.local/share/pixelart_engine/outputs")

# Preference: Default to True
PROCESS_ASSETS = True

# Resolution Mapping
SIZES = {
    "GEM": 256, "ITEM": 384, "SLOT": 512, 
    "WORLD": 768, "MAP": 1024, "DEFAULT": 512
}

os.makedirs(OUTPUT_DIR, exist_ok=True)
keep_running = True
total_time = 0.0
images_completed = 0

def signal_handler(sig, frame):
    global keep_running
    print("\n\n[!] Interrupt detected (Ctrl-C). Finishing current task...")
    keep_running = False

signal.signal(signal.SIGINT, signal_handler)

def get_vram_total():
    try:
        res = subprocess.check_output(["nvidia-smi", "--query-gpu=memory.total", "--format=csv,noheader,nounits"])
        return int(res.decode().strip())
    except:
        return 0

def slugify(text):
    return re.sub(r'[^\w\s-]', '', text).strip().lower().replace(' ', '_')[:50]

def is_valid_image(filepath):
    if not os.path.exists(filepath) or os.path.getsize(filepath) == 0:
        return False
    try:
        with Image.open(filepath) as img:
            img.verify()  
        return True
    except:
        return False

def track_progress(stop_event):
    while not stop_event.is_set() and keep_running:
        try:
            res = requests.get(PROG_URL, timeout=1)
            if res.status_code == 200:
                data = res.json()
                progress = data.get("progress", 0)
                percent = progress * 100
                bar = "█" * int(20 * progress) + "-" * (20 - int(20 * progress))
                sys.stdout.write(f"\r    [GPU Working] |{bar}| {percent:.1f}% ")
                sys.stdout.flush()
        except:
            pass
        time.sleep(1)

def generate_images():
    global keep_running, total_time, images_completed
    vram = get_vram_total()
    is_kepler = vram < 4000 
    
    if not os.path.exists(PROMPTS_FILE):
        print(f"[!] Error: {PROMPTS_FILE} not found.")
        return

    with open(PROMPTS_FILE, "r") as f:
        prompts = [line.strip() for line in f if line.strip()]

    print(f"[*] Starting Batch: {len(prompts)} items.")
    print(f"[*] GPU Stats: {vram}MB VRAM | Kepler Safety: {is_kepler}")

    for i, raw_line in enumerate(prompts):
        if not keep_running: break

        category = "DEFAULT"
        if ": " in raw_line:
            category_part, prompt_text = raw_line.split(": ", 1)
            if category_part in SIZES:
                category = category_part
        else:
            prompt_text = raw_line

        target_size = SIZES.get(category, SIZES["DEFAULT"])
        if is_kepler and target_size > 512:
            target_size = 512

        filename = f"{slugify(prompt_text)}.png"
        filepath = os.path.join(OUTPUT_DIR, filename)

        if is_valid_image(filepath):
            continue

        print(f"\n[*] [{category}] Generating {i+1}/{len(prompts)}: {prompt_text}")
        
        payload = {
            "prompt": f"pixel art, {prompt_text}, vibrant colors, 16-bit aesthetic",
            "negative_prompt": "blurry, low quality, photo, realistic, 3d render",
            "steps": 20, "width": target_size, "height": target_size, 
            "cfg_scale": 7, "sampler_name": "Euler a"
        }

        start_time = time.time()
        stop_event = threading.Event()
        progress_thread = threading.Thread(target=track_progress, args=(stop_event,))
        progress_thread.start()

        try:
            response = requests.post(API_URL, json=payload, timeout=1200)
            stop_event.set()
            progress_thread.join()

            if response.status_code == 200 and keep_running:
                duration = time.time() - start_time
                images_completed += 1
                total_time += duration
                
                img_data = base64.b64decode(response.json()['images'][0])
                with Image.open(BytesIO(img_data)) as img:
                    # --- PIXEL PERFECT PROCESSING ---
                    if PROCESS_ASSETS:
                        # Pass the specific category to adjust internal pixel chunkiness
                        img = engine.apply_pixel_perfection(img, category=category)
                    
                    img.save(filepath)
                
                avg_time = total_time / images_completed
                print(f"\r    [DONE] {target_size}px | Time: {duration:.2f}s | Avg: {avg_time:.2f}s | Saved: {filename}")
            
            if is_kepler: time.sleep(8) 
            
        except Exception as e:
            stop_event.set()
            print(f"\n    [!] Error: {e}")
            time.sleep(5)

    print(f"\n[*] Session Finished. Total Images: {images_completed} | Avg Speed: {total_time/max(1, images_completed):.2f}s")

if __name__ == "__main__":
    wait_count = 0
    try:
        while keep_running:
            try:
                status = requests.get(f"{BASE_URL}/sdapi/v1/options", timeout=2)
                if status.status_code == 200:
                    print("\n[✓] Backend API detected and responsive.")
                    break
            except (requests.exceptions.ConnectionError, requests.exceptions.Timeout):
                wait_count += 2
                sys.stdout.write(f"\r[*] Waiting for Stable Diffusion API (Options Request)... {wait_count}s")
                sys.stdout.flush()
                time.sleep(2)
        
        if keep_running:
            generate_images()
    except KeyboardInterrupt:
        pass