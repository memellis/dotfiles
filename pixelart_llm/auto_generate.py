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
import pixel_engine_controller as engine

# --- CONFIGURATION ---
BASE_URL = "http://127.0.0.1:7860"
API_URL = f"{BASE_URL}/sdapi/v1/txt2img"
PROG_URL = f"{BASE_URL}/sdapi/v1/progress"
PROMPTS_FILE = "prompts.txt"
OUTPUT_DIR = os.path.expanduser("~/.local/share/pixelart_engine/outputs")

PROCESS_ASSETS = True

SIZES = {
    "GEM": 256, "ITEM": 384, "SLOT": 512, 
    "WORLD": 768, "MAP": 1024, "DEFAULT": 512
}

os.makedirs(OUTPUT_DIR, exist_ok=True)
keep_running = True
total_generation_time = 0.0
images_completed = 0
total_prompts = 0

def signal_handler(sig, frame):
    global keep_running
    print("\n\n[!] Interrupt detected. Finishing current task...")
    keep_running = False

signal.signal(signal.SIGINT, signal_handler)

def format_eta(seconds):
    if seconds <= 0: return "0s"
    m, s = divmod(int(seconds), 60)
    h, m = divmod(m, 60)
    if h > 0: return f"{h}h{m}m"
    if m > 0: return f"{m}m{s}s"
    return f"{s}s"

def get_vram_total():
    try:
        res = subprocess.check_output(["nvidia-smi", "--query-gpu=memory.total", "--format=csv,noheader,nounits"])
        return int(res.decode().strip())
    except: return 0

def slugify(text):
    return re.sub(r'[^\w\s-]', '', text).strip().lower().replace(' ', '_')[:50]

def track_progress(stop_event, current_start_time):
    """Displays progress bar and ETA on a single line."""
    global images_completed, total_prompts, total_generation_time
    
    while not stop_event.is_set() and keep_running:
        try:
            res = requests.get(PROG_URL, timeout=1)
            if res.status_code == 200:
                data = res.json()
                progress = data.get("progress", 0)
                if progress > 0:
                    # 1. Calculate ETA for the CURRENT image
                    elapsed = time.time() - current_start_time
                    estimated_total_for_this_one = elapsed / progress
                    remaining_this_one = estimated_total_for_this_one - elapsed
                    
                    # 2. Calculate ETA for the WHOLE BATCH
                    remaining_items = total_prompts - images_completed - 1
                    if images_completed > 0:
                        avg_per_item = total_generation_time / images_completed
                    else:
                        avg_per_item = estimated_total_for_this_one
                    
                    batch_eta = (avg_per_item * remaining_items) + remaining_this_one
                    
                    # 3. Render the Line
                    percent = progress * 100
                    bar = "█" * int(20 * progress) + "-" * (20 - int(20 * progress))
                    eta_str = format_eta(batch_eta)
                    
                    sys.stdout.write(f"\r    [GPU] |{bar}| {percent:.1f}% | Batch ETA: {eta_str}  ")
                    sys.stdout.flush()
        except: pass
        time.sleep(1)

def generate_images():
    global keep_running, total_generation_time, images_completed, total_prompts
    vram = get_vram_total()
    is_kepler = vram < 4000 
    
    if not os.path.exists(PROMPTS_FILE):
        print(f"[!] Error: {PROMPTS_FILE} not found."); return

    with open(PROMPTS_FILE, "r") as f:
        prompts = [line.strip() for line in f if line.strip()]

    total_prompts = len(prompts)
    print(f"[*] Starting Batch: {total_prompts} items.")
    
    for i, raw_line in enumerate(prompts):
        if not keep_running: break

        category = "DEFAULT"
        if ": " in raw_line:
            cat_part, prompt_text = raw_line.split(": ", 1)
            if cat_part in SIZES: category = cat_part
        else: prompt_text = raw_line

        filename = f"{slugify(prompt_text)}.png"
        filepath = os.path.join(OUTPUT_DIR, filename)

        if os.path.exists(filepath) and os.path.getsize(filepath) > 0:
            images_completed += 1
            continue

        print(f"\n[*] [{i+1}/{total_prompts}] {category}: {prompt_text}")
        
        target_size = SIZES.get(category, 512)
        if is_kepler and target_size > 512: target_size = 512

        payload = {
            "prompt": f"pixel art, {prompt_text}, vibrant colors, 16-bit aesthetic",
            "negative_prompt": "blurry, low quality, photo, realistic",
            "steps": 20, "width": target_size, "height": target_size, 
            "cfg_scale": 7, "sampler_name": "Euler a"
        }

        start_time = time.time()
        stop_event = threading.Event()
        # Passing start_time to the tracker for live math
        threading.Thread(target=track_progress, args=(stop_event, start_time)).start()

        try:
            response = requests.post(API_URL, json=payload, timeout=1200)
            stop_event.set()

            if response.status_code == 200 and keep_running:
                duration = time.time() - start_time
                images_completed += 1
                total_generation_time += duration
                
                img_data = base64.b64decode(response.json()['images'][0])
                with Image.open(BytesIO(img_data)) as img:
                    if PROCESS_ASSETS:
                        img = engine.apply_pixel_perfection(img, category=category)
                    img.save(filepath)
                
                print(f"\n    [DONE] {duration:.1f}s | Saved: {filename}")
            
            if is_kepler: time.sleep(5) 
            
        except Exception as e:
            stop_event.set()
            print(f"\n    [!] Error: {e}")
            time.sleep(5)

if __name__ == "__main__":
    while keep_running:
        try:
            status = requests.get(f"{BASE_URL}/sdapi/v1/options", timeout=2)
            if status.status_code == 200: break
        except:
            time.sleep(2)
    
    if keep_running:
        generate_images()