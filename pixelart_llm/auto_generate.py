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
keep_running = True

# Performance tracking globals
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
    if not os.path.exists(PROMPTS_FILE):
        print(f"[!] Error: {PROMPTS_FILE} not found.")
        return

    vram = get_vram_total()
    with open(PROMPTS_FILE, "r") as f:
        prompts = [line.strip() for line in f if line.strip()]

    print(f"[*] Total Prompts: {len(prompts)} | Hardware: {'GTX 780 Pacing' if vram < 4000 else 'Standard'}")

    for i, raw_line in enumerate(prompts):
        if not keep_running:
            break

        prompt_text = raw_line.split(": ", 1)[-1] if ": " in raw_line else raw_line
        filename = f"{slugify(prompt_text)}.png"
        filepath = os.path.join(OUTPUT_DIR, filename)

        if is_valid_image(filepath):
            continue

        print(f"\n[*] Generating {i+1}/{len(prompts)}: {prompt_text}")
        
        payload = {
            "prompt": f"pixel art, {prompt_text}, vibrant colors, 16-bit aesthetic",
            "negative_prompt": "blurry, low quality, photo, realistic, 3d render",
            "steps": 20, "width": 512, "height": 512, "cfg_scale": 7, "sampler_name": "Euler a"
        }

        # Timer Start
        start_time = time.time()
        
        stop_event = threading.Event()
        progress_thread = threading.Thread(target=track_progress, args=(stop_event,))
        progress_thread.start()

        try:
            response = requests.post(API_URL, json=payload, timeout=1200)
            
            stop_event.set()
            progress_thread.join()

            if response.status_code == 200 and keep_running:
                # Timer End
                end_time = time.time()
                duration = end_time - start_time
                
                # Calculate Averages
                images_completed += 1
                total_time += duration
                avg_time = total_time / images_completed

                r_json = response.json()
                image_data = base64.b64decode(r_json['images'][0])
                
                with Image.open(BytesIO(image_data)) as img:
                    img.save(filepath)
                
                # Display individual and average performance
                print(f"\r    [DONE] Time: {duration:.2f}s | Avg: {avg_time:.2f}s | Saved: {filename}")
            
            if vram < 4000:
                time.sleep(5)
            
        except Exception as e:
            stop_event.set()
            if progress_thread.is_alive():
                progress_thread.join()
            if keep_running:
                print(f"\n    [!] Error: {e}")
                time.sleep(5)

    print(f"\n[*] Batch Complete. Total Images: {images_completed} | Session Avg: {total_time/max(1, images_completed):.2f}s")

if __name__ == "__main__":
    try:
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
    