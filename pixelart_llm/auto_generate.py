import requests
import time
import sys
import os
import threading
import re
import base64
import signal
import subprocess
import hashlib
from PIL import Image
from io import BytesIO
import pixel_engine_controller as engine

# --- CONFIGURATION ---
BASE_URL = "http://127.0.0.1:7860"
API_URL = f"{BASE_URL}/sdapi/v1/txt2img"
PROG_URL = f"{BASE_URL}/sdapi/v1/progress"
PROMPTS_FILE = "prompts.txt"
OUTPUT_DIR = os.path.expanduser("~/.local/share/pixelart_engine/outputs")

# Instructions: Default to True
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
skipped_count = 0

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

def get_prompt_hash(text):
    """Creates a unique 32-character MD5 hash for any prompt string."""
    return hashlib.md5(text.strip().encode('utf-8')).hexdigest()

def track_progress(stop_event, current_start_time, remaining_work_count):
    """Displays progress bar and ETA based ONLY on work remaining in this session."""
    global images_completed, total_generation_time, skipped_count
    
    while not stop_event.is_set() and keep_running:
        try:
            res = requests.get(PROG_URL, timeout=1)
            if res.status_code == 200:
                data = res.json()
                progress = data.get("progress", 0)
                if progress > 0:
                    # 1. Math for the single item currently being processed
                    elapsed = time.time() - current_start_time
                    est_single = elapsed / progress
                    rem_single = est_single - elapsed
                    
                    # 2. Math for the remaining session queue
                    done_this_session = images_completed - skipped_count
                    left_in_session = remaining_work_count - done_this_session - 1
                    
                    if done_this_session > 0:
                        avg_speed = total_generation_time / done_this_session
                    else:
                        avg_speed = est_single
                    
                    batch_eta = (avg_speed * left_in_session) + rem_single
                    
                    percent = progress * 100
                    bar = "█" * int(20 * progress) + "-" * (20 - int(20 * progress))
                    eta_str = format_eta(batch_eta)
                    
                    sys.stdout.write(f"\r    [GPU] |{bar}| {percent:.1f}% | Session ETA: {eta_str}  ")
                    sys.stdout.flush()
        except: pass
        time.sleep(1)

def generate_images():
    global keep_running, total_generation_time, images_completed, total_prompts, skipped_count
    vram = get_vram_total()
    is_kepler = vram < 4000 
    
    if not os.path.exists(PROMPTS_FILE):
        print(f"[!] Error: {PROMPTS_FILE} not found."); return

    with open(PROMPTS_FILE, "r") as f:
        all_lines = [line.strip() for line in f if line.strip()]

    total_prompts = len(all_lines)
    valid_prompts = []
    
    print(f"[*] Auditing {total_prompts} prompts against local storage...")
    
    # SILENT AUDIT: Check for existing hashes
    for raw_line in all_lines:
        file_hash = get_prompt_hash(raw_line)
        filepath = os.path.join(OUTPUT_DIR, f"{file_hash}.png")

        if os.path.exists(filepath) and os.path.getsize(filepath) > 0:
            skipped_count += 1
        else:
            valid_prompts.append(raw_line)

    images_completed = skipped_count
    remaining_work_count = len(valid_prompts)

    print(f"[*] Audit Results: {skipped_count} found, {remaining_work_count} remaining.")

    if remaining_work_count == 0:
        print("[✓] All tasks already completed. Total images: 50/50.")
        return

    start_batch_time = time.time()
    
    for i, raw_line in enumerate(valid_prompts):
        if not keep_running: break

        category = "DEFAULT"
        if ": " in raw_line:
            cat_part, p_text = raw_line.split(": ", 1)
            if cat_part.upper() in SIZES: category = cat_part.upper()
        else: p_text = raw_line

        file_hash = get_prompt_hash(raw_line)
        filename = f"{file_hash}.png"
        filepath = os.path.join(OUTPUT_DIR, filename)

        # Global index display (Current iteration + what we skipped)
        current_display_idx = i + skipped_count + 1
        print(f"\n[*] [{current_display_idx}/{total_prompts}] {category}: {p_text[:60]}...")
        
        target_size = SIZES.get(category, 512)
        if is_kepler and target_size > 512: target_size = 512

        payload = {
            "prompt": f"pixel art, {p_text}, vibrant colors, 16-bit aesthetic",
            "negative_prompt": "blurry, low quality, photo, realistic, shadows, gradients",
            "steps": 20, "width": target_size, "height": target_size, 
            "cfg_scale": 7, "sampler_name": "Euler a"
        }

        start_time = time.time()
        stop_event = threading.Event()
        threading.Thread(target=track_progress, args=(stop_event, start_time, remaining_work_count)).start()

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
                
                print(f"\n    [DONE] {duration:.1f}s | Hash: {file_hash}")
            
            if is_kepler: time.sleep(2) 
            
        except Exception as e:
            stop_event.set()
            print(f"\n    [!] Error: {e}")
            time.sleep(5)

    if keep_running:
        total_session_duration = time.time() - start_batch_time
        print("\n" + "="*40)
        print(f" BATCH COMPLETE")
        print(f" Session Time: {format_eta(total_session_duration)}")
        print(f" New Files:    {remaining_work_count}")
        print(f" Total Files:  {images_completed}")
        print("="*40 + "\n")

if __name__ == "__main__":
    # Wait for SD to be alive
    while keep_running:
        try:
            if requests.get(f"{BASE_URL}/sdapi/v1/options", timeout=2).status_code == 200: break
        except: time.sleep(2)
    
    if keep_running:
        generate_images()
    