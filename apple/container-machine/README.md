# Apple [Container machine](https://github.com/apple/container/blob/main/docs/container-machine.md)

Provision [Apple `container`](https://github.com/apple/container) [Container machines](https://github.com/apple/container/blob/main/docs/container-machine.md) with NixOS - generic and dotfiles-agnostic.

Each supported OS is a **flavor directory** under `apple/container-machine/`. The NixOS flavor is [`nixos/`](./nixos/), and its image build boots into a **switchable NixOS host**:

- [`nixos/`](./nixos/) - builds the OCI archive the machine boots. Initially `container`'s built-in provisioning supplies the login user + `/home` and boot services give that user a working `PATH` + `wheel`/`sudo`. The host is then `nixos-rebuild` switchable like OrbStack/`launchpad` (`user.nix` + `configuration.nix` via `bootstrap/foundation/nixos/switch.sh`). Build on a Linux box (`build.sh`) or inside an Apple `container` sandbox (`build-on-container.sh`) - no Lima VM needed. [`Makefile`](./nixos/Makefile) is the recommended entry point.

Flow: build the image, create the machine, shell in, then `nixos-rebuild switch` - done. See [`nixos/README.md`](./nixos/README.md) for the user model, compat shims, disk footprint, and clean-up.

## Troubleshoot

Symptoms first, then the fix. All verified on `container` CLI 1.5.0 (macOS 27).

### Upgraded the CLI but everything still behaves like the old version

- Symptoms:
  - `container system status` reports mismatched `client.version` / `server.version`.
  - Builds fail with DNS and TCP timeouts inside `container build` while running machines on the same network work fine.
  - Machine boots fail with `Operation not supported by device`.
  - `ps` shows plugin binaries running out of an old install path.
- Cause: the launchd service plists under `~/Library/Application Support/com.apple.container/` (in `apiserver/`, `plugin-state/*/`, `containers/buildkit/`, `networks/default/`) hardcode the install path from when each service was first created, and old servers stay up across CLI upgrades.
- Fix:

  ```sh
  container system stop
  # bootout any service still running, then repoint every plist that
  # references the old version (e.g. installs/container/1.3.0/) to the
  # current install (installs/container/latest/), and finally:
  container system start
  container system status   # server.version must match client.version
  ```

### Builds die partway through a heavy step with no useful error

- Cause: `container build` gives the buildkit sandbox only 2 CPUs / 2G by default; nix unpacks and home-manager evals OOM there.
- Fix: pass explicit resources - `container build -c 4 -m 8G ...`.
- Alternative: the [nixos flavor](./nixos/) sidesteps `container build` entirely and runs the build in a plain container sandbox with 4 CPUs / 6G - see [`nixos/bin/build-on-container.sh`](./nixos/bin/build-on-container.sh).

### The build sandbox has no outbound network, but machines are fine

Two known causes, in the order to check them:

- Version skew (the section above): the builder runs the old runtime. Fix the services first.
- A VPN/advanced-network-config default-route conflict blackholes NAT on the default vmnet network. Build on a freshly created network instead: `CONTAINER_BUILD_NETWORK=fresh` in `nixos/bin/build-on-container.sh`.

### A network test inside a build looks fine but installs find nothing

- Trap: `apt-get update` exits 0 even when every mirror fails, so `apt-get update && echo OK` proves nothing.
- Do this instead:
  - DNS: `getent hosts archive.ubuntu.com`
  - TCP: `bash -c 'echo >/dev/tcp/archive.ubuntu.com/80'`
  - Or simply install a package for real.

### Disk keeps growing after builds

Two culprits, both under `~/Library/Application Support/com.apple.container/`:

- The buildkit container's writable layer holds the whole build cache (tens of GB after a full image build). Reclaim between infrequent builds:
  - `container stop buildkit && container delete buildkit`
  - It auto-recreates; the next build starts cold.
- Rebuilt images re-imported under the same tag can leave orphaned snapshots of old digests (10 to 20G each) in `snapshots/`. After a rebuild:
  - `container image list` - check for duplicate tags.
  - Delete the stale image entries.

### Machine lifecycle papercuts

- No `machine start` subcommand: a stopped machine boots on the next `machine run`.
- Machines created with `--no-boot` cannot be booted by `run` (fails with `Operation not supported by device`).
- `machine run` flattens its arguments through a shell, so every argument must be a single word; run compound commands through piped stdin with `-i` instead.
