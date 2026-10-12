# Run a personal assistant in a VM

AI assistants can read your email, browse the web, fill in forms and organize files. That's useful — and it's a
lot of trust to hand over. On your own Mac, an assistant can potentially reach everything you can: your files,
your accounts, your messages, your saved passwords.

A Cove VM lets you give an assistant **a Mac of its own** instead. It sees only what you put there: the accounts
you sign in to inside the VM, and the folders you choose to share. Your own Mac stays yours.

**On this page:** [The idea](#the-idea) · [Set it up](#set-it-up) · [What to sign in to](#what-to-sign-in-to) ·
[Share one folder, read-only](#share-one-folder-read-only) · [Snapshots before risky tasks](#snapshots-before-risky-tasks) ·
[Good habits](#good-habits) · [What a VM doesn't protect](#what-a-vm-doesnt-protect)

## The idea

Think of the VM as a separate computer you've lent to your assistant.

| | On your Mac | In a Cove VM |
|---|---|---|
| Your files | Everything in your home folder | Only folders you share |
| Your accounts | Every account you're signed in to | Only accounts you sign in to in the VM |
| Messages, Photos, Keychain | Yours | The VM has its own, empty ones |
| Clipboard | Shared with everything | Not shared — macOS VMs don't support clipboard sharing |
| If something goes wrong | You clean up | Restore a snapshot |

## Set it up

1. **Create a VM.** Choose **Agent sandbox** under **What's it for?** if you also want to reach the VM over SSH
   from your Mac, or **Everyday & tinkering** if you'll only use its window. (New to Cove? Follow
   [Getting started](getting-started.md) first.)
2. **Finish Setup Assistant.** Create a user account in the VM. When asked to sign in with an Apple Account,
   choose to skip it, or use a separate account made for the assistant — not your personal one.
3. **Take a snapshot** named “Clean” (**Virtual Machine ▸ Take Snapshot…**, ⇧⌘S). This is your fresh start.
4. **Install the assistant inside the VM.** Download its app or command-line tool *in the VM* — for example in
   Safari inside the VM — just as you would on a new Mac.
5. **Sign in to only what it needs** (see below).
6. **Take another snapshot** named “Assistant ready”. You can return here any time.

> [!TIP]
> Running the assistant *inside* the VM is the key step. If the assistant runs on your Mac and only sends
> commands into the VM over SSH, it still has whatever access you've given it on your Mac.

## What to sign in to

A good rule: **sign in to the least the task needs, and make it easy to revoke.**

**Sign in to these inside the VM**

- The assistant's own account (its app, or an API key made just for this VM).
- Accounts the task really needs — ideally a **separate** email, calendar or storage account made for the
  assistant, or one you've shared specific items with.
- Services that let you create **limited tokens** or **app-specific passwords**, so you can revoke the VM's
  access without changing your main password.

**Keep these out of the VM**

- Your main **Apple Account / iCloud** — it would bring along your Photos, Messages, iCloud Drive and synced
  passwords.
- Your **password manager** vault.
- **Banking**, payment and investment accounts.
- **Work** single sign-on and admin accounts, unless the task needs them and your workplace allows it.
- SSH keys, API tokens and other secrets from your Mac.

> [!NOTE]
> Apple supports signing in with an Apple Account in a VM when both your Mac and the VM run macOS 15 or later.
> Some features may still be limited. For an assistant VM, a separate account — or none — is usually the better
> choice anyway.

## Share one folder, read-only

If the assistant needs some of your files, share **one** folder rather than your whole home folder.

1. On your Mac, make a folder for the assistant — for example `~/Assistant Inbox` — and put in only what it needs.
2. Shut down the VM.
3. Choose **Virtual Machine ▸ Settings…** (⌘I) and click **Sharing**.
4. Click **Add folder…** and choose the folder.
5. Set it to **Read only**.
6. Start the VM. The folder is at `/Volumes/My Shared Files/Assistant Inbox`.

Need the assistant to hand files back? Add a **second**, empty folder — say `~/Assistant Outbox` — and leave just
that one as **Read & write**. Check what lands there before you use it.

> [!WARNING]
> Restoring a snapshot resets the VM, **not** shared folders. Anything the assistant changes in a Read & write
> folder stays changed on your Mac.

## Snapshots before risky tasks

Before you ask the assistant to do something new or far-reaching — install software, run a script it found,
change settings, work through a long to-do list unattended:

1. Take a snapshot (⇧⌘S) with a clear name, like “Before inbox cleanup”.
2. Let it work. You can watch in the VM window, or leave it running.
3. Happy with the result? Keep going. Not happy? Shut down or suspend the VM, open
   **Virtual Machine ▸ Show Snapshots** (⌥⌘S), pick the snapshot and click **Restore**.

Snapshots are instant and only store what changes afterward, so take them freely.

## Good habits

- **Keep macOS in the VM up to date** with **System Settings ▸ General ▸ Software Update** inside the VM.
- **Suspend the VM when you're not using it** (⌥⌘U). It stops using memory and resumes exactly where it left off.
- **Remember that snapshots keep sign-ins.** A snapshot taken while an account was signed in still contains that
  sign-in. When you remove an account from the VM, delete older snapshots that include it too.
- **Revoke, don't just delete.** When you stop using an assistant VM, revoke its tokens and app-specific passwords
  at each service, then delete the VM.
- **Go offline when you can.** For tasks that don't need the internet, set **Network** to **Disconnected** in
  **Settings… ▸ Network** (SSH access needs the network).

## What a VM doesn't protect

Being clear about the limits helps you use it well.

- **Accounts you sign in to.** If the assistant is signed in to an email account, it can read and send email from
  that account — the VM limits *which* accounts it can use, not what it does with them.
- **The internet and your network.** With the default **Shared (NAT)** network, the VM can reach the internet
  and other devices and services on your network, including any your Mac offers on its network.
- **Read & write shared folders**, as above.
- **Things you copy out.** Files you bring back to your Mac from the VM are just files — treat downloads and
  results with the same care as anything else.
- **Flaws in macOS itself.** A VM is a strong, practical separation, but no software boundary is perfect.

See also: [Safety model](../README.md#safety-model) · [SSH & agent access](ssh-and-agents.md)
