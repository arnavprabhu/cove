# Getting started with Cove

This guide takes you from nothing to a working Mac-inside-your-Mac. No experience with virtual machines needed.
Words in **bold** are exactly what you'll see on screen.

New words? See the [glossary](README.md#glossary).

**On this page:** [Before you start](#before-you-start) · [Install Cove](#1-install-cove) ·
[Approve Cove](#2-approve-cove-the-first-time) · [Create your first VM](#3-create-your-first-vm) ·
[Setup Assistant](#4-finish-setup-assistant-in-the-vm) · [Everyday use](#5-everyday-use) ·
[Snapshots](#6-snapshots-your-undo-button) · [Share a folder](#7-share-a-folder-optional) ·
[Next steps](#next-steps)

## Before you start

You need:

- A Mac with **Apple silicon** (M1 or later). To check, choose **Apple menu ▸ About This Mac** and look for
  "Chip: Apple M…".
- **macOS 14 Sonoma** or later.
- About **55 GB of free space**. To check, open **System Settings ▸ General ▸ Storage**.
- An internet connection. macOS is a large download (about 25–27 GB), so a fast connection helps.

## 1. Install Cove

The easiest way is [Homebrew](https://brew.sh), a free tool for installing Mac apps from Terminal.

1. Open **Terminal** (in **Applications ▸ Utilities**).
2. Type this and press Return:

   ```sh
   brew install --cask arnavprabhu/tap/cove
   ```

3. When it finishes, Cove is in your **Applications** folder.

Don't have Homebrew? Follow the one-line install on [brew.sh](https://brew.sh) first, or
[build Cove from source](../README.md#build-from-source).

## 2. Approve Cove the first time

Cove isn't notarized by Apple yet. That means macOS can't check it for you, so the first time you open it macOS
stops it and shows a warning. You only need to approve it once.

1. Open **Cove** from **Applications**.
2. macOS says it **can't verify** “Cove”. On macOS 15 or later the message is:

   > “Cove” Not Opened
   > Apple could not verify “Cove” is free of malware that may harm your Mac or compromise your privacy.

   Click **Done**. Don't click **Move to Trash**.
3. Open **System Settings** and click **Privacy & Security** in the sidebar.
4. Scroll down to the **Security** section. You'll see *“Cove” was blocked to protect your Mac.*
5. Click **Open Anyway**.
6. A dialog asks if you're sure. Click **Open Anyway** again and enter your Mac's password (or use Touch ID).

Cove opens. From now on it opens normally, like any other app.

> [!TIP]
> On macOS 15 and later, the old trick of Control-clicking the app and choosing **Open** no longer works for
> this. Use **Privacy & Security** as above. You don't need to — and shouldn't — turn off any of macOS's
> security settings.

Still stuck? See [Troubleshooting ▸ macOS won't open Cove](troubleshooting.md#macos-wont-open-cove).

## 3. Create your first VM

When Cove opens you'll see **Welcome to Cove**. The panel on the right, **This Mac**, checks that your Mac is
ready. All items should have a green check.

1. Click **Create macOS Virtual Machine**. (Or click one of the three tiles above it to start with that purpose
   already chosen.)
2. Under **Which macOS do you want?**, leave **Latest from Apple** selected. Cove asks Apple for the newest
   macOS your Mac can run.
3. Under **What's it for?**, choose one:

   | Choose | If you want to… | Cove sets up |
   |---|---|---|
   | **Agent sandbox** | Give AI agents or assistants a Mac to work in | SSH access, passwordless `sudo` and a “Fresh install” snapshot |
   | **Everyday & tinkering** | Try apps, betas and downloads | A balanced VM with an 80 GB disk |
   | **Development & testing** | Build, test installers, try other macOS versions | A larger 128 GB disk |

   You can change any of this later.
4. Give the VM a **Name**, or keep the suggested one.
5. Cove has already sized the VM for your Mac (**Sized for your Mac**). To change processors, memory, disk,
   display, network or shared folders, click **Customize…**. Most people don't need to.
6. Click **Create & Install**.

Cove now works through four stages: **Check this Mac**, **Download restore image**, **Install macOS** and
**First boot**. On an M5 Pro, installing took about 15 minutes after the download; your time depends on your Mac
and your internet connection.

You don't have to watch. Click **Continue in Background** and keep using your Mac — Cove sends a notification
when your VM is ready.

> [!NOTE]
> The macOS download (the *restore image*) is kept so your next VM doesn't need to download it again. To save
> space instead, untick **Keep the restore image for future VMs** before you click **Create & Install**, or
> remove downloaded images later in **Cove ▸ Settings… ▸ Storage**.

If the download stops partway, see [Troubleshooting ▸ The download failed](troubleshooting.md#the-download-failed-or-stopped).

## 4. Finish Setup Assistant in the VM

When installation finishes, the VM starts in its own window and shows Apple's **Setup Assistant** — the same
screens you see on a brand-new Mac.

1. Click inside the VM window. Your keyboard and pointer now go to the VM.
2. Choose your country, language and so on.
3. Create a user account. This account lives only in the VM; it doesn't need to match your Mac's.
4. **Apple Account:** you can skip signing in. For agent and assistant VMs we recommend skipping it, or using a
   separate account — see the [personal assistant guide](personal-assistant.md).

To get your keyboard and pointer back to your Mac, press **⌃ Control + ⌥ Option**.

> [!TIP]
> Before you install anything, take a snapshot named something like “Set up” (see below). It's your clean
> starting point.

## 5. Everyday use

- **Start, stop and pause.** Use the buttons at the top of the VM window, the **Virtual Machine** menu, or the
  Cove icon in your menu bar.
  - **Shut Down** turns the VM off, like shutting down a Mac.
  - **Suspend** saves exactly what's on screen to disk and frees up memory. **Resume** picks up where you left off.
  - **Pause** freezes the VM in memory for a moment.
- **See all your VMs.** Choose **View ▸ Show Library** (⌘0). Select a VM to see its details and snapshots.
- **Change settings.** Select a VM and choose **Virtual Machine ▸ Settings…** (⌘I). Changes to hardware,
  storage and network apply the next time the VM starts.
- **Two at a time.** Apple's macOS license allows two macOS VMs running at once on one Mac. If you start a third,
  Cove offers to suspend one of the others.

## 6. Snapshots: your undo button

A **snapshot** saves the whole VM exactly as it is right now. If something goes wrong later, restore the
snapshot and the VM goes back to that moment.

Snapshots are instant and take almost no space at first: Cove uses APFS clones, so a snapshot only stores what
changes after it.

**Take a snapshot**

1. Select the VM (or click its window).
2. Choose **Virtual Machine ▸ Take Snapshot…** (⇧⌘S), or click **Take Snapshot** in the VM window's toolbar.
3. Give it a name you'll recognize, like “Before installing beta”, and click **Take Snapshot**.

If the VM is running, the snapshot includes what's in memory too (you'll see **+ memory**).

**Restore a snapshot**

1. Shut down or suspend the VM.
2. Choose **Virtual Machine ▸ Show Snapshots** (⌥⌘S).
3. Select the snapshot and click **Restore**.

Cove automatically takes a snapshot of the current state first (marked **Automatic**), so you can always change
your mind.

> [!IMPORTANT]
> Snapshots cover the VM's own disk. They don't undo changes to [shared folders](#7-share-a-folder-optional) on
> your Mac.

From the same window you can also **Rename…**, **Delete** or **Clone to New VM…** — the last one makes a
separate VM that starts from that snapshot.

## 7. Share a folder (optional)

Shared folders let the VM see one folder from your Mac.

1. Shut down the VM.
2. Choose **Virtual Machine ▸ Settings…** (⌘I) and click **Sharing**.
3. Click **Add folder…** and pick the folder.
4. Choose **Read only** if the VM should be able to look but not change anything. Otherwise it's
   **Read & write**.
5. Start the VM. In the VM, the folder is in **Finder** under `/Volumes/My Shared Files`.

Only share what the VM needs. A VM can change or delete anything in a read & write folder, and snapshots don't
undo that.

## Next steps

- [Connect your AI agents over SSH](ssh-and-agents.md)
- [Run a personal assistant safely in a VM](personal-assistant.md)
- [Troubleshooting](troubleshooting.md)
