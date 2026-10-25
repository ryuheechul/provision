# Adapting to upstream `container` changes

This repo tracks breaking `container` runtime changes that affect how the
guest NixOS image is built and how existing machines are kept bootable.
Adapting has two aspects:

1. **Change how we build the image** — fresh machines created from the new
   image must carry whatever the new runtime expects.
2. **Restore an existing unbootable machine** — a machine created before the
   fix may refuse to boot under the new runtime; you cannot log in to repair
   it, so recovery must happen from outside the guest.

The single source of truth for both aspects is
[`machine-configuration/user-setup-tools.nix`](../machine-configuration/user-setup-tools.nix):
one command list that flows into the image `/bin` graft and the persistent
`/usr/local/bin` activation links.

---

## 1.5 -> 1.6

`container` 1.6 changed user setup from a one-time
`/sbin.machine/init -u` (guarded by `machine.initialized`) to a host-driven
`/bin/sh -c <embedded script>` exec on **every boot**, run before stage-2
activation links `/run/current-system`, with

```
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

NixOS keeps every command that script calls (`getent`, `date`, `mkdir`,
`cp`, `chmod`, `tr` — plus the existing `chown`, `cut`, `grep`, `id`) in the
system profile only, so none of them resolve on that PATH. The setup then
reads empty passwd lookups and refuses the home it created on an earlier
boot:

```
container machine: refusing to use existing path '/home/<user>' as the
home directory for user '<user>'
```

### a) Change how we build the image (fresh machines)

Update the command list in
[`machine-configuration/user-setup-tools.nix`](../machine-configuration/user-setup-tools.nix).
That one file flows into both places:

- **Image `/bin` graft** ([`image/common.nix`](../image/common.nix)):
  `make-rootfs.sh` symlinks each command into `/bin` at image build time. A
  machine created from the new image has the commands available before any
  activation, which is exactly when 1.6's setup runs.
- **Persistent `/usr/local/bin` links**
  ([`machine-configuration/users.nix`](../machine-configuration/users.nix)): an
  activation script (`containerMachineUserSetupTools`) links the same
  commands into `/usr/local/bin` on every switch and boot. This repairs
  machines created from an older image that lacks the `/bin` graft —
  `/usr/local/bin` is first on the runtime PATH and survives reboots,
  unlike `/bin/sh` which NixOS relinks at activation.

Then rebuild and republish (`make build`, `make publish`), and existing
machines self-repair on their next `make switch`. Fresh creates pick up the
`/bin` graft immediately.

### b) Restore an existing unbootable machine (already created)

A machine created before the fix will not boot under 1.6: setup runs before
you have guest access and stops the machine on failure, so you cannot log in
to install tools. Recovery:

1. Boot the machine once under an older `container` (e.g.
   `mise install container@1.5.0`, then
   `mise exec container@1.5.0 -- container system start`). The older runtime
   skips setup because `/etc/.machine.initialized` exists, so the machine
   comes up with its account and `/home` intact.
2. Inside the guest, make the setup commands reachable on the new runtime's
   minimal PATH. Link each command to its **absolute store path** (not
   `/run/current-system/...`, which disappears after activation):

   ```sh
   ln -sfn "$(readlink -f "$(command -v getent)")" /usr/local/bin/getent
   ```

   for each of `getent`, `date`, `mkdir`, `cp`, `chown`, `chmod`, `tr`,
   `cut`, `grep`, `id`.
3. Stop the older runtime stack (`container system stop`; if services linger,
   `launchctl bootout gui/501/<label>`), start the new runtime
   (`container system start`), and cold-boot the machine — 1.6's every-boot
   setup now finds its commands and no-ops on the existing account.
4. Once you have applied this repo's fix to the machine — sync the updated
   `machine-configuration/` (which now contains `user-setup-tools.nix` and the
   `containerMachineUserSetupTools` activation script) with `make sync-config`,
   then run `make switch` — the `/usr/local/bin` links are recreated by
   activation on every boot and switch, and refreshed to point at the current
   generation's store paths. Until then they remain manual symlinks tied to
   the one generation they were installed under (valid until a guest GC
   collects those store paths).

### Cross-version control

After any fix, fresh-create a scratch machine under both the old and new
runtime and confirm `container machine run` succeeds on both. That control
is what validated this 1.5 -> 1.6 adaptation (fresh create under 1.6.1,
fresh create under 1.5.0 via `mise`, and a cross-version boot of the
1.5-created machine under 1.6.1).

---

## Template for the next breaking change

When a future `container` version changes setup again:

1. Read the new embedded setup script (extract it from the new
   `machine-apiserver` resources) and list every external command it invokes.
2. Add the new commands to
   `machine-configuration/user-setup-tools.nix`, keeping the old ones unless
   the new script no longer needs them.
3. Confirm each command exists on `pkgs` for `aarch64-linux` (the image
   target) — `pkgs.coreutils`, `pkgs.getent`, `pkgs.gnugrep`, etc.
4. Rebuild (`make build`), fresh-create under both versions, and document
   the transition here under a new version heading.
