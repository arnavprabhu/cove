# Cove

A native macOS app that creates and runs **macOS virtual machines on Apple silicon** with Apple's
Virtualization.framework — one click to download, install and boot the latest macOS.

- Host: Apple silicon, macOS 14 Sonoma or later
- Stack: Swift + SwiftUI (AppKit bridges for `VZVirtualMachineView` and the menu bar extra)
- Engine: Virtualization.framework only (no QEMU, no kernel extensions)

## Build

```sh
brew install xcodegen
xcodegen generate            # creates Cove.xcodeproj from project.yml (not checked in)
open Cove.xcodeproj          # or:
xcodebuild -project Cove.xcodeproj -scheme Cove -derivedDataPath build/dd build
xcodebuild -project Cove.xcodeproj -scheme Cove -derivedDataPath build/dd test
```

Debug builds are ad-hoc signed with `com.apple.security.virtualization` and the App Sandbox. Release
distribution is Developer ID + notarization (set `DEVELOPMENT_TEAM` / signing in `project.yml`).

### Engine smoke test

```sh
APP=build/dd/Build/Products/Debug/Cove.app/Contents/MacOS/Cove
$APP -coveSmoke fetch     # resolve the latest restore image from Apple
$APP -coveSmoke install   # download → create → install → boot → suspend → resume → stop
```

Verified on an M5 Pro (macOS 27.0.1 host, 2026-10-11): `install` downloaded the 26.6 GB macOS 27.0.1 image,
installed it, took the "Fresh install" APFS-clone snapshot, booted, suspended to a save file, resumed from it and stopped.

### Visual QA

```sh
OUT=~/Library/Containers/app.cove.Cove/Data/tmp/render   # sandboxed app can only write inside its container
$APP -coveRender $OUT    # Debug builds: renders each screen with sample data, dark + light, to PNGs
```

## Keyboard

| Action | Shortcut |
|---|---|
| New Virtual Machine… / Import… | ⌘N / ⇧⌘O |
| Show Library | ⌘0 |
| Start / Resume · Restart | ⌘R · ⌥⌘R |
| Pause · Suspend · Shut Down | ⌥⌘P · ⌥⌘U · ⌥⌘. |
| Take Snapshot… · Show Snapshots | ⇧⌘S · ⌥⌘S |
| VM Settings… · Show in Finder | ⌘I · ⇧⌘R |
| Release keyboard from the VM | ⌃⌥ (or ⌃⌥⌘, App Settings) |

While a running VM has keyboard focus, ⌘-shortcuts go to the guest; press ⌃⌥ to give the keyboard back to Cove.

## Layout

| Folder | Contents |
|---|---|
| `App/` | App entry, scenes, window routing, commands |
| `Engine/` | Virtualization.framework: bundle format, configuration builder, sessions, install pipeline, resumable download, snapshots |
| `Model/` | Codable config, state, resource planner (pure, unit-tested) |
| `UI/` | Theme tokens, shared components, alerts |
| `Features/` | One folder per screen (Welcome, NewVM, Install, Library, Console, Snapshots, MenuBar, VMSettings, AppSettings, Alerts) |
| `Resources/` | Info.plist, entitlements, assets |
| `design/` | Reference mockups (`*.dc.html`) — not shipped |

## On-disk format

```
<Library>/VMs/<Name>.cove/          document package (UTI app.cove.vm)
  config.json  HardwareModel  MachineIdentifier  AuxiliaryStorage  Disk.img (sparse)
  SaveState.vzvmsave               only while suspended
  Snapshots/<uuid>/                meta.json, Disk.img, AuxiliaryStorage, SaveState?, config.json  (APFS clones)
  Thumbnail.png
<Library>/RestoreImages/*.ipsw     (+ .resume data for interrupted downloads)
```

Default library: `~/Library/Containers/app.cove.Cove/Data/Library/Application Support/Cove`.

## Decisions taken (from the handoff's open list)

- **Bridged networking**: implemented but compiled out. It needs Apple to grant `com.apple.vm.networking`;
  then add the entitlement and the `COVE_BRIDGED` compilation condition.
- **Export**: copies the `.cove` package (APFS clone, without snapshots/saved state). Zip / Apple Archive is a follow-up.
- **"Specific version"**: lists restore images already in the library cache plus any `.ipsw` the user picks.
  Apple's full catalog isn't a public API.
- **Intel Macs**: the binary is arm64-only; the "Unsupported Mac" screen is shown at runtime when
  virtualization is unavailable (e.g. inside a VM). A universal build that shows the screen on Intel is a follow-up.
- Name / bundle ID (`app.cove.Cove`) and App Store vs Developer ID remain open.

## Known gaps

- Live-UI verification of the console (thumbnail capture from the VM view's IOSurface, guest key routing)
  still needs a manual pass with a running VM — the engine path itself is verified by the smoke test.
- Updates pane has no updater yet (Sparkle or similar).
- Guest CPU/memory usage isn't exposed by Virtualization.framework; status bars show allocated resources.
