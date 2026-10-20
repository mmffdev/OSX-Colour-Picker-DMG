"""Independent 8-bit LittleCMS check via Pillow; no app build or profile writes.

Usage: python3 tools/diagnose_bpc_reference.py /absolute/path/to/CMYK.icc
Pillow is optional diagnostic tooling, not an application dependency.
"""
import sys
from PIL import Image, ImageCms

target = ImageCms.getOpenProfile(sys.argv[1])
source = ImageCms.createProfile("sRGB")
readback = ImageCms.buildTransform(
    target, ImageCms.createProfile("LAB"), "CMYK", "LAB", renderingIntent=1
)


def lab(image):
    lightness, a, b = ImageCms.applyTransform(image, readback).getpixel((0, 0))
    return round(lightness * 100 / 255, 3), a - 128, b - 128


print("LittleCMS:", ImageCms.core.littlecms_version, "Profile:", sys.argv[1])
for bpc in (False, True):
    forward = ImageCms.buildTransform(
        source, target, "RGB", "CMYK", renderingIntent=1,
        flags=ImageCms.Flags.BLACKPOINTCOMPENSATION if bpc else 0,
    )
    for value in (0, 51, 128, 255):
        inks = ImageCms.applyTransform(Image.new("RGB", (1, 1), (value,) * 3), forward)
        print("BPC", bpc, "RGB", value, "CMYK", inks.getpixel((0, 0)), "Lab", lab(inks))
