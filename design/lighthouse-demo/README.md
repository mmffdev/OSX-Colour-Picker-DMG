# Lighthouse motion demo

From this directory, run `python3 -m http.server 8768 --bind 127.0.0.1`, then open http://127.0.0.1:8768.

Both models start complete. Previous/Next or arrow keys traverse the seven stages. Stage numbers jump directly; Replay build starts at the island. Slow motion halves replay speed. Reduced-motion system settings remove growth, rotation and water animation.

`demo.js` builds both scenes from geometry with Three.js 0.180.0 (vendored locally; MIT licence in vendor/LICENSE). No network assets are loaded. The approved image is linked from the page. This is a browser motion study; the macOS app is unchanged.
