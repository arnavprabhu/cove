# Changelog

All notable changes to Cove are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and Cove uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-10-11

First public release. Requires a Mac with Apple silicon running macOS 14 Sonoma or later.

### Added

- **One-click macOS VMs.** Cove downloads the latest macOS restore image Apple supports for your Mac, creates
  the VM, installs macOS and boots it. Downloads resume after an interruption, and restore images can be kept
  for the next VM. You can also install from a restore image already in the library or from any `.ipsw` file.
- **Purposes.** Start from *Everyday & tinkering*, *Development & testing* or *Agent sandbox*; each picks
  sensible CPU, memory and disk sizes for your Mac, and every setting can be changed later.
- **Library.** Every VM with its state, purpose and resources. Start, resume, suspend, shut down, rename,
  clone, export, import (`.cove` packages) and delete; show a VM in Finder.
- **Console windows.** Each running VM gets its own window with full keyboard and pointer support. Press ⌃⌥
  (or ⌃⌥⌘) to give the keyboard back to your Mac. Start in Recovery when you need it.
- **Suspend and resume.** Suspend a running VM to disk and resume it exactly where it left off. Running VMs
  are suspended automatically when you quit Cove.
- **Snapshots.** Take, restore, rename, delete and clone snapshots, kept as space-saving APFS clones. New VMs
  get a "Fresh install" snapshot so you can always get back to a clean Mac.
- **SSH & agent access.** Reach any VM with `ssh cove-<name>`, from your own terminal or a coding agent on your
  Mac. A guided walkthrough sets up the key, the guest and passwordless sudo; Agent sandbox VMs turn it on by
  default.
- **VM settings.** Processors, memory, disk size, display resolution, sound, network (NAT with a stable MAC
  address), shared folders (read-only or read-write) and notes.
- **Menu bar.** See and control running VMs from the menu bar, and keep VMs running after the main window is
  closed.
- **App settings.** Open at login, defaults for new VMs, library location, restore image storage.
- **Safeguards.** Warnings for low disk space while VMs run, a clear explanation of macOS's limit of two
  running macOS VMs, notifications when an install finishes, and a dedicated screen on Macs that can't run VMs.

[Unreleased]: https://github.com/arnavprabhu/cove/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/arnavprabhu/cove/releases/tag/v0.1.0
