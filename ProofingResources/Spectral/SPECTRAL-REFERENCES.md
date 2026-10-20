# Spectral reference data

The twelve `Wts-*.csv` tables are unchanged downloads from the [ICC Colorimetry Data registry](https://registry.color.org/colorimetry-data/), retrieved 17 October 2026. Source URL for each file: `https://registry.color.org/colorimetry-data/data/<filename>`. The registry credits the LWL least-squares weighting method to Li et al. and Tanzima Habib, revised by CIE TC1-102. Tables cover CIE 1931 (2°) and CIE 1964 (10°), illuminants D50/D65/A, and 380–730 or 380–780 nm at 10 nm. `spectral-sha256.json` pins the downloaded bytes; runtime loading verifies these hashes and table shape/normalisation. Packaged apps never substitute a developer's source-tree copy.

Calculation: sum each measured reflectance fraction times the corresponding published X/Y/Z weight and divide by 100. Measurements covering 780 nm use the 780 table; otherwise the 730 table. Sampling at 1/2/5 nm is linearly evaluated at the 10 nm nodes, without extrapolation. This is a bounded preview method, not an assertion of full ISO 13655, ASTM E308 or CxF conformance. Unmeasured tails are never invented.

Display context: calculated XYZ is represented relative to a fixed D65 reference display, preserving illuminant cast. It is converted into the app's existing D50 master representation solely for its display pipeline. No adaptation from the selected illuminant white is applied, and no human ambient-adaptation model is claimed. Values outside Display P3 are clipped for display; precise un-clipped XYZ remains available in the prediction result. The monitor's own calibration/gamut still limits the preview. 10° XYZ is encoded through standard 2° RGB for an approximate preview; this is not an exact conversion between observers. The displayed numerical XYZ is calculated directly from the selected observer, independently of that display encoding.

## Independent numerical fixture

`reference-values.json` contains twelve checks of the synthetic reflectance function `0.1 + 0.7 exp(-((wavelength-540)/65)^2)`. This is mathematical reference data, not a measured material. The reference XYZ values were separately integrated at 1 nm using CIE observer and illuminant data. The ICC-weighted 10 nm values are retained separately. The maximum absolute component difference is approximately 0.001048 (white Y = 1); the stated test tolerance is 0.0012. This is fixture agreement, not a universal error bound for arbitrary materials or proof certification.

Reproduce with `python3 tools/validate_spectral_references.py`. The script downloads official CIE tables, validates their published SHA-256 checksums, recomputes both paths and checks the committed fixture. CIE reference datasets are CC BY-SA 4.0; this derived fixture is provided under that same licence, with changes consisting of synthetic reflectance multiplication, normalisation and integration. The original CIE data are downloaded for verification and are not included here.

CIE attributions:

- CIE 2019, [CIE 1931 2° colour-matching functions](https://doi.org/10.25039/CIE.DS.xvudnb9b).
- CIE 2019, CIE 1964 10° colour-matching functions; [official dataset and metadata](https://files.cie.co.at/Publications-datasets/CIE_xyz_1964_10deg.csv_metadata.json).
- CIE 2022, [CIE standard illuminant D50](https://doi.org/10.25039/CIE.DS.etgmuqt5).
- CIE 2019, [CIE standard illuminant D65](https://doi.org/10.25039/CIE.DS.hjfjmt59).
- CIE 2018, [CIE standard illuminant A, 1 nm](https://doi.org/10.25039/CIE.DS.8jsxjrsn).
- [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).

CxF importer reference: [X-Rite CxF3 schema and examples](https://www.xrite.com/-/media/xrite/files/literature/misc/c/cxf3_schema_and_examples_en.zip), specifically `ReflectanceDataType` (1.0 = 100%), `WavelengthRange`, `ReflectanceSpectrum` and referenced `ColorSpecification`. Colorgain reads this documented reflectance subset; it does not redistribute the SDK, claim instrument control or accept every CxF custom resource. Original XML bytes retain data outside the calculated subset.
