# Colour Management App: Product Vision and Feature Deep Dive

Oct 1, 2026 · @Richard Cook

## Positioning

The app should be the system of record for colour across a studio: governed, versioned, measurable and wired live into every tool the team uses.

Image sampling and export are table stakes. The differentiators are three layers on top of them:

- **Colour science** that is correct for print, screen, 3D and video at the same time.
- **Governance** so brand colours are approved, locked, versioned and auditable.
- **Live distribution** so a change reaches every connected app, not just the next export.

## Our own colour system

We build a systematic, perceptually uniform colour system with measured physical references. Pantone's names, numbers and guides are protected, but colour values themselves are not.

- **Perceptual foundation.** The grid is built in OKLCH or CIELAB, so equal steps look equal to the eye. Pantone grew organically and has gaps. Ours can be systematic.
- **Self-describing codes.** A code such as `L62-C14-H245` states lightness, chroma and hue. Designers can reason about a colour from its code alone. Human-friendly names sit on top as an optional layer.
- **Substrate variants.** Each colour has coated, uncoated, textile, plastic and screen versions, because the same ink looks different on each.
- **Spectral data.** Physical guides are printed, measured with a spectrophotometer and published as spectral reflectance data in CxF format. This is the moat. Digital values alone cannot compete with a physical reference.
- **Physical products.** Printed fan guides and chip books become a revenue stream and the thing printers and manufacturers actually trust.
- **Nearest match against libraries users own.** Users import their own licensed libraries and we find the nearest match by Delta E 2000. We do not ship third-party library data ourselves.

Open question: legal review of the naming scheme, the cross-referencing feature and any trademark exposure before launch.

## Colour science

Every swatch must be correct in every destination it will be used, and the app must say when it cannot be.

| Area | What we support | Why it matters |
| --- | --- | --- |
| RGB spaces | sRGB, Display P3, Adobe RGB, Rec.709, Rec.2020, ACEScg | Screen, HDR video and VFX each need their own space |
| Linear vs encoded | Every RGB value flagged as linear or gamma-encoded | 3D and VFX renders go wrong with encoded values |
| Print | CMYK tied to ICC profiles (FOGRA39/51, GRACoL, SWOP), spot colours, soft proofing | CMYK without a profile is meaningless |
| Perceptual and device-independent | Lab, LCh, OKLCH, XYZ, HSB, HSL | Accurate comparison, scales and matching |
| Gamut warnings | Per destination, before export | Catch "can't print this teal on uncoated" early |
| Lighting | D50 and D65, metamerism warnings from spectral data | Colours that shift under shop or daylight get flagged |

On macOS we use ColorSync for ICC handling rather than building our own.

## Format support

Import and export covers every major discipline. 3D and game formats export in both sRGB and ACEScg linear.

| Discipline | Formats and targets |
| --- | --- |
| 2D and design | Adobe ASE, ACO, ACB, Apple .clr, Sketch, Affinity, CorelDRAW XML, Procreate .swatches, Clip Studio, Krita .kpl, GIMP and Inkscape .gpl, JASC and RIFF .pal, Aseprite and Lospec hex |
| 3D, animation and games | Blender (palette files plus add-on), Unity .colors preset libraries, Unreal data assets, Cinema 4D, Maya and Houdini via scripts |
| Video and grading | OCIO-aware values for Resolve and Nuke workflows, ACES-referenced swatches |
| Print and manufacturing | CxF3 (spectral), QTX, PDF spec sheets with spot and process breakdowns |
| Code and design systems | W3C Design Tokens (DTCG) JSON, Style Dictionary, CSS custom properties, SCSS, Tailwind config, SwiftUI, Xcode .colorset, Android colors.xml, Jetpack Compose, Flutter |

The existing export pack (library folder, PNG per colour, contact sheet, CSS tokens) stays as the default bundle.

## Feature deep dive

Features fall into seven groups. Governance and live distribution are where we beat existing tools.

### Capture

- System-wide menu bar eyedropper that grabs from any app on screen.
- iPhone camera capture, corrected against a printed calibration target. We sell our own target card, which doubles as marketing.
- Hardware colour meter support: Nix, Variable Spectro, Datacolor ColorReader.
- Extract palettes from a URL, PDF, AI or PSD file, video frame or Figma file.

### Build and generate

