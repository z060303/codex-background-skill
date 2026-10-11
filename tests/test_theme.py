import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('create_theme', ROOT / 'skills/codex-background/scripts/create_theme.py')
theme = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(theme)


class ThemeTests(unittest.TestCase):
    def test_all_palettes_create_decodable_local_theme(self):
        with tempfile.TemporaryDirectory() as temp:
            for preset in theme.PRESETS:
                output = theme.build_theme(Path(temp)/preset, 'test-'+preset, '测试 Theme', preset)
                manifest = json.loads((output/'theme.json').read_text(encoding='utf-8'))
                with Image.open(output/manifest['image']) as image:
                    self.assertEqual(image.format, 'PNG')
                    self.assertGreater(image.width, 100)
                self.assertNotIn('__SURFACE', (output/'codeface.css').read_text())
                self.assertEqual(manifest['name'], '测试 Theme')

    def test_transparent_local_image_normalized_and_bounded(self):
        with tempfile.TemporaryDirectory() as temp:
            picture = Path(temp)/'source.png'
            Image.new('RGBA', (4200, 20), (0,0,0,0)).save(picture)
            out = theme.build_theme(Path(temp)/'out', 'custom', 'Custom', image_path=picture)
            with Image.open(out/'background.png') as result:
                self.assertEqual(result.mode, 'RGB')
                self.assertEqual(result.width, 3840)
                self.assertEqual(result.getpixel((0,0)), theme.rgb(theme.PRESETS['warm']['background']))

    def test_failure_does_not_overwrite_existing_theme(self):
        with tempfile.TemporaryDirectory() as temp:
            marker = Path(temp)/'existing.txt'
            marker.write_text('keep')
            with self.assertRaises(ValueError): theme.build_theme(temp, 'test', 'Test')
            self.assertEqual(marker.read_text(), 'keep')

    def test_invalid_id_and_unreadable_opacity_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            for bad in ['../escape', 'white space', 'UPPER', 'x'*65]:
                with self.assertRaises(ValueError): theme.build_theme(temp, bad, 'Test')
            with self.assertRaises(ValueError): theme.build_theme(temp, 'test', 'Test', surface_opacity=0.2)


if __name__ == '__main__': unittest.main()
