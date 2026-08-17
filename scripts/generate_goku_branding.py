#!/usr/bin/env python3
"""Generate original Goku branding assets for the Hermex fork.

The artwork intentionally avoids Dragon Ball characters, insignia, and trade dress.
It uses an original energy-orbit "G" mark and preserves the source asset catalog's
existing filenames so no Xcode project churn is required.
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "HermesMobile" / "Resources" / "Assets.xcassets"
FONT = "/System/Library/Fonts/SFNSRounded.ttf"


def gradient(size: tuple[int, int], top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    width, height = size
    image = Image.new("RGB", size)
    draw = ImageDraw.Draw(image)
    for y in range(height):
        t = y / max(height - 1, 1)
        color = tuple(round(a + (b - a) * t) for a, b in zip(top, bottom))
        draw.line((0, y, width, y), fill=color)
    return image


def rounded_font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT, size=size)


def centered_text_mask(text: str, size: tuple[int, int], font_size: int, y_offset: int = 0) -> Image.Image:
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    font = rounded_font(font_size)
    bounds = draw.textbbox((0, 0), text, font=font, stroke_width=0)
    text_width = bounds[2] - bounds[0]
    text_height = bounds[3] - bounds[1]
    x = (size[0] - text_width) / 2 - bounds[0]
    y = (size[1] - text_height) / 2 - bounds[1] + y_offset
    draw.text((x, y), text, fill=255, font=font)
    return mask


def radial_glow(size: tuple[int, int], center: tuple[float, float], radius: float, color: tuple[int, int, int, int]) -> Image.Image:
    width, height = size
    alpha = Image.new("L", size, 0)
    pixels = alpha.load()
    for y in range(height):
        for x in range(width):
            distance = math.hypot(x - center[0], y - center[1])
            value = max(0.0, 1.0 - distance / radius)
            pixels[x, y] = round(color[3] * value * value)
    layer = Image.new("RGBA", size, color[:3] + (0,))
    layer.putalpha(alpha)
    return layer


def make_icon(
    top: tuple[int, int, int],
    bottom: tuple[int, int, int],
    ring: tuple[int, int, int],
    glyph: tuple[int, int, int],
    accent: tuple[int, int, int],
    *,
    monochrome: bool = False,
) -> Image.Image:
    size = (1024, 1024)
    base = gradient(size, top, bottom).convert("RGBA")
    if not monochrome:
        base = Image.alpha_composite(base, radial_glow(size, (720, 280), 620, accent + (118,)))
        base = Image.alpha_composite(base, radial_glow(size, (285, 780), 520, ring + (84,)))

    draw = ImageDraw.Draw(base)
    center = (512, 512)
    ring_box = (198, 198, 826, 826)
    shadow = Image.new("RGBA", size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.ellipse((ring_box[0] + 18, ring_box[1] + 25, ring_box[2] + 18, ring_box[3] + 25), outline=(0, 0, 0, 95), width=52)
    shadow = shadow.filter(ImageFilter.GaussianBlur(14))
    base = Image.alpha_composite(base, shadow)
    draw = ImageDraw.Draw(base)
    draw.ellipse(ring_box, outline=ring + (255,), width=44)
    draw.arc((142, 142, 882, 882), start=202, end=328, fill=accent + (240,), width=24)
    draw.arc((242, 242, 782, 782), start=22, end=138, fill=accent + (220,), width=18)

    for angle, distance, radius in ((18, 392, 12), (151, 390, 9), (229, 376, 14), (317, 404, 8)):
        radians = math.radians(angle)
        x = center[0] + math.cos(radians) * distance
        y = center[1] + math.sin(radians) * distance
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=accent + (245,))

    glyph_mask = centered_text_mask("G", size, 500, y_offset=-18)
    glyph_shadow = Image.new("RGBA", size, (0, 0, 0, 0))
    shifted = ImageChops.offset(glyph_mask, 12, 20).filter(ImageFilter.GaussianBlur(16))
    glyph_shadow.putalpha(shifted.point(lambda value: round(value * 0.52)))
    base = Image.alpha_composite(base, glyph_shadow)
    glyph_layer = Image.new("RGBA", size, glyph + (255,))
    glyph_layer.putalpha(glyph_mask)
    base = Image.alpha_composite(base, glyph_layer)

    return base.convert("RGB")


def save_icon_variants() -> dict[str, Image.Image]:
    variants = {
        "light": make_icon((255, 247, 224), (255, 151, 32), (26, 42, 74), (13, 25, 48), (37, 99, 235)),
        "dark": make_icon((12, 22, 44), (2, 7, 20), (255, 151, 32), (248, 250, 255), (69, 137, 255)),
        "gradient_light": make_icon((246, 249, 255), (124, 178, 255), (22, 45, 82), (10, 22, 44), (255, 147, 30)),
        "gradient_dark": make_icon((29, 52, 99), (5, 11, 29), (255, 160, 40), (250, 252, 255), (79, 154, 255)),
        "disco": make_icon((51, 18, 93), (7, 4, 28), (255, 75, 179), (255, 255, 255), (36, 228, 255)),
        "mono_light": make_icon((250, 250, 250), (215, 215, 215), (28, 28, 28), (10, 10, 10), (80, 80, 80), monochrome=True),
        "mono_dark": make_icon((28, 28, 28), (0, 0, 0), (239, 239, 239), (255, 255, 255), (200, 200, 200), monochrome=True),
    }

    destinations = {
        "light": [
            "AppIcon.appiconset/hermes_mobile_light_icon.png",
            "AppIconLight.appiconset/hermes_mobile_light_icon.png",
            "AppIconLightPreview.imageset/hermes_mobile_light_icon.png",
        ],
        "dark": [
            "AppIcon.appiconset/hermes_mobile_dark_icon.png",
            "AppIconDark.appiconset/hermes_mobile_dark_icon.png",
            "AppIconDarkPreview.imageset/hermes_mobile_dark_icon.png",
            "HermesAppIcon.imageset/hermes_mobile_dark_icon.png",
        ],
        "gradient_light": [
            "AppIconGradientLight.appiconset/hermex_gradient_light_icon.png",
            "AppIconGradientLightPreview.imageset/hermex_gradient_light_icon.png",
        ],
        "gradient_dark": [
            "AppIconGradientDark.appiconset/hermex_gradient_dark_icon.png",
            "AppIconGradientDarkPreview.imageset/hermex_gradient_dark_icon.png",
        ],
        "disco": [
            "AppIconDisco.appiconset/hermes_mobile_dark_disco_icon.png",
            "AppIconDiscoPreview.imageset/hermes_mobile_dark_disco_icon.png",
        ],
        "mono_light": [
            "AppIconMonochromeLight.appiconset/hermex_monochrome_light_icon.png",
            "AppIconMonochromeLightPreview.imageset/hermex_monochrome_light_icon.png",
        ],
        "mono_dark": [
            "AppIconMonochromeDark.appiconset/hermex_monochrome_dark_icon.png",
            "AppIconMonochromeDarkPreview.imageset/hermex_monochrome_dark_icon.png",
        ],
    }

    for variant, relative_paths in destinations.items():
        for relative_path in relative_paths:
            variants[variant].save(ASSETS / relative_path, format="PNG", optimize=True)

    return variants


def save_wordmarks() -> None:
    banner_size = (1286, 202)
    word_mask = centered_text_mask("GOKU", banner_size, 184, y_offset=-7)
    banner = Image.new("RGBA", banner_size, (0, 0, 0, 0))
    shadow = Image.new("RGBA", banner_size, (0, 0, 0, 0))
    shadow_alpha = ImageChops.offset(word_mask, 8, 11).filter(ImageFilter.GaussianBlur(7))
    shadow.putalpha(shadow_alpha.point(lambda value: round(value * 0.72)))
    banner = Image.alpha_composite(banner, shadow)
    fill = gradient(banner_size, (255, 239, 92), (255, 132, 24)).convert("RGBA")
    fill.putalpha(word_mask)
    banner = Image.alpha_composite(banner, fill)
    outline = Image.new("RGBA", banner_size, (0, 0, 0, 0))
    outline_draw = ImageDraw.Draw(outline)
    font = rounded_font(184)
    bounds = outline_draw.textbbox((0, 0), "GOKU", font=font, stroke_width=0)
    x = (banner_size[0] - (bounds[2] - bounds[0])) / 2 - bounds[0]
    y = (banner_size[1] - (bounds[3] - bounds[1])) / 2 - bounds[1] - 7
    outline_draw.text((x, y), "GOKU", font=font, fill=(0, 0, 0, 0), stroke_width=4, stroke_fill=(12, 25, 52, 255))
    banner = Image.alpha_composite(banner, outline)
    banner.save(ASSETS / "HermesMobileBanner.imageset/hermes-mobile-banner.png", optimize=True)

    layer_size = (643, 185)
    mask = centered_text_mask("GOKU", layer_size, 168, y_offset=-5)

    fill_mask = Image.new("RGBA", layer_size, (255, 255, 255, 0))
    fill_mask.putalpha(mask)
    fill_mask.save(ASSETS / "hermes-fill-mask.imageset/hermes-fill-mask.png", optimize=True)

    shading = gradient(layer_size, (255, 255, 255), (82, 82, 82)).convert("RGBA")
    shading.putalpha(mask.point(lambda value: round(value * 0.42)))
    shading.save(ASSETS / "hermes-shading-overlay.imageset/hermes-shading-overlay.png", optimize=True)

    highlight_alpha = ImageChops.offset(mask, -2, -3).filter(ImageFilter.GaussianBlur(1))
    highlight = Image.new("RGBA", layer_size, (255, 255, 255, 0))
    highlight.putalpha(highlight_alpha.point(lambda value: round(value * 0.34)))
    highlight.save(ASSETS / "hermes-highlight.imageset/hermes-highlight.png", optimize=True)

    expanded = mask.filter(ImageFilter.MaxFilter(9))
    outline_alpha = ImageChops.subtract(expanded, mask)
    shadow_alpha = ImageChops.offset(outline_alpha, 3, 5).filter(ImageFilter.GaussianBlur(2))
    outline_shadow = Image.new("RGBA", layer_size, (9, 17, 33, 0))
    outline_shadow.putalpha(shadow_alpha.point(lambda value: round(value * 0.9)))
    outline_shadow.save(ASSETS / "hermes-outline-shadow.imageset/hermes-outline-shadow.png", optimize=True)


if __name__ == "__main__":
    save_icon_variants()
    save_wordmarks()
    print("Generated original Goku icon variants and wordmarks.")
