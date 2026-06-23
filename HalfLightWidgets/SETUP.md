# HalfLight Widgets — status & notes

The widget extension target (`HalfLightWidgetsExtension`) is fully wired in the
Xcode project and **builds**. No further target setup is needed.

## Layout
- `Shared/` — code compiled into BOTH the app and the widget
  (`DreamSnapshot.swift`, `QuickRecordIntent.swift`). Referenced by both targets
  via file-system-synchronized groups.
- `HalfLight/Widgets/` — app-only (`WidgetSnapshotWriter.swift`,
  `HalfLightShortcuts.swift`).
- `HalfLightWidgets/` — the widget extension (bundle, provider, widget views,
  Control, theme, Info.plist, Assets, entitlements).

## App Group
Both targets share `group.LanternHours.HalfLight` via their `.entitlements` files,
and both build configs set `REGISTER_APP_GROUPS = YES` with automatic signing — so
the group is provisioned automatically.

> If a **device** build ever complains about the App Group / provisioning, open
> each target ▸ Signing & Capabilities and confirm **App Groups** lists
> `group.LanternHours.HalfLight` (add it with **+ Capability** if missing). The
> Simulator doesn't enforce this.

## Try it
1. Run the app once (writes the first snapshot; it refreshes on every change).
2. Long-press Home/Lock Screen ▸ add HalfLight widgets: **Streak & Record**,
   **Latest Dream**, **Dream Stats**, **Dream Prompt**.
3. Add the **Record a Dream** control (Control Center / Lock Screen gallery).
4. Any "Record" surface — or "Hey Siri, record a dream in HalfLight" — opens a new
   dream with dictation already running.
