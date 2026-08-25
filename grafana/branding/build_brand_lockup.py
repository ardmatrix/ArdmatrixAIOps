from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "ardmatrix-aiops-transparent-final.png"
HEADER_OUTPUT = ROOT / "ardmatrix-header-logo.png"
FAVICON_OUTPUT = ROOT / "ardmatrix-favicon.png"
APPLE_ICON_OUTPUT = ROOT / "ardmatrix-apple-touch-icon.png"

source = Image.open(SOURCE).convert("RGBA")
bounds = source.getchannel("A").getbbox()
if bounds is None:
    raise RuntimeError("Official ARDMATRIX logo has no visible pixels")

logo = source.crop(bounds)
logo.save(HEADER_OUTPUT, optimize=True)
icon_source = source.crop((bounds[0], bounds[1], 500, bounds[3]))


def make_square_icon(size: int, output: Path) -> None:
    icon = icon_source.copy()
    icon.thumbnail((size - 4, size - 4), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(icon, ((size - icon.width) // 2, (size - icon.height) // 2))
    canvas.save(output, optimize=True)


make_square_icon(64, FAVICON_OUTPUT)
make_square_icon(180, APPLE_ICON_OUTPUT)
print(f"Created {HEADER_OUTPUT} ({logo.width}x{logo.height})")
print(f"Created {FAVICON_OUTPUT} and {APPLE_ICON_OUTPUT}")
