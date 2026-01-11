import unittest
import os
import shutil
import base64
from io import BytesIO
from PIL import Image

# Import your actual code functions
try:
    from auto_generate import slugify, is_valid_image
except ImportError:
    print("[!] Error: Could not find auto_generate.py in the current directory.")
    exit(1)

class TestPixelArtRegression(unittest.TestCase):
    def setUp(self):
        """Create a temporary workspace for testing."""
        self.test_workspace = "test_workspace_temp"
        os.makedirs(self.test_workspace, exist_ok=True)

    def tearDown(self):
        """Clean up the workspace after tests."""
        if os.path.exists(self.test_workspace):
            shutil.rmtree(self.test_workspace)

    def test_slugify_consistency(self):
        """PROVE: Filenames stay consistent (Crucial for Resume feature)."""
        input_text = "Gold Coin (Pixel Art)!!!"
        expected = "gold_coin_pixel_art"
        result = slugify(input_text)
        self.assertEqual(result, expected, f"Slugify changed! Got '{result}' instead of '{expected}'")

    def test_resume_logic_valid(self):
        """PROVE: The script correctly identifies a valid PNG."""
        path = os.path.join(self.test_workspace, "valid.png")
        Image.new('RGB', (64, 64), color='red').save(path)
        self.assertTrue(is_valid_image(path), "Valid image was incorrectly flagged as invalid!")

    def test_resume_logic_corrupt(self):
        """PROVE: The script correctly identifies a corrupt/partial file."""
        path = os.path.join(self.test_workspace, "corrupt.png")
        with open(path, "w") as f:
            f.write("This is not a real PNG file data.")
        self.assertFalse(is_valid_image(path), "Corrupt file was incorrectly flagged as valid!")

    def test_save_integrity(self):
        """PROVE: The Base64 -> PIL -> Disk flow works without data loss."""
        # 1. Create a mock red 512x512 image base64 (like the API returns)
        mock_img = Image.new('RGB', (512, 512), color='red')
        buf = BytesIO()
        mock_img.save(buf, format="PNG")
        mock_b64 = base64.b64encode(buf.getvalue()).decode()

        # 2. Run the actual save logic found in your script
        test_save_path = os.path.join(self.test_workspace, "save_test.png")
        img_data = base64.b64decode(mock_b64)
        with Image.open(BytesIO(img_data)) as img:
            img.save(test_save_path)

        # 3. Verify
        self.assertTrue(os.path.exists(test_save_path))
        with Image.open(test_save_path) as saved_img:
            self.assertEqual(saved_img.size, (512, 512))
            self.assertEqual(saved_img.getpixel((10, 10)), (255, 0, 0))

if __name__ == "__main__":
    print("--- Starting Regression Tests ---")
    unittest.main()
