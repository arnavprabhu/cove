# Security

Cove runs software you may not fully trust (AI agents, test builds, downloads) inside virtual machines, so the
boundary between a VM and your Mac matters. Reports are very welcome.

## Reporting a problem

Please **don't open a public issue**. Use
[private vulnerability reporting](https://github.com/arnavprabhu/cove/security/advisories/new) on GitHub instead.
Include what you found, how to reproduce it, and the Cove and macOS versions. You'll get a reply within a few
days, and credit in the release notes if you'd like it.

## What's in scope

- A VM reading, writing or running anything on your Mac beyond what you shared with it
- Anything a VM writes being trusted by Cove on the host (for example the SSH status files or `~/.ssh/cove/config`)
- Importing a `.cove` file leading to access outside that VM
- Cove's sandbox, entitlements, SSH keys and file permissions
- Data loss: VMs, snapshots or saved state destroyed or corrupted by Cove

## Good to know

- Cove is open source and ad-hoc signed, not notarized (see the README's install section).
- Folders you share into a VM are readable — and writable unless marked **Read only** — by anything in the VM.
  Snapshots don't undo changes to shared folders.
- With **passwordless sudo** on, anything in the VM can become administrator *inside the VM*. That doesn't extend
  to your Mac.
- Only the latest release gets security fixes.
