#!/usr/bin/env python3
"""Reproduce the independent CIE 1 nm checks for Colorgain's ICC LWL preview.
Downloads primary-source CIE datasets, checks their published SHA-256, then
compares the committed reference fixture and original ICC tables. No app writes.
"""
import csv
import hashlib
import io
import json
import math
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1] / "ProofingResources/Spectral"
BASE = "https://files.cie.co.at/Publications-datasets/"
FILES = ["CIE_xyz_1931_2deg.csv", "CIE_xyz_1964_10deg.csv", "CIE_std_illum_D50.csv", "CIE_std_illum_D65.csv", "CIE_std_illum_A_1nm.csv"]

def fetch(name):
    return urlopen(Request(BASE + name, headers={"User-Agent": "Colorgain reference validation"}), timeout=30).read()

def dataset(name):
    raw = fetch(name)
    metadata = None
    for suffix in ["_metadata.json", "_metadata_v2.json"]:
        try:
            metadata = json.loads(fetch(name + suffix))
            break
        except Exception:
            pass
    assert metadata, "Missing CIE metadata: " + name
    expected = next(row["checksum"] for row in metadata["checksums"] if row["hashMethod"] == "sha256")
    assert hashlib.sha256(raw).hexdigest() == expected, "CIE checksum mismatch: " + name
    return {int(row[0]): [0 if value.lower() == "nan" else float(value) for value in row[1:]] for row in csv.reader(io.StringIO(raw.decode("utf-8-sig"))) if row}

def main():
    data = {name: dataset(name) for name in FILES}
    fixtures = json.loads((ROOT / "reference-values.json").read_text())
    hashes = json.loads((ROOT / "spectral-sha256.json").read_text())
    maximum = 0
    for ref in fixtures:
        matching = data[FILES[0 if ref["observer"] == "1931" else 1]]
        light = data[FILES[2 + ["D50", "D65", "A"].index(ref["illuminant"])]]
        end = ref["end"]
        def reflectance(wavelength):
            return 0.1 + 0.7 * math.exp(-((wavelength - 540) / 65) ** 2)
        denominator = sum(light[nm][0] * matching[nm][1] for nm in range(380, end + 1))
        xyz = [sum(reflectance(nm) * light[nm][0] * matching[nm][i] for nm in range(380, end + 1)) / denominator for i in range(3)]
        name = f'Wts-{ref["observer"]}-{ref["illuminant"]}-380-10-{end}nm.csv'
        raw = (ROOT / name).read_bytes()
        assert hashlib.sha256(raw).hexdigest() == hashes[name], "ICC table checksum mismatch"
        rows = [row for row in csv.reader(io.StringIO(raw.decode("utf-8-sig"))) if row]
        lwl = [sum(float(row[i + 1]) * reflectance(int(row[0])) / 100 for row in rows) for i in range(3)]
        assert max(abs(a - b) for a, b in zip(xyz, ref["referenceXYZ"])) < 1e-12
        assert max(abs(a - b) for a, b in zip(lwl, ref["iccXYZ"])) < 1e-12
        difference = max(abs(a - b) for a, b in zip(xyz, lwl))
        assert difference < ref["tolerance"]
        maximum = max(maximum, difference)
    print(f"{len(fixtures)} independent cases passed; maximum absolute XYZ difference {maximum:.8f} (Y white = 1).")

if __name__ == "__main__":
    main()
