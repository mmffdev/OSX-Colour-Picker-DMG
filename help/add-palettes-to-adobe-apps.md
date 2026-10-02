# Add a palette to Photoshop, Illustrator or InDesign

MMFFDev Colour 3 can put a palette where an Adobe app keeps its own colour libraries, so it appears in that app's menus in every document.

## What you need

- MMFFDev Colour 3 in your Applications folder
- Photoshop, Illustrator or InDesign installed
- An administrator's password for your Mac

## Add a palette

1. Select the palette in the sidebar.
2. Choose **File ▸ Add To Adobe Apps**, or right-click the palette and choose **Add To Adobe Apps**.
3. Pick where it should go:

   | Choice | What the Adobe app gets | Where you find it |
   |---|---|---|
   | Photoshop — Colour Book | A colour book | Colour picker ▸ Color Libraries ▸ Book |
   | Photoshop — Swatches | A swatch file | Presets ▸ Color Swatches folder |
   | Illustrator — Swatch Library | A swatch library | Swatches panel ▸ Open Swatch Library |
   | InDesign — Colour Book | A colour book | Presets ▸ Swatch Libraries folder |

   Only the Adobe apps installed on your Mac are listed.
4. If your Mac asks for your password, enter it. See "Why am I asked for my password?" below.
5. Quit and reopen the Adobe app. It reads its libraries when it starts.

### Example: a palette as a Photoshop colour book

1. Choose **File ▸ Add To Adobe Apps ▸ Photoshop 2026 — Colour Book**.
2. Restart Photoshop.
3. Click the foreground colour, then **Color Libraries**.
4. Open the **Book** menu and choose your palette by name. Each colour is listed with its name.

## Why am I asked for my password?

Adobe's library folders belong to macOS, not to you, so nothing can be saved there without an administrator's say-so. The password dialog is macOS's own. MMFFDev Colour 3 never sees or stores your password.

If you press **Cancel**, nothing is added. Finder opens with the file selected and the Adobe folder beside it; drag the file across and Finder will ask for your password itself.

The same happens if you use **File ▸ Export…** and choose one of these folders yourself.

## Stop being asked every time

The first time MMFFDev Colour 3 opens it shows a short setup: one row for each thing macOS needs you to allow, with a light and a button. The same rows are always in **Settings ▸ Permissions**.

1. On the **Adobe apps** row, press **Allow…**.
2. What happens next depends on where the app is installed:
   - **In the Applications folder (installed for all users):** macOS opens **System Settings ▸ General ▸ Login Items**. Allow MMFFDev Colour 3 there. This installs a small helper that can do one thing: save swatch files into Adobe's library folders.
   - **In your own Applications folder (installed for me only):** macOS asks for an administrator's password once, and your account is given leave to add files to Adobe's library folders.
3. The light turns green and reads **On**.

From now on palettes are added with no password dialog. Press **Turn Off** on the same row to go back.

| Light | Meaning |
|---|---|
| Green | On. Palettes are added without a password. |
| Orange | Waiting for you to allow MMFFDev Colour 3 in System Settings ▸ General ▸ Login Items. |
| Red | Off. Your password is asked for each time. Press Allow… |
| Grey | No Adobe apps were found on this Mac. |

## After an Adobe upgrade

Each yearly Adobe version has its own folders. Palettes you added to Photoshop 2026 are not carried into Photoshop 2027; add them again. If the app is installed for you only, the Adobe apps row goes red after an upgrade: press **Allow…** once more.

---

*Record for the help files. Tried on Rick's Mac on 2 October 2026 with the Adobe 2026 apps: the password dialog, turning the helper on from Settings ▸ Export (since moved to Permissions), and a palette appearing as a Photoshop colour book. Not yet tried: the first-open setup sheet, the Permissions pane, the "installed for me only" unlock, Photoshop — Swatches, Illustrator, InDesign, pressing Cancel, turning access off again.*
