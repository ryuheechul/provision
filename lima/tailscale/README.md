# tailscale

A sole purpose of this machine is to run tailscale via [lima](../).

## Why?

Tailscale on macOS [seems to disconnect when switching between user accounts](https://github.com/tailscale/tailscale/issues/594).
Thus, unreliable to run it on macOS host level for my use case.

Using this lima vm + `ssh host.lima.internal` from the vm should allow to workaround that situation.

## Provision

> installing tailscale is taken care by [config.yaml](./config.yaml)

`LIMA_INSTANCE=my-tailscale make start`

## Access
> in case exited the shell
`LIMA_INSTANCE=my-tailscale make enter`

## Run Tailscale

```bash
# inside the vm
$ sudo tailscale up
# or
$ make tailscale
```

### More commands
at [Makefile](./Makefile)


### Access Mac Host From a Remote Machine

#### Diagram
```mermaid
flowchart TD
    remote-machine -- direct ssh --> lima-guest
    remote-machine -- ssh via --> lima-guest-as-jump-server
    lima-guest -- direct ssh --> macOS-host
    lima-guest-as-jump-server -- for `remote-machine` --> macOS-host
    macOS-host -- spawns --> lima-guest
```

```ssh-config
# given ~/.ssh/config on a remote machine
# (being used to connect the macOS host running lima guest)
# with following example config

Host *
  # optional but this allows you to keep using public/private keys
  # on local machine without having to move it to the jump host
  ForwardAgent yes

  # optional and useful if adding keys are not done from a shell already
  AddKeysToAgent yes

  # optional but you maybe want to reduce the payloads on the network
  Compression yes

Host actual-host
  HostName host.lima.internal # perspective from lima
  ProxyJump remote-lima-guest
  User my-username

# since tailscale is running on this layer
Host remote-lima-guest
  # should match to the name in your tailscale, alternatively use ip
  HostName lima-my-tailscale
  User my-username
```

`ssh remote-lima-guest` should let you connect to the lima guest directly given the lima guest and remote machine both are connected by tailscale.

`ssh actual-host` should let you connect to the macOS host via lima-guest by [SSH jump host](https://wiki.gentoo.org/wiki/SSH_jump_host)

> adding a public key of the remote machine to `~/.ssh/authorized_keys`, would let you avoid typing password of the account of the target machine

### Caveats
Resource spec at [./config.yaml](./config.yaml) is still probably an overkill and not terribly optimized yet.

macOS host by default would turn into sleep mode when display is off unless a setting like below to be turned on.

_Prevent automatic sleeping on power adapter when the display is off_

[Go here](https://gist.github.com/ryuheechul/3918366306f6b7f02c250dcb0cbee4ec#prevent-ssh-disconnection) for more on that.
