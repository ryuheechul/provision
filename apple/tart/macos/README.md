# tart/macos

macOS inside a [tart](https://github.com/cirruslabs/tart) VM. Like the
[`nixos`](../nixos/) flavor, tart runs only on Apple Silicon
(Virtualization.framework).

Unlike [`nixos`](../nixos/) (which boots an installer ISO and expects a manual
install), this clones a prebuilt vanilla macOS image from Cirrus Labs, so it
boots ready to use - no installer, no Setup Assistant.

## Usage

    make run              # pull (first call) + clone the vanilla image, boot it
    make run-vnc          # same, but hand the display to Screen Sharing
    make run-headless     # same, no window; `tart ip` then ssh in
    make service-install    # register `tart run --vnc` as a per-user service
    make service-stop       # stop the VM, keeping the service registered
    make service-start      # boot it again via the registered service
    make service-status     # loaded / unloaded / differs / missing
    make service-uninstall  # unload and remove that service
    make delete           # remove the VM, keep the downloaded base image
    make clean            # also remove the base image

Resources default to 4 CPUs / 8 GiB; override them at create time:

    make delete
    make run cpu=8 memory=16384

The guest defaults to `golden-gate` (macOS 27, matching the host); choose
another codename at create time:

    make delete
    make run codename=sequoia

## Autostart service

[`mise.toml`](./mise.toml) declares a per-user service (a macOS LaunchAgent)
under `[bootstrap.macos.launchd.agents]`. `make service-install` renders it to
`~/Library/LaunchAgents/dev.mise.tart-macos.plist` and loads it into the
`gui/<uid>` domain, where it runs:

    tart run --vnc macos-vm

`--vnc` resolves the guest IP and opens `vnc://<ip>` in the host's Screen
Sharing app, which needs the desktop (Aqua) session - so this is a LaunchAgent
and starts at login, not at boot. For a host that reboots unattended, enable
automatic login; without a desktop login the VM does not start.

    make service-install     # trust mise.toml + apply the service (starts the VM)
    make service-stop        # stop the VM, keep the service registered
    make service-start       # boot it again through the registered service
    make service-status      # loaded / unloaded / differs / missing
    make service-uninstall   # unload and remove the service

Notes:

- Installing starts the VM immediately. If `make run-vnc` is already running
  it, the launch exits with "already running" and retries every 60 s until the
  other instance stops.
- `keep_alive_on_failure` retries a boot that fails (for example tart's 60 s
  wait for the guest IP expiring); a clean guest shutdown exits 0 and is not
  retried until the next login or `make service-start`.
- `make service-stop` runs `tart stop` (guest shutdown, `SIGKILL` after 30 s) and
  leaves the service registered; tart exits 0, so launchd does not relaunch it.
  `make service-start` kickstarts the loaded job, and fails with a hint if the
  service is not installed.
- Do not add `--no-graphics` to the service's args: combined with `--vnc` it
  prints the VNC URL instead of opening Screen Sharing.
- Logs: `~/Library/Logs/tart-service-macos-vm.log` and
  `tart-service-macos-vm.err.log`.
- `tart` is resolved with `command -v` when the service is installed and baked
  into the plist, so re-run `make service-install` if the binary moves. Running
  `mise bootstrap` directly falls back to mise's default data dir and its
  `latest` symlink.
- `make service-uninstall` unloads the job, which stops the tart process launchd
  started. Run `make service-stop` first for a graceful guest shutdown.
- The service is declared in this directory's config, so `make service-install`
  must run here; from the repo root use
  `mise -C apple/tart/macos bootstrap macos launchd-agents apply`.
- `make delete` does not remove the service. Uninstall it first, or the service
  fails at the next login until the VM is recreated with the same name.

## Notes

- Image: `ghcr.io/cirruslabs/macos-<codename>-base:latest` - vanilla macOS with
  SSH enabled and the `admin` / `admin` account.
- `tart clone` is copy-on-write under the hood: the VM claims almost no extra
  space until written, and every clone shares the base image's blocks.
- The codename is fixed when the VM is cloned, so `make delete` before
  switching; resources can also be changed later with `tart set`.
- The ASIF disk image grows with guest writes and shrinks again when files are
  deleted - freed blocks go back to the host (verified: a 1 GiB write grew
  `disk.img` by ~1 GiB, and deleting it returned that space).
- `tart` comes from `PATH` (mise, Nix, ...). It is declared in the repo's
  [`mise.toml`](../../../mise.toml), so `mise install` at the repo root is the
  simplest setup; `make run` stops with a hint if it is missing.

## Troubleshoot

### `make run` boots the VM but no window appears

`tart run` needs the desktop (Aqua) session to present its window. A shell
inside a terminal multiplexer (`tmux`, `screen`, `zellij`) that lives in a
non-Aqua launchd session has none, so the VM boots headless: the window is
created but never shown. Check with `launchctl managername` - `Aqua` is fine,
`Background` means headless.

Run `make run` from a plain terminal window (outside the multiplexer), or use
`make run-headless` and ssh in.

The same applies to the [`nixos`](../nixos/) flavor, also driven by `tart run`.

### Use Screen Sharing instead of tart's window

`make run-vnc` (`tart run --vnc`) hands the display to the macOS Screen Sharing
app instead of tart's built-in window - worth it for copy/paste and
drag-and-drop. The [autostart service](#autostart-service) uses this same mode, so
after a login the VM is running with Screen Sharing already opened. The Cirrus
image already has Screen Sharing and Remote Login enabled, so a VM that is
already running headless can also be reached directly:

    open vnc://$(tart ip macos-vm)

or Finder -> Go -> Connect to Server -> `vnc://<ip>`. Log in as `admin` /
`admin`.

### `sandbox_extension_issue_file_to_process` warning

With mise, `tart` lives under a `latest` -> `<version>` symlink, and launching
it through that symlink can print:

    sandbox_extension_issue_file_to_process failed: (Operation not permitted)

This is macOS declining to grant the spawned child a sandbox extension for the
app bundle: the symlinked path does not match the bundle the kernel expects, so
it returns `EPERM`. tart logs it and continues without the extension. Nothing
in the VM's operation relies on that grant - boot, disk and network worked with
the warning present - so it is a warning, not an error. Resolving `tart` to its
real path silences it, but the Makefile calls `tart` as-is rather than carrying
that path logic.

