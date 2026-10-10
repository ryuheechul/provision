# tart/nixos

Running NixOS inside a [tart](https://github.com/cirruslabs/tart) VM - tart's
`--linux` mode is macOS-only (Virtualization.framework), like everything else
in this repo.

## Usage

    make run     # first call: install tart from nixpkgs, fetch the channel ISO
                 # and boot it; install NixOS manually inside the tart window
                 # and power off - make then boots the VM disk, and later
                 # `make run` calls go straight to it
    make delete  # remove the VM; the downloaded ISO stays so a recreate
                 # skips the fetch

The ISO (`nixos-<channel>.iso`) and the make markers are gitignored: they are
per-machine state, and the ISO alone is multiple GB.
