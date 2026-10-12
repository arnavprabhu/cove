# Cove documentation

Cove gives AI agents and assistants a Mac of their own — and gives you a spare Mac for testing and tinkering —
using virtual machines that run right on your Mac.

## Guides

| Guide | Read this if you want to… |
|---|---|
| **[Getting started](getting-started.md)** | Install Cove, approve it in **Privacy & Security**, create your first VM, finish Setup Assistant and use snapshots. |
| **[SSH & agent access](ssh-and-agents.md)** | Let Claude Code, Codex, Cursor or your own scripts run commands in a VM with `ssh cove-<name>`. |
| **[Run a personal assistant in a VM](personal-assistant.md)** | Give an assistant its own Mac, decide what to sign in to, and share a single folder read-only. |
| **[Troubleshooting](troubleshooting.md)** | Fix a blocked first launch, low disk space, a failed download, the two-VM limit, SSH problems and more. |

The [main README](../README.md) covers what Cove is, the [safety model](../README.md#safety-model), the
[FAQ](../README.md#faq) and [building from source](../README.md#build-from-source).

## Glossary

- **Virtual machine (VM)** — A complete computer simulated by software, running in a window on your Mac. A Cove VM runs real macOS with its own disk, user accounts, apps and settings, separate from your Mac's.
- **Host** — Your actual Mac: the one running Cove. The VM is sometimes called the *guest*.
- **Restore image** — The file Apple publishes to install macOS on Apple silicon Macs. Its name ends in `.ipsw` and it's about 25–27 GB. Cove downloads it from Apple and, unless you choose otherwise, keeps it so your next VM installs without downloading again.
- **Setup Assistant** — The series of screens a new Mac shows the first time it starts — language, user account, Apple Account and so on. Every new VM starts with it.
- **Snapshot** — A saved copy of a VM at a moment in time. Restore it to put the VM back exactly as it was. Cove's snapshots are *APFS clones*: they're instant and only store what changes afterward.
- **APFS clone** — A feature of the Mac's file system (APFS) that copies a file instantly by sharing its data with the original. Only parts that later change take up new space.
- **Clone (VM)** — A separate VM made from an existing VM or snapshot. It gets its own identity on the network.
- **Suspend** — Saves everything the VM is doing to disk and stops it, so it uses no memory. **Resume** continues exactly where it left off. **Pause** is similar but keeps the VM in memory.
- **Shared folder** — A folder on your Mac that the VM can see, under `/Volumes/My Shared Files`. It can be **Read & write** or **Read only**.
- **SSH** — “Secure Shell” — the standard way to run commands on another computer from Terminal, e.g. `ssh cove-agent-sandbox 'ls'`. Coding agents use it to work in a VM.
- **SSH key** — A matched pair of files used instead of a password. The *private* key stays on your Mac; the *public* key goes in the VM. Cove makes one pair for your library.
- **Remote Login** — macOS's name for its built-in SSH service. Cove's setup command turns it on inside the VM.
- **`sudo`** — Runs a command as an administrator. **Let agents use sudo without a password** allows agents to make administrator changes inside the VM without typing a password. It doesn't affect your Mac.
- **NAT (Shared network)** — The VM shares your Mac's internet connection and gets a private address like `192.168.64.6`. It's Cove's default network mode.
- **Agent** — An AI program that can take actions — run commands, edit files, use apps — rather than just answer questions. Examples include Claude Code and Codex.
- **Gatekeeper** — The part of macOS that checks apps before they open. Because Cove isn't notarized yet, you approve it once in **System Settings ▸ Privacy & Security**.
- **Notarization** — A check Apple runs on apps distributed outside the App Store. Notarized apps open without the extra approval step. Cove isn't notarized yet.
- **Homebrew / cask** — [Homebrew](https://brew.sh) installs software from Terminal. A *cask* is a Homebrew package for a Mac app.
