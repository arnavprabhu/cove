# Contributing to Cove

Thanks for helping. Bug reports, ideas and pull requests are all welcome.

- **Questions and ideas:** [Discussions](https://github.com/arnavprabhu/cove/discussions)
- **Bugs:** [open an issue](https://github.com/arnavprabhu/cove/issues/new/choose)
- **Security problems:** report them privately (see [SECURITY.md](SECURITY.md))

## Building

You need an Apple silicon Mac with macOS 14 or later, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate     # creates Cove.xcodeproj from project.yml (not checked in)
xcodebuild -project Cove.xcodeproj -scheme Cove -derivedDataPath build/dd test
```

`scripts/install.sh` builds a Release copy and installs it to `/Applications`.

Handy for checking your work (Debug builds only):

- `-coveRender <dir>` renders every screen with sample data, in dark and light, to PNGs. The sandboxed app can only
  write inside its container, e.g. `~/Library/Containers/app.cove.Cove/Data/tmp/render`.
- `-coveSmoke fetch|install|ssh` exercises the real engine end to end (`install` downloads macOS — about 27 GB).

## Where things live

| Folder | What's there |
|---|---|
| `App/` | App entry, scenes, menus, window routing |
| `Engine/` | Virtualization.framework: VM bundles, configuration, sessions, install, snapshots, SSH access |
| `Model/` | Plain data types and the resource planner (unit-tested) |
| `UI/` | Theme, shared components, alerts |
| `Features/` | One folder per screen |
| `CoveTests/` | Unit tests |
| `scripts/`, `packaging/` | Install, packaging, icon and Homebrew cask template |

## Guidelines

- **Match the surrounding code**: naming, comment density and SwiftUI idioms. Use the `Theme` tokens and shared
  components so screens look right in light and dark mode.
- **Treat the VM as untrusted.** Anything a guest can write (shared folders, `Cove Status`, DHCP data) must be
  validated before the host uses it. See `Engine/GuestAccess.swift`.
- **Don't lose people's VMs.** File changes in a VM bundle should be atomic or easy to recover from.
- **Add tests** for logic in `Model/` and `Engine/` when you can, and keep `xcodebuild … test` passing.
- **Plain, friendly copy.** Short sentences, no jargon without explanation, UI names in **bold** in docs.
- Keep pull requests focused; describe how you checked the change.
