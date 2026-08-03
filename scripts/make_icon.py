#!/usr/bin/env python3
"""Gera o AppIcon do Tomafoco.

Mantém a estrutura original do ícone (squircle navy com gradiente vertical,
anel de progresso cyan sobre trilha branca translúcida) e desenha no centro
um tomate branco com brilho no lugar do antigo símbolo DDS.

O fundo/anel NÃO são redesenhados: são preservados do PNG existente. Só o
miolo do anel é repintado com o gradiente do próprio arquivo (amostrado
linha a linha) antes de compor o tomate.

Uso:
    python3 scripts/make_icon.py [--dry-run]

Requer Pillow.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ICONSET = (
    Path(__file__).resolve().parent.parent
    / "App/Resources/Assets.xcassets/AppIcon.appiconset"
)

SIZES = (16, 32, 64, 128, 256, 512, 1024)

# Geometria medida no ícone original de 1024px, em fração do lado.
RING_RADIUS = 309 / 1024.0
RING_WIDTH = 25 / 1024.0
SAMPLE_X = 160 / 1024.0  # coluna de fundo limpa (dentro do corpo, fora do anel)

# Tomate: raio horizontal do corpo e deslocamento do centro, em fração do lado.
TOMATO_SCALE = 205 / 1024.0
TOMATO_ASPECT = 1.0
TOMATO_OFFSET_Y = 50 / 1024.0

BODY_EXPONENT = 2.15  # > 2 achata os polos e cria o ombro do tomate
BODY_FLATTEN = 0.84  # altura do corpo em relação à largura
# Coroa e corpo são da mesma cor, então a coroa é desenhada quase toda ACIMA
# da silhueta do corpo — o recorte contra o navy é o que a torna legível.
CALYX_BASE = (0.0, -0.72)  # de onde saem cabinho e sépalas
CALYX_SEPALS = ((38, 0.70, 0.19), (82, 0.70, 0.16))  # (ângulo°, comprimento, meia-largura)

# Tomate branco: gradiente de branco puro para um cinza levemente azulado, para
# o volume aparecer sem virar cinza chapado.
BODY_TOP = (0xFF, 0xFF, 0xFF)
BODY_BOTTOM = (0xAF, 0xBD, 0xD2)
RIM_COLOR = (0xFF, 0xFF, 0xFF)
RIM_ALPHA = 0  # corpo claro já se separa do navy; contorno só sujaria a borda
HIGHLIGHT_ALPHA = 235

SS = 4  # supersampling do desenho do tomate


def cubic(p0, c1, c2, p3, steps=80):
    """Amostra uma bézier cúbica (exclui o ponto inicial)."""
    pts = []
    for i in range(1, steps + 1):
        t = i / steps
        u = 1 - t
        x = u * u * u * p0[0] + 3 * u * u * t * c1[0] + 3 * u * t * t * c2[0] + t * t * t * p3[0]
        y = u * u * u * p0[1] + 3 * u * u * t * c1[1] + 3 * u * t * t * c2[1] + t * t * t * p3[1]
        pts.append((x, y))
    return pts


def mirror(pts):
    return [(-x, y) for (x, y) in pts]


def tomato_body(steps=360):
    """Silhueta do tomate: superelipse achatada nos polos, mais larga que alta.

    Unidades normalizadas: x em [-1, 1], y para baixo em [-BODY_FLATTEN, ...].
    Expoente > 2 é o que dá o "ombro" do tomate — uma elipse pura viraria bola.
    """
    e = 2.0 / BODY_EXPONENT
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        cos_t, sin_t = math.cos(t), math.sin(t)
        x = math.copysign(abs(cos_t) ** e, cos_t)
        y = math.copysign(abs(sin_t) ** e, sin_t) * BODY_FLATTEN
        pts.append((x, y))
    return pts


def sepal(angle_deg, length, width, base=CALYX_BASE):
    """Uma sépala da coroa: folha pontuda saindo da base do cabinho."""
    a = math.radians(angle_deg)
    dx, dy = math.sin(a), -math.cos(a)  # 0° aponta para cima
    px, py = -dy, dx  # perpendicular
    bx, by = base
    tip = (bx + dx * length, by + dy * length)
    b1 = (bx + px * width, by + py * width)
    b2 = (bx - px * width, by - py * width)
    bulge = 1.15
    c1 = (bx + dx * length * 0.55 + px * width * bulge, by + dy * length * 0.55 + py * width * bulge)
    c2 = (bx + dx * length * 0.55 - px * width * bulge, by + dy * length * 0.55 - py * width * bulge)
    return [b1] + cubic(b1, c1, c1, tip) + cubic(tip, c2, c2, b2)


def tomato_stem():
    """Cabinho curto e reto no topo."""
    bx, by = CALYX_BASE
    top = by - 0.60
    return [(bx - 0.10, by), (bx - 0.055, top), (bx + 0.055, top), (bx + 0.10, by)]


def tomato_calyx():
    """Coroa: cabinho + sépalas simétricas abertas para cima."""
    shapes = [tomato_stem()]
    for angle, length, width in CALYX_SEPALS:
        shapes.append(sepal(angle, length, width))
        shapes.append(sepal(-angle, length, width))
    return shapes


def to_pixels(pts, side, ss):
    """Converte unidades normalizadas para pixels do canvas supersampleado."""
    sx = TOMATO_SCALE * TOMATO_ASPECT * side * ss
    sy = TOMATO_SCALE * side * ss
    cx = 0.5 * side * ss
    cy = (0.5 + TOMATO_OFFSET_Y) * side * ss
    return [(cx + x * sx, cy + y * sy) for (x, y) in pts]


def build_mask(side):
    """Máscara (modo L) do tomate inteiro, no canvas supersampleado."""
    n = side * SS
    mask = Image.new("L", (n, n), 0)
    draw = ImageDraw.Draw(mask)
    for shape in [tomato_body()] + tomato_calyx():
        draw.polygon(to_pixels(shape, side, SS), fill=255)
    return mask


def vertical_gradient(size, top, bottom):
    grad = Image.new("RGB", (1, size), top)
    px = grad.load()
    for y in range(size):
        t = y / max(1, size - 1)
        px[0, y] = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    return grad.resize((size, size), Image.NEAREST)


def render_tomato(side):
    """Camada RGBA do tomate, já reduzida para `side` pixels."""
    n = side * SS
    mask = build_mask(side)

    layer = vertical_gradient(n, BODY_TOP, BODY_BOTTOM).convert("RGBA")
    layer.putalpha(mask)

    # Contorno opcional (usado quando o corpo é escuro e some no navy).
    if RIM_ALPHA:
        erosion = max(3, int(round(n * 0.0045)) | 1)
        inner = mask.filter(ImageFilter.MinFilter(erosion))
        rim = Image.new("L", (n, n))
        rim.paste(mask, (0, 0))
        rim = Image.composite(Image.new("L", (n, n), 0), rim, inner)
        rim = rim.point(lambda v: v * RIM_ALPHA // 255)
        layer.paste(Image.new("RGBA", (n, n), RIM_COLOR + (255,)), (0, 0), rim)

    # Brilho especular no ombro esquerdo (difuso) + glint pequeno em cima dele.
    gloss = Image.new("L", (n, n), 0)
    g = ImageDraw.Draw(gloss)
    box = to_pixels([(-0.78, -0.66), (0.02, 0.20)], side, SS)
    g.ellipse([box[0], box[1]], fill=255)
    gloss = gloss.filter(ImageFilter.GaussianBlur(n * 0.032))
    gloss = Image.composite(gloss, Image.new("L", (n, n), 0), mask)
    gloss = gloss.point(lambda v: v * HIGHLIGHT_ALPHA // 255)
    layer.paste(Image.new("RGBA", (n, n), (255, 255, 255, 255)), (0, 0), gloss)

    glint = Image.new("L", (n, n), 0)
    gg = ImageDraw.Draw(glint)
    spot = to_pixels([(-0.60, -0.50), (-0.26, -0.20)], side, SS)
    gg.ellipse([spot[0], spot[1]], fill=255)
    glint = glint.filter(ImageFilter.GaussianBlur(n * 0.012))
    glint = Image.composite(glint, Image.new("L", (n, n), 0), mask)
    layer.paste(Image.new("RGBA", (n, n), (255, 255, 255, 255)), (0, 0), glint)

    return layer.resize((side, side), Image.LANCZOS)


def clear_ring_interior(img):
    """Apaga o símbolo antigo repintando o miolo do anel com o gradiente do fundo."""
    side = img.size[0]
    px = img.load()
    cx = cy = (side - 1) / 2.0
    inner = (RING_RADIUS - RING_WIDTH * 0.75) * side
    sample_x = min(side - 1, max(0, int(round(SAMPLE_X * side))))

    y0 = max(0, int(cy - inner) - 1)
    y1 = min(side - 1, int(cy + inner) + 1)
    for y in range(y0, y1 + 1):
        base = px[sample_x, y]
        dy = y - cy
        span = inner * inner - dy * dy
        if span <= 0:
            continue
        half = span**0.5
        for x in range(int(cx - half) + 1, int(cx + half)):
            px[x, y] = base
    return img


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="não grava os PNGs")
    parser.add_argument("--out", type=Path, default=ICONSET)
    args = parser.parse_args()

    for side in SIZES:
        src = ICONSET / f"icon_{side}.png"
        img = Image.open(src).convert("RGBA")
        if img.size != (side, side):
            print(f"aviso: {src.name} tem {img.size}, esperado {side}x{side}")
        base = clear_ring_interior(img)
        base.alpha_composite(render_tomato(side))
        if not args.dry_run:
            base.save(args.out / f"icon_{side}.png")
        print(f"{'(dry) ' if args.dry_run else ''}icon_{side}.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())
