# SSH & agent access

Use a Cove VM as a disposable sandbox that **you** and **coding agents on your Mac** (Claude Code, Codex,
Cursor, scripts…) can reach over SSH: `ssh cove-<vm-name> '<command>'`.

In the app: select a VM ▸ **SSH & Agent Access…** (⇧⌘K, the console toolbar's SSH button, or the VM's
context menu). The window walks through the same steps as below and shows live status for each one.

## 1. Turn on SSH access

Flip **SSH access** on for the VM. Cove then:

- creates one SSH key for your library (`ed25519`, kept in Cove's container), and
- attaches a small **Cove** shared folder to the VM containing the public key and a setup script.

The folder is a virtual device, so if the VM is running it appears after a restart.

## 2. Start the VM and finish Setup Assistant

Create your macOS user in the VM as usual.

## 3. Run the setup command inside the VM

Open **Terminal in the VM** and type (copy-paste between your Mac and a macOS VM isn't available):

```sh
sh "/Volumes/My Shared Files/Cove/setup.sh"
```

Enter your VM password when asked. The script:

1. turns on **Remote Login** (SSH),
2. adds Cove's public key to `~/.ssh/authorized_keys`,
3. optionally allows **passwordless `sudo`** (if you ticked *Let agents use sudo without a password* — agents
   can't type passwords), and removes that rule if you didn't,
4. sets the VM's local host name to the alias (e.g. `cove-smoke-test.local`), and
5. tells Cove which user it ran as.

Change the sudo option later? Re-run the same command.

## 4. Connect from your Mac

The walkthrough shows the VM's IP (from macOS's built-in NAT, `192.168.64.x`), whether SSH is reachable, and
the exact command. **Open in Terminal** connects for you.

## 5. Let Terminal and agents use `ssh cove-<name>`

Click **Add Cove to ~/.ssh/config…** and choose your `~/.ssh` folder (or your home folder). Cove:

- copies its key to `~/.ssh/cove/cove_ed25519`,
- writes `~/.ssh/cove/config` with a `Host cove-<name>` entry per VM (user, key, current IP — refreshed
  automatically when the IP changes), and
- adds one line to the top of `~/.ssh/config`: `Include ~/.ssh/cove/config`.

Now anything on your Mac can use the VM:

```sh
ssh cove-smoke-test 'sw_vers'
scp ./build.zip cove-smoke-test:~/
rsync -az ./project/ cove-smoke-test:~/project/
```

### Tell your agent about it

Copy **Agent instructions** from the walkthrough into your project's `CLAUDE.md` / `AGENTS.md`. It looks like:

```md
## Sandbox VM (Cove)

A disposable macOS 27 virtual machine named “Smoke Test” is available for running code in isolation.

- Run commands in it over SSH: `ssh cove-smoke-test '<command>'` (user `arnav`, non-interactive key auth).
- Copy files: `scp ./file cove-smoke-test:~/` and `scp cove-smoke-test:~/path ./`, or `rsync -az ./dir/ cove-smoke-test:~/dir/`.
- `sudo` works without a password inside the VM.
- Prefer doing risky or system-level work (installs, config changes, untrusted code) in the VM, not on the host.
- The VM can be reset by restoring a snapshot in Cove — ask the user before assuming it is clean.
```

### Sandbox workflow

1. Take a snapshot first (**Take Snapshot** in the walkthrough → “Before agent run”).
2. Let the agent work in the VM.
3. Reset by restoring the snapshot (Snapshots window ▸ Restore). Cove auto-saves the current state first, and
   the VM keeps the same SSH host key and user, so `ssh cove-<name>` keeps working.

Share a project folder into the VM (VM Settings ▸ Sharing) if you want the agent to edit host files directly —
it appears at `/Volumes/My Shared Files/<folder>`. Mark it read-only to keep the host copy safe.

## Troubleshooting

| Symptom | Fix |
|---|---|
| “Not reachable” | Remote Login is off — re-run the setup command; make sure the VM is running and finished booting. |
| `Permission denied (publickey)` | Setup ran as a different user than the one in `~/.ssh/cove/config`; re-run setup as the user you want. |
| `/Volumes/My Shared Files/Cove` missing | SSH access was turned on while the VM was running — restart the VM. |
| Host key changed warning after cloning a VM | Clones get their own alias; remove stale lines from `~/.ssh/cove/known_hosts`. |
| No IP shown | The VM hasn't requested a network address yet (still booting) or its network is set to Disconnected. |

## How it works (for the curious)

- **IP lookup**: Cove gives every VM a fixed MAC address and reads macOS's NAT DHCP lease table
  (`/var/db/dhcpd_leases`, a read-only sandbox exception) to find its current IP.
- **Reachability**: a TCP probe of port 22 every few seconds while the VM runs.
- **Keys** never leave your Mac; the VM only receives the public key.
