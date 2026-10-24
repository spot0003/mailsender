"""Deterministically package the original QuickDrop artwork into native icon slots."""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'branding/quickdrop-icon.png'

def main():
    image = Image.open(SOURCE).convert('RGBA')
    paths = list((ROOT/'app/assets/img').glob('logo-*.png'))
    paths += list((ROOT/'app/android/app/src/main/res').glob('mipmap-*/*.png'))
    paths += list((ROOT/'app/ios/Runner/Assets.xcassets/AppIcon.appiconset').glob('*.png'))
    paths += list((ROOT/'app/macos/Runner/Assets.xcassets/AppIcon.appiconset').glob('*.png'))
    paths += list((ROOT/'app/ios/Runner/Assets.xcassets/LaunchImage.imageset').glob('*.png'))
    paths += [ROOT/'app/android/app/src/main/ic_launcher-playstore.png']
    for path in paths:
        if not path.exists():
            continue
        with Image.open(path) as old:
            size = old.size
        output = image.resize(size, Image.Resampling.LANCZOS)
        # White/black and Android monochrome slots need an alpha mask, not a solid tile.
        if any(s in path.name for s in ('monochrome', 'quicktile', 'white', 'black')):
            mask = image.convert('L').point(lambda p: 255 if p > 220 else 0).resize(size, Image.Resampling.LANCZOS)
            output = Image.new('RGBA', size, 'black' if 'black' in path.name else 'white')
            output.putalpha(mask)
        output.save(path)
    for path in (ROOT/'app').rglob('*.ico'):
        image.save(path, format='ICO', sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)])
    print(f'Updated {len(paths)} PNG slots and Windows ICO resources')

if __name__ == '__main__':
    main()
