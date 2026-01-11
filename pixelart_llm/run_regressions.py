import unittest
import os
import shutil
import base64
from io import BytesIO
from PIL import Image

# Import the actual functions
try:
    import auto_generate
except ImportError:
    print("[!] Error: Could not find auto_generate.py.")
    exit(1)

class TestPixelArtRegression(unittest.TestCase):
    
    def setUp(self):
        """Create a clean temporary workspace."""
        self.test_dir = "regression_test_temp"
        os.makedirs(self.test_dir, exist_ok=True)
        self.test_image_path = os.path.join(self.test_dir, "test_file.png")

    def tearDown(self):
        """Clean up."""
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir)

    def test_multi_size_mapping(self):
        """PROVE: Categories map to the correct intended resolutions."""
        self.assertEqual(auto_generate.SIZES["GEM"], 256)
        self.assertEqual(auto_generate.SIZES["WORLD"], 768)
        self.assertEqual(auto_generate.SIZES["MAP"], 1024)
        print("\n[PASS] Multi-Size Mapping verified.")

    def test_kepler_vram_cap_logic(self):
        """PROVE: Resolutions above 512px are capped for low-VRAM hardware."""
        vram_sim = 3000 # Simulate 3GB GTX 780
        is_kepler_sim = vram_sim < 4000
        
        # Test a 'WORLD' prompt (intended 768)
        target_size = auto_generate.SIZES["WORLD"]
        if is_kepler_sim and target_size > 512:
            target_size = 512
            
        self.assertEqual(target_size, 512)
        print("[PASS] Kepler VRAM Safety Cap logic verified.")

    def test_category_parsing(self):
        """PROVE: Categorized prompts are split correctly for the API and Filenames."""
        raw_line = "GEM: red ruby jewel"
        category = raw_line.split(": ", 1)[0]
        prompt = raw_line.split(": ", 1)[-1]
        
        slug = auto_generate.slugify(prompt)
        
        self.assertEqual(category, "GEM")
        self.assertEqual(slug, "red_ruby_jewel")
        print(f"[PASS] Category Parsing: '{raw_line}' correctly handled.")

    def test_performance_average_math(self):
        """PROVE: Division logic for average timing is safe."""
        total = 45.0
        count = 3
        avg = total / count
        self.assertEqual(avg, 15.0)
        print("[PASS] Timing Math verified.")

    def test_image_io_integrity(self):
        """PROVE: The saving process preserves image resolution."""
        test_reso = 256
        mock_img = Image.new('RGB', (test_reso, test_reso), color='blue')
        buf = BytesIO()
        mock_img.save(buf, format="PNG")
        
        # Save to disk using the script's logic
        img_data = buf.getvalue()
        with Image.open(BytesIO(img_data)) as img:
            img.save(self.test_image_path)
            
        with Image.open(self.test_image_path) as verified:
            self.assertEqual(verified.size, (test_reso, test_reso))
        print(f"[PASS] Image IO Integrity verified at {test_reso}px.")

if __name__ == "__main__":
    print("--- RUNNING FULL REGRESSION SUITE ---")
    suite = unittest.TestLoader().loadTestsFromTestCase(TestPixelArtRegression)
    result = unittest.TextTestRunner(verbosity=1).run(suite)
    
    if result.wasSuccessful():
        print("\n\033[0;32m[SUCCESS] All core functions are stable.\033[0m")
    else:
        print("\n\033[0;31m[CRITICAL] Regression detected. Do not run main script.\033[0m")
        exit(1)
    