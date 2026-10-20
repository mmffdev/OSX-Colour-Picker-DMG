# Colorgain Metadata for Lightroom Classic

Read-only macOS prototype, version 0.1.0.1. Adds a **Colorgain** choice to the Library module's Metadata panel and a **Library > Plug-in Extras > Refresh Colorgain Metadata** command. The same fields also appear under **All Plug-in Metadata**.

## Use

1. Select one or more photos in Library.
2. Choose **Library > Plug-in Extras > Refresh Colorgain Metadata**.
3. Choose **Colorgain** in the Metadata panel's view selector.

The panel displays Custom Value (`colorgain:colorgain`, currently XXXXX in the test DNG), Application, Test ID, Test Note, source location, last checked time and all Colorgain fields. These are cached snapshots. Refresh again after an external edit. Read errors clear prior displayed values and explain the failure.

Only namespace `urn:colorgain:metadata:1.0:` is read. XML prefix spelling is irrelevant. Standard exposure, copyright and IPTC fields are not imported or changed. Test Note is stored historical text, not a live exposure reading.

## Source rules and limits

- Adjacent same-stem `.xmp` containing Colorgain fields takes precedence as a whole. Fields from different sources are not merged.
- If a valid sidecar contains no Colorgain fields, inspect supported embedded metadata and label that fallback explicitly.
- A malformed or unreadable sidecar is an error, not permission to display potentially stale embedded data.
- Embedded XMP currently supports classic TIFF containers, including DNG and CR2. Standalone XMP is also readable. JPEG, PNG, CR3, other embedded containers, compressed XMP and BigTIFF are not implemented.
- Read limit: 16 MB per XMP packet. Only the file's TIFF directory and XMP region are read, not its image payload. XML DTD/entity declarations are rejected.
- The prototype supports simple custom attributes/elements. Complex structured history is not a typed history UI.
- A virtual copy shares its underlying file metadata; this plug-in does not represent virtual-copy Develop settings.
- Source files are opened read-only. The plug-in writes its own display fields to Lightroom's catalogue via the supported SDK. It never saves Develop settings, writes source/sidecar files, adds keywords or imports images.
- macOS only, built for the development machine's architecture. This is a local prototype, not a signed distributable release.

## Build and installation

Run `tools/lightroom/build.sh`, then `python3 tools/lightroom/test_reader.py` from the repository root. Build output is `.build/lightroom/Colorgain.lrplugin`; the helper is compiled with Apple's Swift toolchain and requires no Python installation at runtime. The main Colorgain app is unaffected.

Copy the complete bundle to `~/Library/Application Support/Adobe/Lightroom/Modules/Colorgain.lrplugin`. In Lightroom, open **File > Plug-in Manager > Add** and select it. After Lua changes, reload it through Plug-in Manager. The reader is launched afresh on every refresh.

Installed locally on 17 October 2026. Lightroom Classic 15.5.1 reported the plug-in enabled with no diagnostic messages. A real refresh of 0028.CR2 populated the visible All Plug-in Metadata panel with the application, UUID, test note, sidecar source and last checked time. The standalone helper also reads XXXXX from 0028-Rendered.dng. Selecting the dedicated tagset and displaying that DNG in Lightroom still need a hands-on check; native canvas controls did not respond reliably to automation.

Fixture checks cover alternate XML prefixes, attributes/elements, UTF-8 and newline values, both TIFF byte orders, unchanged source bytes, missing files, malformed XML and TIFF, entity rejection, empty metadata, sidecar priority and embedded fallback. Review also checked read-only source access and stale-field clearing.

Sources: [Adobe Lightroom SDK](https://developer.adobe.com/lightroom-classic). Metadata field definitions and tagsets follow chapters 4 and 10 of Adobe's Lightroom Classic SDK Programmer's Guide.
