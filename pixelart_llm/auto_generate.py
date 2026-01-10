import requests, time, base64, os, subprocess, threading, json, math
from PIL import Image

# --- CONFIG ---
URL = "http://127.0.0.1:7860"
OUT_DIR = "output/slot_assets"
PROMPT_FILE = "prompts.txt"
STYLE_SUFFIX = "pixel art, 16-bit arcade style, white background, thick black outline"
TILE_SIZE = 512

def get_gpu_metrics():
    try:
        cmd = "nvidia-smi --query-gpu=memory.total,temperature.gpu,memory.used --format=csv,noheader,nounits"
        out = subprocess.check_output(cmd.split()).decode('utf-8').strip().split(',')
        return int(out[0]), int(out[1]), int(out[2])
    except: return 0, 0, 0

def progress_heartbeat(stop_event, start_time):
    """Reports status every 5 seconds on a single line."""
    while not stop_event.is_set():
        _, temp, vram_used = get_gpu_metrics()
        elapsed = int(time.time() - start_time)
        # \r overwrites the current line
        print(f"\r  [Status] {elapsed}s | Temp: {temp}°C | VRAM: {vram_used}MB    ", end="", flush=True)
        time.sleep(5)

def is_valid_image(path):
    if not os.path.exists(path) or os.path.getsize(path) == 0: return False
    try:
        with Image.open(path) as img:
            img.verify()
        return True
    except: return False

def stitch_assets():
    print("\n\nStitching final sprite sheet...")
    images = [f for f in os.listdir(OUT_DIR) if f.endswith('.png') and "spritesheet" not in f]
    if not images: return
    
    count = len(images)
    cols = math.ceil(math.sqrt(count))
    rows = math.ceil(count / cols)
    sheet = Image.new("RGBA", (cols * TILE_SIZE, rows * TILE_SIZE), (0,0,0,0))
    
    manifest = {"frames": {}}
    for index, img_name in enumerate(sorted(images)):
        img = Image.open(os.path.join(OUT_DIR, img_name))
        x, y = (index % cols) * TILE_SIZE, (index // cols) * TILE_SIZE
        sheet.paste(img, (x, y))
        manifest["frames"][img_name] = {"frame": {"x": x, "y": y, "w": TILE_SIZE, "h": TILE_SIZE}}
        
    sheet.save(os.path.join(OUT_DIR, "spritesheet.png"))
    with open(os.path.join(OUT_DIR, "spritesheet.json"), "w") as f:
        json.dump(manifest, f, indent=4)
    print("Master sheet and JSON manifest created.")

def generate():
    vram_total, _, _ = get_gpu_metrics()
    cooldown = 4 if vram_total < 4000 else 1
    request_timeout = 1000 if vram_total < 4000 else 300
    
    if not os.path.exists(OUT_DIR): os.makedirs(OUT_DIR)
    if not os.path.exists(PROMPT_FILE):
        print(f"Error: {PROMPT_FILE} not found."); return
        
    with open(PROMPT_FILE, "r") as f:
        prompts = [line.strip() for line in f if line.strip()]

    print(f"\n--- Resource Aware Generator ---")
    print(f"Target: {len(prompts)} items | Mode: {'Legacy' if vram_total < 4000 else 'Modern'}")

    for i, raw_text in enumerate(prompts):
        asset_name = raw_text.replace(" ", "_")[:30]
        path = os.path.join(OUT_DIR, f"{asset_name}.png")

        if is_valid_image(path):
            print(f"[{i+1}/{len(prompts)}] Skipping Valid: {asset_name}")
            continue

        print(f"[{i+1}/{len(prompts)}] GENERATING: {asset_name}")
        
        stop_heartbeat = threading.Event()
        hb = threading.Thread(target=progress_heartbeat, args=(stop_heartbeat, time.time()))
        hb.start()

        payload = {
            "prompt": f"{raw_text}, {STYLE_SUFFIX}",
            "negative_prompt": "blurry, low quality, 3d, realistic, shadow, text",
            "steps": 18, "width": TILE_SIZE, "height": TILE_SIZE, "cfg_scale": 7
        }
        
        try:
            r = requests.post(f"{URL}/sdapi/v1/txt2img", json=payload, timeout=request_timeout)
            stop_heartbeat.set()
            hb.join()
            
            if r.status_code == 200:
                with open(path, "wb") as f:
                    f.write(base64.b64decode(r.json()['images'][0]))
                print(f"\r  [DONE] Saved {asset_name}                          ")
            else:
                print(f"\r  [!] Server Error: {r.status_code}               ")
        except Exception as e:
            stop_heartbeat.set()
            hb.join()
            print(f"\r  [!] Error: {e}                                      ")
        
        time.sleep(cooldown)

    stitch_assets()
    print("\n--- ALL TASKS COMPLETE ---")

if __name__ == "__main__":
    generate()
