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
    make delete           # remove the VM, keep the downloaded base image
    make clean            # also remove the base image

Resources default to 4 CPUs / 8 GiB; override them at create time:

    make delete
    make run cpu=8 memory=16384

The guest defaults to `golden-gate` (macOS 27, matching the host); choose
another codename at create time:

    make delete
    make run codename=sequoia

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
drag-and-drop. The Cirrus image already has Screen Sharing and Remote Login
enabled, so a VM that is already running headless can be reached directly:

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

