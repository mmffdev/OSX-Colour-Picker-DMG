# UI Components

Open `index.html` to review the control direction before changing the macOS app. The page is self-contained and works without a build step or network access.

`components.js` exposes reusable `ColorgainUI` factories for text actions, icon actions, mode and import choice buttons, circular checkboxes, dropdowns/dropups, and text, date, and multiline fields. `components.css` holds their shared tokens and states; `app.js` assembles the specimen page. The circular checkbox is a **proposal** based on the supplied reference. The native Swift `SwissCheckbox` remains square until the design is approved.

The raised button study is a separate proposal. It uses layered CSS gradients and shadows to reproduce the supplied capsule reference, including its bright rim, lower lip, cast shadow, raised disc and amber glow. No native button style changes are made by the study.

The native counterparts currently span `UIPrimitives/Buttons.swift`, `UIPrimitives/Design.swift`, and `UIPrimitives/Controls.swift`. HTML and Swift are separate runtimes, so approval should be followed by consolidating the corresponding Swift primitives and migrating call sites.