- Perceptually even tint and shade scales from one seed colour.
- Harmonies, gradient builder, automatic light and dark mode pairs.
- Semantic layer on raw colours (primary, surface, error) for design systems.
- Optional AI palette generation from a brief or mood board. Kept optional, as pros are wary.

### Validate

- Contrast matrix for every pairing against WCAG 2.2 and APCA.
- Colour vision deficiency simulation across the whole palette.
- Near-duplicate detection, e.g. three greys within 0.8 ΔE flagged for merging.
- Drift reports showing how a brand colour changed between versions.

### Govern

- Version history with visual diffs and rollback.
- Approval workflow: draft, review, approved, locked.
- Roles: owner, editor, contributor, viewer, external client.
- Deprecation with migration mapping, pushed to every connected tool.
- Full audit trail for regulated industries and agencies.
- Branching, so a team can explore a rebrand without touching the live library.

### Context and usage rules

- Notes per colour on where to use it and where not to.
- Approved pairings, proportions (e.g. 60/30/10), do and don't examples.
- Provenance: who sampled it, when, from what source.
- Physical cross-references the team adds, such as paint codes or thread numbers.

### Distribute live

- Plugins that keep libraries synced inside Adobe CC (UXP), Figma, Sketch, Blender, Unreal and VS Code. Export is a snapshot. Live sync makes us the source of truth.
- Auto-generated brand guideline PDFs and supplier spec sheets for printers.
- Public share pages for clients, with comment and approve actions.

### Integrate

- REST API and webhooks.
- CLI that pushes token updates to a GitHub repo as a pull request.
- Slack and Teams notifications when a library changes.

## Platforms and sync

macOS leads, with iOS and a web app close behind. Android ships last.

| Platform | Role | Priority |
| --- | --- | --- |
| macOS | Flagship, native SwiftUI, ColorSync | 1 |
| iPadOS and iOS | Camera capture, review, Apple Pencil picking, Procreate workflows | 2 |
| Web app | Clients, marketers and developers who won't install anything | 2 |
| Windows | Essential for 3D, games and video studios | 3 |
| Android | Small professional design user base | 4 |

Sync is offline-first, because designers work on trains and on set. Individuals sign in with Apple, Google or Microsoft. Enterprise gets SAML SSO and SCIM provisioning.

## Becoming the industry standard

Standards win by being open and embedded, not by being the best app.

- Publish an open library format: DTCG-based JSON with a spectral extension and CxF compatibility.
- Release a free reader SDK so other tools can read our libraries.
- Keep commercial value in the colour system, governance, live sync and physical products.

## Pricing model

Five tiers from free to enterprise, with viewers always free. Prices are proposals in GBP.

| Tier | Price (GBP) | For |
| --- | --- | --- |
| Free | £0 | Solo, 3 libraries, local only, standard exports |
| Pro | £8/month or £72/year | Unlimited libraries, all formats, sync, full colour system |
| Team | £14/user/month (min 3) | Shared libraries, plugins, comments, versioning |
| Studio | £24/user/month | Approvals, branching, audit trail, API, CLI |
| Enterprise | From \~£15k/year | SSO and SCIM, data residency, SLA, custom colour systems |

Additional revenue and adoption levers:

- **Free viewers.** Clients, developers and stakeholders never cost a seat. This drives adoption.
- **Free for education.** Students become future paying users.
- **Physical guides** sold separately, roughly £90 to £250 depending on substrate set.
- **Mac perpetual licence** for solo users who avoid subscriptions, with sync as an add-on.
- **Colour system licensing** for manufacturers and printers who reference our codes. Long term, this could out-earn the app.

## Risks and sequencing

The colour system with measured physical guides is our biggest differentiator and our biggest cost. We go digital-first and add physical guides once printers are on board.

1. Digital colour system on the perceptual grid, shipped in the macOS app.
2. iOS and web app, with sync, sharing and free viewers.
3. Plugins for Adobe CC and Figma, then Blender and Unreal.
4. Windows app.
5. Printed and measured physical guides, spectral data published.
6. Android app.

Other risks:

- **Legal exposure** on naming and cross-referencing. Needs review before launch.
- **Platform sprawl** across five clients plus plugins. A shared core library for colour maths and formats keeps behaviour identical everywhere.
- **Credibility of a new system.** Printers and manufacturers trust measured physical references, not apps. Partnerships matter as much as features.
