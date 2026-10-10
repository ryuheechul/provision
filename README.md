# provision
Where I write code to provision (probably just) Virtual Machines that hopfully is useful.

Currently there is:

- [apple/container-machine/nixos](./apple/container-machine/nixos) - NixOS config for an Apple [Container machine](https://github.com/apple/container/blob/main/docs/container-machine.md)
- [lima](./lima) - Provision VMs with [Lima](https://github.com/lima-vm/lima)
  - [lima/dev](./lima/dev) - Dev VM on Lima's default template
  - [lima/nixos](./lima/nixos) - NixOS inside a Lima VM (reference for comparing against the [container machine](./apple/container-machine/nixos))
  - [lima/tailscale](./lima/tailscale) - Tailscale inside a Lima VM
  - [lima/screenshare](./lima/screenshare) - VNC VM working around `open vnc://` on macOS
- [tart/nixos](./tart/nixos) - NixOS inside a [tart](https://github.com/cirruslabs/tart) VM
