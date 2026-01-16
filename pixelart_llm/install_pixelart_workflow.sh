import json
import urllib.request
import urllib.parse
import uuid
import os

# Default configuration
SERVER_ADDRESS = "127.0.0.1:8188"
CLIENT_ID = str(uuid.uuid4())
PROCESS_ASSETS = True  # Default as requested

def queue_prompt(prompt):
    p = {"prompt": prompt, "client_id": CLIENT_ID}
    data = json.dumps(p).encode('utf-8')
    req = urllib.request.Request(f"http://{SERVER_ADDRESS}/prompt", data=data)
    return json.loads(urllib.request.urlopen(req).read())

def get_history(prompt_id):
    with urllib.request.urlopen(f"http://{SERVER_ADDRESS}/history/{prompt_id}") as response:
        return json.loads(response.read())

def generate_image(prompt_text):
    """
    Glue function to trigger a basic SDXL generation
    """
    # This is a simplified API-format workflow for SDXL
    # In a real scenario, you'd export your JSON from the ComfyUI 'Save (API)' button
    workflow = {
        "3": {
            "class_type": "KSampler",
            "inputs": {
                "cfg": 8, "denoise": 1, "sampler_name": "euler", 
                "scheduler": "normal", "steps": 20, "seed": 42,
                "model": ["4", 0], "positive": ["6", 0], "negative": ["7", 0], "latent_image": ["5", 0]
            }
        },
        "4": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": "sd_xl_base_1.0.safetensors"}},
        "5": {"class_type": "EmptyLatentImage", "inputs": {"batch_size": 1, "height": 1024, "width": 1024}},
        "6": {"class_type": "CLIPTextEncode", "inputs": {"text": prompt_text, "clip": ["4", 1]}},
        "7": {"class_type": "CLIPTextEncode", "inputs": {"text": "blurry, distorted, low quality", "clip": ["4", 1]}},
        "8": {"class_type": "VAEDecode", "inputs": {"samples": ["3", 0], "vae": ["4", 2]}},
        "9": {"class_type": "SaveImage", "inputs": {"filename_prefix": "ComfyUI", "images": ["8", 0]}}
    }

    print(f"Queueing prompt: {prompt_text}")
    prompt_id = queue_prompt(workflow)['prompt_id']
    
    if PROCESS_ASSETS:
        print("Waiting for assets to process...")
        # Simple polling logic
        import time
        while True:
            history = get_history(prompt_id)
            if prompt_id in history:
                print("Generation complete!")
                return history[prompt_id]
            time.sleep(1)

if __name__ == "__main__":
    # Example Usage
    result = generate_image("A futuristic cyberpunk version of a Dell XPS laptop, high detail, 8k")
    print("Output saved to ComfyUI/output folder.")

