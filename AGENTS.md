# Mac Middle

## Project scope

Mac Middle is a small native macOS menu bar utility. Its purpose is to minimize the window under the pointer when the user middle-clicks an empty title bar or its title text, similar to GNOME.

Keep the app lightweight and dependency-free. Use public AppKit, Quartz, and Accessibility APIs. The minimum supported macOS version is 13.

## Project layout

- `Sources/main.swift`: application entry point, menu bar controls, Accessibility permission flow, mouse event monitoring, and Accessibility adapter.
- `Sources/WindowInteraction.swift`: testable click-sequence handling and title-bar detection.
- `Tests/`: unit tests with simulated Accessibility elements.
- `Package.swift`: dependency-free Swift Package Manager test configuration.
- `Info.plist`: bundle metadata and menu bar app configuration.
- `scripts/build.sh`: builds an app bundle for the host architecture and signs it ad hoc.
- `build/`: generated output; ignored by source control.
- `README.md`: user setup, limitations, troubleshooting, and verification steps.

## Build and verify

Run from the repository root:

```sh
swift test
bash scripts/build.sh
plutil -lint Info.plist
codesign --verify --strict --verbose=2 "build/Mac Middle.app"
```

Unit tests cover click-sequence handling and title-bar detection without Accessibility permission. They do not verify real Accessibility responses or global input delivery. For changes to event handling or title-bar detection, manually check Finder and Terminal, background windows, browser tabs and content, other mouse buttons, pause/resume, and full-screen windows. Record which checks were actually performed. A successful build does not establish that global input handling works.

Running the app requires the user's Accessibility permission. Do not claim live behavior was verified without exercising it on an authorized app instance. Moving or rebuilding an ad-hoc signed bundle may require granting permission again.

## Behavior constraints

- Handle only middle-button events, identified by Quartz mouse button number `2`.
- Minimize the window under the pointer, rather than assuming the frontmost window is the target.
- Consume a click only when minimizing succeeds, and suppress its matching drag/up events consistently.
- Preserve normal middle clicks in content, tabs, and interactive controls.
- Exclude full-screen windows and windows without an enabled minimize control.
- Prefer conservative title-bar detection. If Accessibility information is incomplete, leave the click alone.
- Keep Accessibility calls in the event callback bounded; slow callbacks can cause macOS to disable the event tap.
- Maintain event-tap recovery and cleanup when monitoring stops or the app quits.
- Keep the menu bar status useful when permission is missing or monitoring cannot start.

## Change conventions

- Follow the existing Swift style and avoid unnecessary frameworks or restructuring.
- Keep setup instructions and known limitations in the README aligned with actual behavior.
- Do not commit generated app bundles or build outputs.
- Do not introduce unrelated Cortex, Jira, Docker, or backend configuration; this directory contains the Mac Middle utility.
- Never add any Codex or AI attribution to git or code-review artifacts. This includes generated-by lines, co-author trailers, session trailers or links, commit messages, PR/MR titles, descriptions, comments, and example commit messages in plans or specs.
- If delegating work that involves commits or code-review artifacts, explicitly pass along the attribution restriction.
