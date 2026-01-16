import os
from PIL import Image, ImageEnhance, ImageOps, ImageFilter

# Preference remembered: Default to True
PROCESS_ASSETS = True

def apply_pixel_perfection(img, internal_res=48, final_res=512):
    """
    Universal cleanup for any object:
    1. Median Filter: Automatically deletes 'salt and pepper' noise and glitch lines.
    2. Posterize: Forces colors into solid blocks (essential for game assets).
    3. Grid-Snap: Downscales to 48px to create the 'Pixel Art' look.
    4. Quantize: Forces a strict 16-color limit for a clean palette.
    """
    img = img.convert("RGB")
    
    # Kill hardware noise (stray pixels)
    img = img.filter(ImageFilter.MedianFilter(size=3))
    
    # Flatten muddy gradients into distinct color steps
    img = ImageOps.posterize(img, 3)
    
    # Sharpen the contrast for clear object silhouettes
    img = ImageEnhance.Contrast(img).enhance(1.4)
    
    # Scale down to chunky grid (Nearest Neighbor keeps edges sharp)
    img = img.resize((internal_res, internal_res), resample=Image.NEAREST)
    
    # Lock to 16 colors
    img = img.quantize(colors=16, method=Image.MAXCOVERAGE).convert("RGBA")
    
    # Upscale back to viewable size
    return img.resize((final_res, final_res), resample=Image.NEAREST)

if __name__ == "__main__":
    print("[✓] Controller: General Pixel-Logic Active.")
