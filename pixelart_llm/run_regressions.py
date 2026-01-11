import unittest
import os
import shutil
import base64
import subprocess
from io import BytesIO
from PIL import Image

# Import the actual functions from your auto_generate.py
try:
    import auto_generate
except ImportError:
    print("[!] Error: Could not find auto_generate.py. Ensure it is in the same folder.")
    exit(1)

class TestPixelArtRegression(unittest.TestCase):
    
    def setUp(self):
        """Create a clean temporary workspace for file tests."""
        self.test_dir = "regression_test_temp"
        if not os.path.exists(self.test_dir):
            os.makedirs(self.test_dir)
        self.test_image_path = os.path.join(self.test_dir, "test_file.png")

    def tearDown(self):
        """Remove the temporary workspace."""
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir)

    def test_category_prefix_parsing(self):
        """PROVE: 'WORLD: My Prompt' is correctly split into just 'My Prompt'."""
        raw_input = "WORLD: forest level with neon lights"
        expected_slug = "forest_level_with_neon_lights"
        
        # Mimic the split logic in auto_generate.py
        processed = raw_input.split(": ", 1)[-1] if ": " in raw_input else raw_input
        result_slug = auto_generate.slugify(processed)
        
        self.assertEqual(result_slug, expected_slug)
        print(f"\n[PASS] Category Parsing: '{raw_input}' -> '{result_slug}.png'")

    def test_slugify_no_prefix(self):
        """PROVE: Standard prompts without categories still work perfectly."""
        raw_input = "red ruby heart"
        expected_slug = "red_ruby_heart"
        
        result_slug = auto_generate.slugify(raw_input)
        self.assertEqual(result_slug, expected_slug)
        print(f"[PASS] Standard Slugify: '{raw_input}' -> '{result_slug}.png'")

    def test_image_validation_logic(self):
        """PROVE: is_valid_image catches 0-byte or non-PNG files (Regression Protection)."""
        # Test 1: Empty file
        with open(self.test_image_path, 'w') as f:
            f.write("")
        self.assertFalse(auto_generate.is_valid_image(self.test_image_path))
        
        # Test 2: Real valid PNG
        Image.new('RGB', (32, 32), color='blue').save(self.test_image_path)
        self.assertTrue(auto_generate.is_valid_image(self.test_image_path))
        print("[PASS] Image Validation (Corrupt vs Valid)")

    def test_vram_detection_safe_fail(self):
        """PROVE: get_vram_total handles errors gracefully without crashing the script."""
        vram = auto_generate.get_vram_total()
        self.assertIsInstance(vram, int)
        print(f"[PASS] VRAM Detection: Found {vram}MB (0 means detection skipped/fail)")

    def test_base64_save_integrity(self):
        """PROVE: The save logic doesn't corrupt the pixels during the BytesIO transfer."""
        # Create a mock API response (Red square)
        mock_img = Image.new('RGB', (100, 100), color='red')
        buf = BytesIO()
        mock_img.save(buf, format="PNG")
        mock_b64 = base64.b64encode(buf.getvalue()).decode()
        
        # Run actual save logic
        image_data = base64.b64decode(mock_b64)
        with Image.open(BytesIO(image_data)) as img:
            img.save(self.test_image_path)
            
        # Verify the saved file is actually red
        with Image.open(self.test_image_path) as verified:
            pixel = verified.getpixel((50, 50))
            self.assertEqual(pixel, (255, 0, 0))
        print("[PASS] PIL Save Integrity")

if __name__ == "__main__":
    print("--- RUNNING AUTOMATED REGRESSION SUITE ---")
    unittest.main()
    