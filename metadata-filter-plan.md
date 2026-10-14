# Metadata filters

## Purpose and interaction

Metadata filtering is a reusable Library primitive used first by image intake and then by the image catalogue view. The actionbar owns a **Filter by Meta** control. Activating it inserts a filter strip between the actionbar and the image grid; it takes layout space and pushes the grid down rather than covering thumbnails. The strip starts with three columns. Each column has a field selector and a value list; choosing a value narrows the next column and the visible image set. Users can add columns to make a longer sequence and remove a column without losing the earlier choices. The filter updates incrementally while the source scan is still producing records.

The same view/model contract accepts image records from Import and persisted catalogue records from Library. A saved preset contains only stable field identifiers, selected values, column order and hierarchy mode; it never stores a file path or a transient scan result. An empty field or unavailable metadata value is represented as **Unknown**, so files without EXIF remain filterable.

## Data to extract

Keep original metadata values and normalized filter values separately. Preserve source namespace/key for round-tripping and add a normalized value only when a mapping is unambiguous. Missing values stay missing; do not infer camera, location, author, ratings or edit state from filenames or previews.

| Column group | Filter fields | Sources and normalization |
|---|---|---|
| File | Capture date/time, year, month, day, file name, extension/file type, media type (raster / RAW), relative folder, file size, imported/linked state | EXIF `DateTimeOriginal`, TIFF `DateTime`, IPTC date, XMP `CreateDate`/`DateCreated`; filesystem URL and resource values; normalize dates to timezone-aware instants while retaining the source string. RAW type comes from `UTType`/ImageIO conformance. |
| Review | Flag/reject state, star rating, colour label, keyword, exported state, edit/develop state | XMP (`Rating`, `Label`, `Marked`, `UserComment`, `Subject`, `Keywords`, `History`), IPTC keywords, catalogue review/edit records. Distinguish absent from zero/no-label. |
| Camera | Make, model, serial number, lens make/model, focal length, 35mm-equivalent focal length, exposure time/shutter speed, aperture/f-number, ISO, exposure bias, exposure program, metering mode, flash, white balance, orientation, pixel width/height, colour space/profile | EXIF/TIFF properties (including maker-note values when ImageIO exposes them), XMP camera fields, ImageIO dimensions/profile. Preserve exact numeric values; expose display-form values alongside canonical numeric values for range filters. |
| Location | GPS present, latitude, longitude, altitude, timestamp, location/map label, sub-location, city, state/province, country/region, country code | EXIF GPS dictionary, IPTC location fields, XMP location fields and matching sidecars. Do not geocode coordinates without user opt-in or network access; map label is a separate supplied value. |
| Rights and provenance | Creator/author, job/title, description/caption, copyright status/notice, rights/usage terms, credit/source, DOI | IPTC and XMP namespaces; JSON, XML/XMP, CSV/TSV sidecars sharing the image basename. Keep DOI as a normalized field when its source key is known, while retaining the original metadata key/value. |
| Extensible | Any supported embedded or sidecar key/value, namespace, metadata source, parse status | ImageIO property dictionaries; JSON object paths; XML/XMP expanded/local names; delimited sidecars. Keep raw values available for inspection and later field mappings. Apply size limits and report malformed sidecars without dropping the image. |

### Initial supported fields

The first implementation should offer fields that can be extracted reliably from ImageIO and standard sidecars: capture date, year/month/day, file name, file type, media type, flag/rating/label/keyword when present, camera make/model/serial, lens, focal length, shutter speed, aperture, ISO, flash, GPS presence/coordinates, city/state/country, creator, copyright, job, DOI and arbitrary metadata. `Exported`, `Develop`, map labels and Colorgain review state are catalogue-owned fields and remain Unknown until those records exist. Pixel dimensions are available as metadata; they must not be presented as thumbnail display dimensions.

## Filter semantics

- Three columns by default; additional columns are user-created and ordered left to right.
- Within one column, selecting multiple values is OR. Across columns, criteria are AND.
- A child column's values are computed from records surviving all earlier columns. Choosing a new earlier value clears only downstream values that no longer exist.
- Date supports a hierarchy (year → month → day) and a flat date mode. Other fields use distinct normalized values, sorted naturally; numeric fields can later add ranges without changing the record contract.
- Unknown is an explicit value. A missing date is not treated as an epoch, an absent rating is not treated as zero, and absent labels are not treated as a positive rating.
- Filter results are a projection of the currently available source/catalogue records. They never copy, move, edit or discard image files.
- New Images compares normalized file identity against this catalogue's registered image assets. Until registration exists, the UI must communicate that the current scan has no known imported assets; it must not invent duplicate knowledge.

## Saved presets and persistence

`MetadataFilterPreset` is versioned and catalogue-scoped: stable UUID, name, ordered columns, selected normalized values, date hierarchy mode, and schema version. Save, Edit and Remove operate on the preset list; a selected preset can be applied to Import or Library. Editing a preset preserves its UUID. Duplicate names are allowed only when disambiguated in the list; blank names are rejected.

The portable source of truth is an optional `metadataFilters` field in the catalogue's `.colcat` structure document. A mirrored copy is stored in `.coldata` under a top-level `metadataFiltersByCatalogue` map keyed by catalogue UUID. A single `MetadataFilterStore` handler reads and writes both. On save it snapshots both files, writes the updated `.colcat` atomically, then updates `.coldata`; if the second write fails it restores the first snapshot. If the process exits between writes, the next read treats `.colcat` as authoritative and repairs the `.coldata` mirror. Catalogue import/relocation carries the `.colcat` definitions; opening that catalogue on another Mac repopulates the local mirror. Machine-specific bookmarks and access grants never enter a preset.

This avoids coupling portable definitions to App Preferences while keeping the app-home index convenient for listing and recovery. The mirror is not a separate source of truth and cannot override newer portable catalogue data.

## Rollout

1. Add the metadata record and preset model, safe dual-file store, versioned `.colcat` field, and self-tests for round-trip, rollback, relocation and old catalogues with no field.
2. Replace the import toolbar's duplicate thumbnail slider with the existing `StudioPage` tile-size slider. Make Grid/Full and Sort genuine controls; Full uses one image column and the existing card selection model.
3. Add the shared three-column filter strip, expanding/collapsing in layout below the actionbar. Feed it incrementally during import scanning and add it to the Library image-catalogue view when registered image assets are shown.
4. Add preset list, Save, Edit and Remove; verify both file copies and that a copied catalogue restores presets on another app home.
5. Expand field coverage from the reliable initial set; add range filters, geospatial groupings and custom field mappings only when extraction and provenance are explicit.

## Safety and performance

Metadata parsing and sidecar reads run on the existing bounded preview queue, never on the main thread. Cache normalized values per file identity (canonical path plus file size/modification time, with content hash only when available or requested). Process scan batches incrementally, debounce only presentation updates, and cancel stale scans. Sidecars are same-basename siblings by default; do not scan or follow arbitrary neighboring files. Bound sidecar bytes, nesting depth, XML entity expansion and value lengths. Never execute metadata, resolve external XML entities, load remote URLs, or trust file content as UI markup. Record parse errors per field/source and keep the image visible.
