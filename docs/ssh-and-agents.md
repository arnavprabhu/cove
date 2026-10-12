# SSH & agent access

Give AI agents a Mac of their own. After a five-minute setup, you — and coding agents on your Mac such as Claude
Code, Codex or Cursor, or your own scripts — can run commands in a Cove VM with one short command:

```sh
ssh cove-<vm-name> '<command>'
```

The agent's commands run in the VM, not on your Mac. If something goes wrong, restore a snapshot and you're
back where you started.

New to SSH? It's the standard way to run commands on another computer from Terminal. You don't need to know
anything about it to follow this guide. (See the [glossary](README.md#glossary).)

**On this page:** [Before you start](#before-you-start) · [The five steps](#the-five-steps) ·
[Tell your agent](#tell-your-agent-about-the-vm) · [A safe routine](#a-safe-routine-for-agent-runs) ·
[Sharing project files](#sharing-project-files) · [Troubleshooting](#troubleshooting) ·
[For developers](#for-developers)

## Before you start

**Quickest start:** create the VM with **Agent sandbox** as its purpose (on the Welcome screen, or under
**What's it for?** in **New Virtual Machine**). Cove turns on SSH access and passwordless `sudo` for you and takes
a “Fresh install” snapshot, so step 1 is already done.

Already have a VM? That works too — start at step 1.

**Open the walkthrough** in any of these ways:

- Select the VM in the Library and choose **Virtual Machine ▸ SSH & Agent Access…** (⇧⌘K).
- Click **SSH** in the VM window's toolbar.
- In the Library, click **Set Up…** (or **Open Walkthrough**) on the VM's **SSH & Agent Access** card.

The window shows the five steps below. Each one turns green with **Done** when it's complete, and Cove checks the
VM's status every few seconds, so you can just follow along.

## Let an agent do the setup

Have an AI agent that can see and control your screen (for example Claude Code or Codex with computer use)? Click
**Copy Setup Prompt** at the top of **SSH & Agent Access** — or **Copy Agent Setup Prompt** on the VM's SSH card in
the Library — and paste it into the agent.

The prompt covers only the steps that are still left, using the exact button names in Cove. It also tells the agent
to ask you for the VM's account name and password (never to make them up), not to sign in to any accounts, not to
change anything on your Mac outside Cove, and to stop and hand over to you whenever your Mac asks for its own
password or Touch ID. It finishes by checking `ssh cove-<name>` works and reporting what it did.

## The five steps

### Step 1 · Turn on SSH access

Turn on the **SSH & agent access** switch.

Cove adds a small **Cove** folder to the VM. It holds a setup script and Cove's *public* SSH key — the half of
the key that's safe to share. The private half stays on your Mac.

If the VM is already running, Cove asks you to **Restart** it so the folder appears. Save your work in the VM
first.

### Step 2 · Start the VM and finish Setup Assistant

Click **Start VM** (or **Open VM Window** if it's already running). If this is a new VM, finish Apple's
**Setup Assistant** and create your user account in the VM.

### Step 3 · Run the setup command in the VM

1. In the VM, open **Terminal** (in **Applications ▸ Utilities**, or search for it with Spotlight).
2. Type this command exactly, then press Return:

   ```sh
   sh "/Volumes/My Shared Files/Cove/setup.sh"
   ```

   You have to type it — copy and paste between your Mac and a macOS VM isn't available. **Capital letters
   matter**: `/volumes/my shared files/…` won't be found. Tip: type `sh "/Volumes/My` and press Tab to let Terminal
   fill in the rest.
3. Enter the password for your account **in the VM** when asked. (Nothing appears as you type. That's normal.)

When it's done, Terminal says *Cove: done.* and the walkthrough shows **Set up for user** with your VM user name.

The script:

1. turns on **Remote Login** (macOS's built-in SSH),
2. lets Cove's key sign in as your VM user,
3. if **Let agents use sudo without a password** is ticked, lets that user run administrator commands without
   typing a password (agents can't type passwords) — and removes that permission if it isn't ticked,
4. names the VM on the network after its alias (for example `cove-agent-sandbox.local`), and
5. tells Cove which user it set up.

Changed the **sudo** option later? Run the same command in the VM again.

### Step 4 · Connect from your Mac

Cove shows the VM's **IP address**, whether **SSH** is **Reachable**, and the **User**. Click **Open in Terminal**
to connect, or copy the command shown.

Until you finish step 5, the command is a long one that points at Cove's key. That's fine for trying it out.

### Step 5 · Let Terminal and your agents use it

Click **Add Cove to ~/.ssh/config…**. A file picker opens at your `.ssh` folder (a hidden folder in your home
folder where SSH keeps its settings). Click **Add Cove**. If you don't have a `.ssh` folder, choose your home
folder instead.

Cove then:

- copies its key to `~/.ssh/cove/`,
- writes `~/.ssh/cove/config` with a `cove-<name>` entry for each VM that has SSH access on — and keeps the
  VM's address up to date when it changes, and
- adds one line to the top of `~/.ssh/config`: `Include ~/.ssh/cove/config`.

Now `ssh cove-<name>` works everywhere on your Mac while the VM is running:

```sh
ssh cove-agent-sandbox 'sw_vers'                       # run a command
scp ./build.zip cove-agent-sandbox:~/                  # copy a file in
rsync -az ./project/ cove-agent-sandbox:~/project/     # sync a folder
```

The alias is `cove-` plus the VM's name in lowercase, with spaces and symbols turned into dashes:
“Agent Sandbox” becomes `cove-agent-sandbox`.

## Tell your agent about the VM

Your agent won't know the VM exists until you tell it. In step 5, click **Copy Instructions** and paste them
into your project's `CLAUDE.md` (Claude Code) or `AGENTS.md` (Codex and others). They look like this:

```md
## Sandbox VM (Cove)

A disposable macOS 27.0.1 virtual machine named “Agent Sandbox” is available for running code in isolation.

- Run commands in it over SSH: `ssh cove-agent-sandbox '<command>'` (user `you`, non-interactive key auth).
- Copy files: `scp ./file cove-agent-sandbox:~/` and `scp cove-agent-sandbox:~/path ./`, or `rsync -az ./dir/ cove-agent-sandbox:~/dir/`.
- `sudo` works without a password inside the VM.
- Prefer doing risky or system-level work (installs, config changes, untrusted code) in the VM, not on the host.
- The VM can be reset by restoring a snapshot in Cove — ask the user before assuming it is clean.
```

The copied text matches your VM: its name, macOS version, user, `sudo` setting and any shared folders.

> [!IMPORTANT]
> With this setup the agent program itself still runs **on your Mac**, with whatever access you've given it
> there. Only the commands it sends over SSH run in the VM. For the strongest separation, install and run the
> agent **inside** the VM — see the [personal assistant guide](personal-assistant.md).

## A safe routine for agent runs

1. **Take a snapshot first.** In step 5, under **Before letting an agent loose**, click **Take Snapshot**. (It's
   named “Before agent run”.)
2. **Let the agent work** in the VM.
3. **Reset when you're done:** shut down or suspend the VM, open **Virtual Machine ▸ Show Snapshots** (⌥⌘S),
   choose the snapshot and click **Restore**. Cove saves the current state first, so nothing is lost by accident.

After a restore the VM keeps the same SSH setup, so `ssh cove-<name>` keeps working. (If you restore a snapshot
taken *before* you ran the setup command, run it again.)

## Sharing project files

You can work two ways:

- **Copy files in and out** with `scp` or `rsync` (above). Your Mac's copy stays untouched until you copy results
  back. This is the safest option.
- **Share a folder.** In **Virtual Machine ▸ Settings… ▸ Sharing**, click **Add folder…**. In the VM it appears
  at `/Volumes/My Shared Files/<folder name>`. Choose **Read only** to stop the VM changing your files.

> [!WARNING]
> A **Read & write** shared folder is your real folder on your Mac. Anything the agent changes or deletes there
> is changed on your Mac too, and restoring a snapshot doesn't undo it.

## Troubleshooting

| What you see | What to do |
|---|---|
| **Not reachable yet — Remote Login may be off** | Make sure the VM is running and has finished starting up, then run the setup command again (step 3). |
| `/Volumes/My Shared Files/Cove` doesn't exist | SSH access was turned on while the VM was running. Restart the VM. |
| **Waiting for an address…** | The VM is still starting, or its network is set to **Disconnected**. Set **Network** to **Shared (NAT)** in **Settings… ▸ Network**. |
| `Permission denied (publickey)` | The setup command was run as a different user. Run it again while signed in as the user you want agents to use. |
| `ssh: Could not resolve hostname cove-…` | Step 5 isn't done, or the alias is different — check the name shown next to the VM's title in the walkthrough. |
| Host key warning after cloning a VM | Clones get their own alias. Remove the old lines for that alias from `~/.ssh/cove/known_hosts`. |
| `sudo` asks for a password | Tick **Let agents use sudo without a password** in step 3, then run the setup command in the VM again. |

More help: [Troubleshooting](troubleshooting.md#ssh-isnt-reachable).

## For developers

**How the pieces fit together**

- **Key.** One `ed25519` key pair per Cove library, created with `ssh-keygen` and stored in
  `<Library>/SSH/cove_ed25519`. Only the public key is put in the VM.
- **Guest folders.** With SSH access on, the VM gets two virtio-fs shares, automounted under
  `/Volumes/My Shared Files/`:
  - `Cove` (the bundle's `Guest/` folder) — **read-only** in the VM: `setup.sh`, `cove_ed25519.pub`, `README.txt`.
    The guest can't change the script or the key it installs.
  - `Cove Status` (the bundle's `GuestStatus/` folder) — the only place the guest can write. `setup.sh` reports
    the user name (`user`) and setup time (`configured`) there.

  The guest runs the script with `sh` because a sandboxed app can't clear quarantine on files it writes.
- **The VM is untrusted.** Everything Cove reads from it is validated before use: the user name must be a plain
  macOS short name (no spaces, line breaks or symbols), the status file must be a small regular file (not a link),
  and every value written into `~/.ssh/cove/config` is a single safe token. Share folders are never symlinks, and
  imported `.cove` bundles containing links are refused.
- **setup.sh** enables `sshd` through `launchctl` (and `systemsetup -setremotelogin on` when allowed), appends
  the key to `~/.ssh/authorized_keys`, writes or removes `/etc/sudoers.d/cove`, and sets `LocalHostName` to the
  alias.
- **IP address.** Each VM has a fixed, locally administered MAC address. Cove reads macOS's NAT DHCP lease table,
  `/private/var/db/dhcpd_leases` (a read-only sandbox exception), to find the VM's current `192.168.64.x` address.
- **Reachability.** A TCP probe of port 22 every 4 seconds while the VM runs.
- **Host config.** After you grant access to `~/.ssh` (a security-scoped bookmark), Cove writes
  `~/.ssh/cove/config` with one block per VM:

  ```sshconfig
  Host cove-agent-sandbox
    HostName 192.168.64.6
    User you
    IdentityFile ~/.ssh/cove/cove_ed25519
    IdentitiesOnly yes
    HostKeyAlias cove-agent-sandbox
    StrictHostKeyChecking accept-new
    UserKnownHostsFile ~/.ssh/cove/known_hosts
    ServerAliveInterval 30
    ConnectTimeout 5
  ```

  It's regenerated when a VM's IP or user changes. The `Include` line is placed at the top of `~/.ssh/config`
  so it isn't swallowed by an earlier `Host` block.

**Scripting tips**

- Use non-interactive commands: `ssh cove-<name> 'cd ~/project && make test'`.
- `ConnectTimeout 5` means a stopped VM fails fast; start it from Cove first (two macOS VMs can run at once).
- Restoring a snapshot keeps the guest's SSH host key, so `known_hosts` stays valid.

**Removing it**

Turn off **SSH & agent access** for each VM. To remove the host side, delete `~/.ssh/cove/` and the
`Include ~/.ssh/cove/config` line (with the `# Added by Cove` comment above it) from `~/.ssh/config`.
