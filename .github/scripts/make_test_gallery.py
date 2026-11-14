#!/usr/bin/env python3
"""Genera una galeria de prueba para la autoprueba de CI.

Escribe imagenes sinteticas en ``cuadros/`` (sala principal y colecciones) que
cubren los casos del proyecto: medidas en el nombre, panoramica, obra alta,
medidas invertidas, EXIF girado, PNG con alfa y original grande para el detalle
con zoom. Nada de esto se versiona: ``cuadros/`` esta ignorada salvo
``.gdignore`` y ``README.md``.

Uso: ``python3 .github/scripts/make_test_gallery.py``
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "cuadros"

# Orientacion EXIF que pide girar la imagen 90 grados en sentido horario.
EXIF_ROTATE_CW = 6


def _lerp(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def _gradient(w: int, h: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    img = Image.new("RGB", (w, h))
    draw = ImageDraw.Draw(img)
    for y in range(h):
        draw.line([(0, y), (w - 1, y)], fill=_lerp(top, bottom, y / max(1, h - 1)))
    return img


def _picture(w: int, h: int, top: tuple[int, int, int], bottom: tuple[int, int, int], label: str) -> Image.Image:
    """Imagen con degradado, figuras y una etiqueta para distinguirla a simple vista."""
    img = _gradient(w, h, top, bottom)
    draw = ImageDraw.Draw(img)
    margin = max(4, w // 20)
    draw.ellipse([margin, margin, w - margin, min(h, w) - margin], outline=(255, 255, 255), width=max(2, w // 200))
    draw.rectangle([margin, h // 2, w - margin, h - margin], outline=(0, 0, 0), width=max(2, w // 250))
    draw.text((margin + 4, margin + 4), label, fill=(255, 255, 255))
    return img


def _save(img: Image.Image, path: Path, **kwargs) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, **kwargs)
    print(f"  {path.relative_to(ROOT)}  {img.width}x{img.height}")


def main() -> int:
    if not OUT.is_dir():
        print(f"No existe la carpeta {OUT}", file=sys.stderr)
        return 1

    room = [
        # nombre, ancho px, alto px, medidas declaradas en cm, color superior, color inferior
        ("paisaje__80x60.jpg", 800, 600, "80x60", (32, 64, 120), (210, 190, 140)),
        ("panoramica__200x100.jpg", 2000, 1000, "200x100", (20, 20, 30), (90, 140, 190)),
        ("torre__60x180.jpg", 600, 1800, "60x180", (60, 20, 40), (220, 160, 90)),
        ("sin_medidas.jpg", 900, 1200, None, (40, 80, 60), (200, 220, 180)),
    ]
    for name, w, h, _dims, top, bottom in room:
        _save(_picture(w, h, top, bottom, name.split("__")[0]), OUT / name, quality=85)

    # Medidas declaradas al reves: la imagen es horizontal 80x60 pero el nombre dice 60x80.
    _save(_picture(800, 600, (120, 40, 30), (240, 200, 120), "invertido"), OUT / "medidas_invertidas__60x80.jpg", quality=85)

    # Foto "guardada girada" con EXIF: 1200x600 almacenados, se ve 600x1200 (60x120 cm).
    exif_img = _picture(1200, 600, (30, 90, 110), (180, 230, 230), "exif6")
    exif = Image.Exif()
    exif[274] = EXIF_ROTATE_CW
    _save(exif_img, OUT / "exif6__60x120.jpg", quality=85, exif=exif)

    # PNG con transparencia real: el fondo debe dejar ver la pared.
    alpha = Image.new("RGBA", (800, 600), (0, 0, 0, 0))
    draw = ImageDraw.Draw(alpha)
    draw.ellipse([120, 60, 680, 540], fill=(220, 70, 55, 255))
    draw.rectangle([60, 240, 740, 420], fill=(40, 90, 200, 120))
    draw.text((130, 80), "alfa", fill=(255, 255, 255, 255))
    _save(alpha, OUT / "alfa__80x60.png")

    # Original de 3000 px: dispara la carga de detalle con zoom (MAX_TEX_SIZE = 2048).
    _save(_picture(3000, 2000, (70, 50, 10), (250, 220, 120), "detalle"), OUT / "detalle__150x100.jpg", quality=82)

    # Colecciones: dos pasillos completos y uno de una sola obra.
    collections = {
        "Impresionismo": [
            ("amanecer__70x50.jpg", 700, 500, (250, 180, 90), (60, 90, 160)),
            ("nenufares__120x80.jpg", 1200, 800, (60, 120, 80), (200, 230, 170)),
            ("estacion__90x110.jpg", 900, 1100, (40, 40, 60), (190, 150, 120)),
        ],
        "Retratos": [
            ("retrato_1__45x63.jpg", 450, 630, (80, 40, 30), (220, 180, 150)),
            ("retrato_2__45x63.jpg", 450, 630, (30, 50, 80), (170, 190, 220)),
        ],
        "Paisajes": [
            ("valle__140x90.jpg", 1400, 900, (20, 60, 20), (170, 220, 150)),
        ],
    }
    for collection, works in collections.items():
        for name, w, h, top, bottom in works:
            _save(_picture(w, h, top, bottom, name.split("__")[0]), OUT / "coleccion" / collection / name, quality=85)

    # Imagen suelta dentro de "coleccion/": el proyecto debe ignorarla.
    _save(_picture(400, 300, (10, 10, 10), (120, 120, 120), "suelta"), OUT / "coleccion" / "suelta.jpg", quality=85)

    # Coleccion vacia: el proyecto la omite con una advertencia.
    (OUT / "coleccion" / "Vacia").mkdir(parents=True, exist_ok=True)

    total = sum(1 for p in OUT.rglob("*") if p.is_file() and p.suffix.lower() != ".md" and p.name != ".gdignore")
    print(f"Galeria de prueba lista: {total} archivos en {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
