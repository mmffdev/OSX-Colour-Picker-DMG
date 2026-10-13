# Workspace-first startup

Implemented direction requested by Rick, 2026-10-12.

- Open or create `colorgain.coldata` before constructing a LibraryController. App data owns settings, shared Assets and the catalogue registry; each `.colcat` owns its catalogue structure and asset references.
- `WorkspaceInventory` strictly reads existing app data without creating files. Registry/discovery failures are errors, never an empty catalogue list. Preserve registered missing/access-denied/invalid entries for Locate. Discover direct catalogue folders under Catalogues; exclude internal Assets and Backups indices. Relative registry paths are supported; known entries deduplicate by canonical location and catalogue UUID.
- Returning users select an existing catalogue, with the last UUID/name preselected when unambiguous. Validate before opening; retain original files and close startup. Migration requires the existing backup/update confirmation.
- A genuinely empty workspace enters first-catalogue creation. Create a blank catalogue only after the user supplies its name, then continue its structure questions. App-data location is not asked again. Interrupted creation resumes its saved draft; a missing catalogue offers recovery.
- Opening a different existing app-data folder switches the bootstrap location; it never moves the old workspace into the new one. New app-data creation accepts an empty folder and seeds it without replacing existing data.
- Open Workspace is in File and the application menu. `--workspace <folder-or-coldata-file>` opens a specific workspace. The NSApplication document handler also routes `.coldata` and `.colcat` opening through workspace validation.

## Persistent development resume

`Development → Resume Workspace Automatically` is a machine-local checkbox, default off. It is stored in the dedicated `com.mmffdev.colorgain.development` preference suite, independent of `.coldata` and disposable trial settings.

- `--dev-on` enables it persistently. Later sessions need no flag.
- `--dev-off` disables it persistently; off wins if both commands are supplied.
- Resume is permitted only when setup is complete and the remembered catalogue validates as ready. Missing access, missing data, invalid data and migration still use recovery/selection.
- Development resume skips automatic startup animation. Explicit `--splash` / `--splash-loop` remain deliberate previews; a saved legacy splashLoop preference does not force onboarding on normal launches.
- Automatic relaunches strip dev-on/off commands so they cannot undo a subsequent menu toggle. Development resume also preserves a --new-user trial between development sessions; turn it off before intentionally running a fresh trial.
- Leave the preference off for the first clean build and user verification. Do not enable it as part of installing or testing this change. Unit tests use an isolated preference suite.

Regression coverage includes genuinely empty data with Assets present, several catalogues, disconnected entries, preserved unknown manifest fields, invalid/newer manifests and catalogue indices, source-file/folder selection, setup gating, persistent on/off behaviour and relaunch argument handling. Native QA must check file/folder opening, existing-catalogue completion and first-catalogue creation at reference and minimum window sizes.

Native verification: existing `.coldata` file and folder selection both resolve catalogues; opening MMFFDev - 001 closes startup and restores the 1,034-colour workspace. Creating an empty temporary app-data folder offers first-catalogue creation without creating Main. Reference and minimum-size layouts were inspected; the real workspace was restored and the development toggle remained off.

Completed workspaces with a valid last catalogue resume on ordinary launches. The development flag remains independently persistent and off by default; it is not required for normal resume. Missing or invalid catalogues retain the recovery chooser. General settings offers a manual wizard and a portable preference reset that retains workspace identity and completion flags.
