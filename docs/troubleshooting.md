# Troubleshooting

Find what you're seeing below. Words in **bold** are exactly what appears on screen.

**On this page:**
[macOS won't open Cove](#macos-wont-open-cove) ·
[“This Mac” shows a problem](#this-mac-shows-a-problem) ·
[Not enough disk space](#not-enough-disk-space) ·
[The download failed or stopped](#the-download-failed-or-stopped) ·
[Two macOS VMs are already running](#two-macos-vms-are-already-running) ·
[Keyboard or pointer stuck in the VM](#keyboard-or-pointer-stuck-in-the-vm) ·
[Copy and paste don't work](#copy-and-paste-dont-work) ·
[A shared folder is missing](#a-shared-folder-is-missing) ·
[SSH isn't reachable](#ssh-isnt-reachable) ·
[I can't restore a snapshot](#i-cant-restore-a-snapshot) ·
[Settings didn't take effect](#settings-didnt-take-effect) ·
[Starting over](#starting-over)

## macOS won't open Cove

**You see:** *“Cove” Not Opened — Apple could not verify “Cove” is free of malware…* (macOS 15 or later), or
*“Cove” can't be opened because Apple cannot check it for malicious software* (macOS 14).

**Why:** Cove isn't notarized by Apple yet, so macOS asks you to approve it once.

**Fix:**

1. Click **Done** (or **OK**). Don't click **Move to Trash**.
2. Open **System Settings ▸ Privacy & Security**.
3. Scroll to the **Security** section, find *“Cove” was blocked to protect your Mac*, and click **Open Anyway**.
4. Click **Open Anyway** again and enter your Mac's password.

**Don't see Open Anyway?** It only appears for about an hour after macOS blocks the app. Open Cove again to make
it reappear, then go straight back to **Privacy & Security**.

**Control-click ▸ Open doesn't help?** That shortcut no longer bypasses this check on macOS 15 and later. Use
**Privacy & Security**.

**Comfortable with Terminal?** You can instead mark this copy as trusted:

```sh
xattr -dr com.apple.quarantine /Applications/Cove.app
```

Please don't turn off Gatekeeper or other macOS security settings to run Cove.

## “This Mac” shows a problem

The **This Mac** panel on the Welcome screen checks four things.

| Item | If it isn't green |
|---|---|
| **Apple silicon** | Cove needs a Mac with Apple silicon (M1 or later). Intel Macs can't run macOS VMs. |
| **Virtualization framework** | Virtualization isn't available — usually because Cove is running inside another VM. Run Cove on your Mac directly. |
| **Free disk space** | See [Not enough disk space](#not-enough-disk-space). |
| **Internet connection** | Connect to the internet. macOS is downloaded from Apple. (This is a warning only; you can still install from an `.ipsw` file.) |

## Not enough disk space

**You see:** **Not enough disk space**, or a yellow banner: *Only … free on your library disk. Cove needs about
55 GB to download and install macOS.*

**Why:** A new VM needs room for the macOS download (about 25–27 GB) plus the installed system. Cove warns when
your library disk drops below 20 GB free and won't start a VM below 5 GB, so VMs don't run out of space mid-task.

**Fix — free up space:**

- **Remove downloaded macOS images** you no longer need: **Cove ▸ Settings… ▸ Storage**, then **Remove** next to
  an image.
- **Delete old snapshots:** **Virtual Machine ▸ Show Snapshots**, select one, click **Delete**.
- **Delete VMs** you don't use: right-click one in the Library, choose **Delete…**, then **Move to Trash**. Empty
  the Trash to get the space back.
- **Move your library** to a bigger disk: **Cove ▸ Settings… ▸ Storage ▸ Move…** (all VMs must be stopped).
  Use an APFS-formatted disk so snapshots stay instant.

## The download failed or stopped

**You see:** **Couldn't finish downloading macOS** — *The connection to Apple was lost at …%. Cove kept what was
downloaded and will pick up from there.*

**Fix:**

- Check your internet connection, then click **Resume Download**. Cove continues from where it stopped — even
  after you quit and reopen Cove.
- Or click **Use a File…** to install from a macOS restore image (`.ipsw`) you already have.

**Download keeps failing?** Try a different network, pause other large downloads, or make sure your Mac doesn't
sleep during the download (**System Settings ▸ Battery** or **Energy**).

If you cancel an installation, the partial download is kept and can be resumed later.

## Two macOS VMs are already running

**You see:** **Two macOS VMs are already running** — *Apple's macOS license allows two macOS virtual machines at
a time on one Mac.*

**Why:** This is part of Apple's macOS license, so Cove enforces it.

**Fix:** Click **Suspend “…” and Start** next to the VM you can pause for now. Suspending saves it exactly as it
is; resume it later. Or shut one down yourself from the menu bar or the **Virtual Machine** menu.

## Keyboard or pointer stuck in the VM

Press **⌃ Control + ⌥ Option** to give the keyboard and pointer back to your Mac. (If you changed it in
**Cove ▸ Settings… ▸ General**, use **⌃ Control + ⌥ Option + ⌘ Command**.)

While the VM has the keyboard, ⌘ shortcuts like ⌘Q and ⌘Tab go to the VM, not to your Mac.

## Copy and paste don't work

That's expected: macOS virtual machines don't support clipboard sharing between the VM and your Mac. To move
text or files:

- Use a [shared folder](getting-started.md#7-share-a-folder-optional), or
- Copy files over SSH with `scp` or `rsync` (see [SSH & agent access](ssh-and-agents.md)).

## A shared folder is missing

- **In the VM, look in** `/Volumes/My Shared Files`. In Finder, choose **Go ▸ Go to Folder…** and type that path.
- **Added it while the VM was running?** Shared folder changes apply after the VM restarts.
- **The folder moved or was renamed on your Mac?** Remove it in **Settings… ▸ Sharing** and add it again.
- **Older macOS in the VM?** Shared folders need macOS 13 or later inside the VM.

## “No such file or directory” when running the setup command

The path inside the VM is case-sensitive. Type it with the same capital letters:

```sh
sh "/Volumes/My Shared Files/Cove/setup.sh"
```

Tip: type `sh "/Volumes/My` and press Tab to let Terminal complete the name. If `ls "/Volumes/My Shared Files"`
doesn't list **Cove**, turn on SSH access in Cove, then shut the VM down and start it again.

## SSH isn't reachable

Work through these in order:

1. **Is the VM running** and finished starting up? SSH only works while it's running.
2. **Is the network connected?** **Settings… ▸ Network** should be **Shared (NAT)**, not **Disconnected**.
3. **Did the setup command run?** In the VM's Terminal, run
   `sh "/Volumes/My Shared Files/Cove/setup.sh"` again. If it says *SSH didn't start*, turn on
   **System Settings ▸ General ▸ Sharing ▸ Remote Login** in the VM and run it once more.
4. **No `/Volumes/My Shared Files/Cove` in the VM?** SSH access was turned on while the VM was running. Restart it.
5. **`Permission denied (publickey)`?** The setup ran as a different user. Run it again as the user you want.
6. **`Could not resolve hostname cove-…`?** Finish step 5 of the walkthrough (**Add Cove to ~/.ssh/config…**).
7. **Restored an older snapshot?** If it was taken before you ran the setup command, run it again.

More detail: [SSH & agent access ▸ Troubleshooting](ssh-and-agents.md#troubleshooting).

## I can't restore a snapshot

**You see:** *Shut down or suspend this VM before restoring a snapshot.*

**Fix:** Shut down or suspend the VM first, then click **Restore**. Cove takes an automatic snapshot of the
current state before restoring, so you can come back.

## Settings didn't take effect

Changes to processors, memory, disk, display, network and shared folders apply the next time the VM starts. If
the VM is running, shut it down and start it again — suspending and resuming isn't enough.

Disk size can only grow, never shrink. Growing a disk adds unused space to the end of the virtual disk, and
macOS inside the VM may not start using it on its own. If you know you'll need lots of room, it's simplest to
choose a bigger disk when you create the VM (**Customize… ▸ Disk size**).

## Starting over

- **Reset one VM:** restore its “Fresh install” snapshot, if it has one.
- **Remove one VM:** right-click it in the Library, choose **Delete…**, then **Move to Trash**.
- **Remove Cove but keep VMs:** `brew uninstall --cask cove`.
- **Remove Cove and everything it stored** — every VM, snapshot and downloaded macOS image:
  `brew uninstall --cask --zap cove`. **This can't be undone.**

Still stuck? Please [open an issue](https://github.com/arnavprabhu/cove/issues) with your macOS version, your
Mac's chip, and what you see.
