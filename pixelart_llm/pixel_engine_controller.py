import os
from PIL import Image, ImageEnhance, ImageOps, ImageFilter

# Preference remembered: Default to True
PROCESS_ASSETS = True

# Internal "Pixel" resolutions for different categories
# Smaller numbers = Chunkier, more "retro" pixels
CHUNK_S_MAP = {
    "GEM": 32,      # Very chunky/sharp
    "ITEM": 48,     # Standard detail
    "SLOT": 64,     # High detail icons
    "WORLD": 128,   # Environment textures
    "MAP": 160,     # Map details
    "DEFAULT": 48
}

def apply_pixel_perfection(img, category="DEFAULT", final_res=512):
    """
    Universal cleanup with category-aware grid snapping.
    """
    img = img.convert("RGB")
    
    # 1. Kill hardware noise (stray pixels)
    img = img.filter(ImageFilter.MedianFilter(size=3))
    
    # 2. Flatten muddy gradients
    img = ImageOps.posterize(img, 3)
    
    # 3. Sharpen silhouettes
    img = ImageEnhance.Contrast(img).enhance(1.4)
    
    # 4. Category-Aware Grid-Snap
    # Fetch the internal resolution based on the category passed from auto_generate.py
    internal_res = CHUNK_S_MAP.get(category, CHUNK_S_MAP["DEFAULT"])
    
    # Scale down to chunky grid (Nearest Neighbor keeps edges sharp)
    img = img.resize((internal_res, internal_res), resample=Image.NEAREST)
    
    # 5. Lock to 16 colors (Game-ready palette)
    img = img.quantize(colors=16, method=Image.MAXCOVERAGE).convert("RGBA")
    
    # 6. Upscale back to viewable size
    return img.resize((final_res, final_res), resample=Image.NEAREST)

if __name__ == "__main__":
    print("[✓] Controller: Category-Aware Pixel-Logic Active.")
