# Colour targets — implementation notes

The header's Colour Target is the workspace's single target control; it governs shown colours and value captions. The duplicate Values control has been removed. Palette review actions remain in the actionbar. Filters are borderless; narrow rails use two rows, wide actionbars one, and Clear appears only for non-default filters. Heading, actionbar and tile blocks share the same page inset.

## Conditions and encoding context

- Print conditions come only from ColorSync's installed profile registry. CMYK and output-class grey ICCs remain local. Missing FOGRA39/51/52, GRACoL/SWOP 2013, Japan Color 2011 and newspaper conditions link to publishers. Generic CMYK is not offered as a real press. The existing CoreGraphics ICC engine remains in use; the planned LittleCMS replacement is unchanged.
- K-only searches the selected CMYK ICC's black-ink axis with CMY fixed at zero; the result reports its actual colour difference. It is a constrained separation, not a new ICC condition. Paper White uses the existing absolute-colorimetric path, including its existing engine limitations.
- Rec. 2100 PQ uses 203 cd/m² reference white and absolute ST 2084 values, up to 10,000 cd/m². HLG uses the BT.2100 OOTF at a 1,000 cd/m², gamma-1.2 reference display, with 203 cd/m² diffuse white. These are explicit reference contexts, not monitor measurements. Current AppKit preview remains SDR. HDR differences use BT.2124 ΔE ITP; other targets retain ΔE00.
- ACES2065-1 uses AP0/D60; ACEScct uses AP1 with the Academy log/toe. Both preserve scene values. Linear Rec. 2020 and Linear P3-D65 reuse the existing primary matrices without display transfer curves.
- DCP XYZ uses the DCI white adaptation, 48 cd/m² reference white, 52.37 scaling, gamma 2.6 and 12-bit codes. This is a value target, not a DCP encoder or cinema display calibration.
- eciRGB v2 uses D50/ECI primaries and L* encoding. Grey Gamma 2.2 reports one neutral D50 luminance value. These mathematical encodings do not bundle ICC files.
- Optional Rec. 601 has not been added: its 525/625-line variants require an explicit delivery choice.

## Sources and checks

- [Apple ColorSync profiles](https://developer.apple.com/documentation/colorsync/color-profiles)
- [ITU-R BT.2100](https://www.itu.int/rec/R-REC-BT.2100), [BT.2408 reference context](https://www.itu.int/dms_pub/itu-r/opb/rep/R-REP-BT.2408-8-2024-PDF-E.pdf), [BT.2124](https://www.itu.int/rec/R-REC-BT.2124)
- [Academy ACES2065-1](https://docs.acescentral.com/encodings/aces2065-1/), [ACEScct](https://docs.acescentral.com/encodings/acescct/)
- [SMPTE EG 432-1](https://pub.smpte.org/doc/eg432-1/20101110-pub/eg0432-1-2010.pdf)
- [ECI working spaces](https://eci.org/doku.php_id%3Dde_colourstandards_workingcolorspaces.html)

`ColourTargetTests` checks published PQ/ACES code points, AP0 primaries, eciRGB L*, DCP white code, HDR highlight/peak behaviour, inverse transforms, metric identity/symmetry, old channel decoding, profile aliases, absent ICCs and K-only output. No external standard press ICC is claimed present or validated when it is not installed.
