#!/usr/bin/env python3
"""Generate a local CodeFace theme. Does not modify or launch Codex."""
import argparse
import io
import json
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageOps

PRESETS = {
    'warm': {'background':'#F5E8D7','panel':'#FFF9EF','panelAlt':'#F3E2CA','accent':'#81572A','text':'#302A24','muted':'#655749','line':'#CBB89D'},
    'forest': {'background':'#DDEBE3','panel':'#F3FAF6','panelAlt':'#DBEAE0','accent':'#236249','text':'#18362B','muted':'#426354','line':'#AAC9B7'},
    'night': {'background':'#131C30','panel':'#172338','panelAlt':'#22324C','accent':'#9CC9FF','text':'#EEF4FF','muted':'#B6C5D9','line':'#455C7A'},
}


def rgb(color):
    return tuple(int(color[i:i+2], 16) for i in (1, 3, 5))


def gradient(palette):
    """Original procedural artwork, no copied image assets."""
    width, height = 1600, 1000
    a, b = rgb(palette['background']), rgb(palette['panelAlt'])
    image = Image.new('RGB', (width, height))
    draw = ImageDraw.Draw(image)
    for y in range(height):
        mix = y / (height - 1)
        draw.line((0, y, width, y), fill=tuple(round(x*(1-mix)+z*mix) for x,z in zip(a,b)))
    glow = Image.new('RGBA', image.size)
    g = ImageDraw.Draw(glow)
    g.ellipse((1040, -210, 1940, 640), fill=rgb(palette['accent'])+(80,))
    g.ellipse((-480, 600, 440, 1460), fill=rgb(palette['accent'])+(65,))
    return Image.alpha_composite(image.convert('RGBA'), glow.filter(ImageFilter.GaussianBlur(140))).convert('RGB')


def build_theme(output, theme_id, name, preset='warm', image_path=None, surface_opacity=0.9):
    if not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', theme_id) or len(theme_id) > 64:
        raise ValueError('Theme ID must be lowercase kebab-case, at most 64 characters.')
    if not name.strip() or not 0.65 <= surface_opacity <= 1:
        raise ValueError('Provide a name and a surface opacity between 0.65 and 1.')
    output = Path(output)
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise ValueError('Output must be a new or empty directory; existing themes are preserved.')
    colors = dict(PRESETS[preset])
    if image_path:
        source = Path(image_path)
        if source.stat().st_size > 16 * 1024 * 1024:
            raise ValueError('Source image exceeds 16 MiB.')
        with Image.open(source) as opened:
            image = ImageOps.exif_transpose(opened).convert('RGBA')
            base = Image.new('RGBA', image.size, colors['background'])
            image = Image.alpha_composite(base, image).convert('RGB')
    else:
        image = gradient(colors)
    image.thumbnail((3840, 3840), Image.Resampling.LANCZOS)
    buf = io.BytesIO()
    image.save(buf, 'PNG', optimize=True)
    if buf.tell() > 16 * 1024 * 1024:
        raise ValueError('Normalized image exceeds 16 MiB; choose a smaller input.')
    theme = {
        'schemaVersion': 2, 'id': theme_id, 'name': name, 'image': 'background.png',
        'layout': {'heroFit':'none', 'backgroundPosition':'center center', 'taskOverlay':0.35},
        'typography': {'fontFamily':'system-ui, -apple-system, sans-serif', 'fontSize':14, 'lineHeight':1.6},
        'chrome': {'brand':False, 'status':False, 'quote':False, 'particles':False, 'orbit':False},
        'effects': {'blur':12, 'saturation':1, 'motionScale':0},
        'colors': colors,
    }
    panel = ', '.join(str(v) for v in rgb(colors['panel']))
    css = (Path(__file__).parent.parent / 'assets' / 'readable.css').read_text(encoding='utf-8')
    css = css.replace('__PANEL_RGB__', panel).replace('__SURFACE_OPACITY__', f'{surface_opacity:.2f}')
    css = css.replace('__COLOR_SCHEME__', 'dark' if preset == 'night' else 'light')
    output.mkdir(parents=True, exist_ok=True)
    (output / 'background.png').write_bytes(buf.getvalue())
    (output / 'theme.json').write_text(json.dumps(theme, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    (output / 'codeface.css').write_text(css, encoding='utf-8')
    return output.resolve()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--id', required=True)
    p.add_argument('--name', required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--image', type=Path)
    p.add_argument('--preset', choices=PRESETS, default='warm')
    p.add_argument('--surface-opacity', type=float, default=0.9)
    args = p.parse_args()
    try:
        result = build_theme(args.output, args.id, args.name, args.preset, args.image, args.surface_opacity)
    except (ValueError, OSError, Image.DecompressionBombError) as error:
        p.error(str(error))
    print(json.dumps({'theme_directory':str(result), 'applied':False}, ensure_ascii=False))


if __name__ == '__main__':
    main()
