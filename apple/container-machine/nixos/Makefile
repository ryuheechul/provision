# Make targets for building and launching an Apple `container` container-machine
# from the NixOS image in this directory. A convenience wrapper over the scripts
# in bin/, which also work directly from any directory; targets without a
# script (clean, recreate, delete, sync-config, switch, restore-config, the
# example switch-* targets, status) live here.
#
#   make build         # build the OCI archive (Apple `container` sandbox)
#   make build-context # alternate: Dockerfile context for container build (fallback)
#   make publish       # push the built image to ghcr.io/ryuheechul/provision/nixos-cm
#   make launch        # load the image + create the machine (create-if-missing)
#   make run           # shell in as the machine user
#   make root          # root shell
#   make wait-exec    # boot (if needed) + wait until exec works (not stage-2)
#   make wait-ready   # wait until stage-2/systemd/nix-daemon are up (switch gate)
#   make status        # key facts about the running config
#   make dns           # machine DNS check: <name>.machine -> IP match
#   make dns-set       # register the machine DNS domain (sudo)
#   make dns-rm        # unregister the machine DNS domain (sudo)
#   make switch        # apply machine-configuration/ to the running machine
#   make fstrim        # reclaim host disk for blocks freed in the guest
#   make kvm-kernel    # build the pinned KVM-capable kernel (cached in XDG cache)
#   make enable-kvm    # apply kernel + virtualization=true (restarts; state kept)
#   make disable-kvm   # undo: default kernel + virtualization=false (restarts)
#   make kvm-verify    # in-guest check: kernel, EL2, /dev/kvm, CONFIG_KVM
#   make kvm-test-create # scratch KVM machine (alpine + kernel); kvm-test runs the L1 smoke
#   make kvm-test      # L1 smoke on the scratch machine (strict -enable-kvm L2 boot)
#   make kvm-test-clean # delete the scratch test machine (confirms)
#   make clean         # remove build artifacts + loaded image + ALL stopped containers (prune is unfiltered; leaves the machine)
#   make recreate      # DELETE the machine + re-create it (DESTROYS state; confirms)
#   make delete        # DELETE the machine + its state, no recreate (DESTROYS; confirms)
#   make help
#
# The bottom of this file holds everything that applies config: sync-config,
# switch, then the TEST-only example switches (switch-nonflake,
# switch-nonflake-baked, switch-flake, switch-flake-live, + restore-config)
# that exercise examples/ against either base.
#
# The machine is STATEFUL: /home/<user> and anything switched in persist on its
# disk (rootfs.ext4). `launch` never touches the machine. `clean` removes build
# artifacts + the loaded image + ALL stopped containers (`container prune` has
# no name/label filter). Only recreate/delete remove a machine, and both ask
# for confirmation first.

# Machine name (single canonical name, also used by launch.sh). Set it on the
# make command line (`make run MACHINE_NAME=foo`) or as an env var.
MACHINE_NAME ?= nixos-cm
# Image tag (single host-side default; passed through to launch.sh). Matches
# image/default.nix imageName:imageTag. Override: `make launch IMAGE=other:tag`.
IMAGE        ?= local/nixos-cm:latest
# Source tree for sync-config (the live overlay written into the guest).
HOST_BASE    := $(CURDIR)/machine-configuration
# Example configurations (switch-nonflake / switch-flake). Host paths, read in
# the guest via the machine's --home-mount rw.
HOST_EXAMPLES := $(CURDIR)/examples

# Nested virtualization (KVM): a KVM-capable kernel built from apple/
# containerization at a pinned ref, parked in the XDG cache under this repo
# own namespace (provision-cm, not the runtime own "container-machine" -
# machine kernel= points here). The filename carries kernel version + ref
# short so a ref bump misses the cache and rebuilds. KVM_KSRC matches
# kernel/Makefile's default KSOURCE; kernel/Makefile curls source.tar.xz
# (161M) on first build.
# KVM_DEFAULT_KERNEL is the CLI's own default-kernel symlink - the undo handle
# for enable-kvm, because `kernel=` (empty) is documented to reset but the
# parser rejects empty values.
KVM_REF            ?= 8be8e841e76960403ac2b126c737a7ac25bf090a
KVM_KSRC           ?= https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.18.5.tar.xz
KVM_CACHE          ?= $(or $(XDG_CACHE_HOME),$(HOME)/.cache)/provision-cm
KVM_SRC            := $(KVM_CACHE)/containerization
KVM_KERNEL         := $(KVM_CACHE)/kernels/vmlinux-arm64-6.18.5-cz-$(shell printf '%.12s' $(KVM_REF))
KVM_DEFAULT_KERNEL ?= $(HOME)/Library/Application Support/com.apple.container/kernels/default.kernel-arm64
# Scratch machine for cheap L1 KVM tests (alpine; see kvm-test-create below).
TEST_MACHINE       ?= kvm-test

.PHONY: help
help: ## Show all targets
	@grep -Eh '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  %-18s %s\n", $$1, $$2}'

# Build the OCI archive inside an Apple `container` sandbox running nixos/nix
# (no Lima VM needed on macOS). For a plain Linux box with nix, use build.sh.
.PHONY: build
build: ## Build the image archive (Apple `container` sandbox)
	./bin/build-on-container.sh

# Secondary packaging path: Dockerfile context for `container build .`.
# Not used by make build / launch; see image/oci.nix for when to reach for it.
.PHONY: build-context
build-context: ## Materialize Dockerfile context (manual fallback; nix-build -A buildContext)
	nix-build image -A buildContext -o build/build-context
	@echo "Context dir: $$(readlink -f build/build-context)"
	@echo "Usage: cp -L build/build-context /tmp/ctx && cd /tmp/ctx && container build -t $(IMAGE) ."

# Push the built archive to GHCR so `container machine create` can pull it
# without a local build (README: "Use the Prebuilt Image").
# Auth: a stored `skopeo login ghcr.io` (classic PAT) or GHCR_USER/GHCR_TOKEN
# env - details in bin/publish.sh.
.PHONY: publish
publish: ## Push build/ OCI archive to ghcr.io (latest + sha tag)
	./bin/publish.sh

# macOS side: load + create-if-missing; only --recreate / make delete destroy.
.PHONY: launch
launch: ## Load the image + create the machine (create-if-missing)
	IMAGE="$(IMAGE)" ./bin/launch.sh

# BY DELETING PERSISTED STATE first (wipes /home + switched-in config); reuses
# launch.sh --recreate (prompts). Address the prompt carefully.
.PHONY: recreate
recreate: ## Delete + re-create the machine (DESTROYS persisted state; confirms)
	IMAGE="$(IMAGE)" ./bin/launch.sh --recreate

# Separate, confirmation-gated destroy path (no recreate). Re-create later
# with `make launch`.
.PHONY: delete
delete: ## Delete the machine + its persisted state (DESTROYS; confirms)
	@read -p "Delete machine '$(MACHINE_NAME)' and ALL its persisted state (e.g. /home)? This cannot be undone. Type delete to confirm: " ans; \
	if [ "$$ans" = "delete" ]; then \
		container machine delete $(MACHINE_NAME); \
		echo "Deleted machine '$(MACHINE_NAME)'."; \
	else \
		echo "Aborted."; \
	fi

# Apple's init execs the passwd shell the instant the CLI connects - before
# stage-2 activation links /run/current-system - so a run in that window dies
# with a transient ENOENT on the shell path (see machine-configuration/shell.nix,
# which closes it only for bootstrap shells). Every target that execs into the
# machine waits here first: boots a stopped machine, then polls `run true`
# until exec works (costs one fast probe when already warm). Exec working is
# NOT stage-2 completion - systemd and the nix-daemon socket come up later,
# and `run true` says nothing about them (see wait-ready).
.PHONY: wait-exec
wait-exec: ## Boot (if needed) + wait until the machine accepts exec
	@container machine list 2>/dev/null | grep -qE '^$(MACHINE_NAME)([ \t]|$$)' || \
		{ echo "error: machine '$(MACHINE_NAME)' not found (make launch first)" >&2; exit 1; }
	@i=0; \
	while ! container machine run -n $(MACHINE_NAME) true >/dev/null 2>&1; do \
		i=$$((i+1)); \
		if [ $$i -ge 45 ]; then \
			echo "error: machine '$(MACHINE_NAME)' still not exec-able after 90s" >&2; \
			exit 1; \
		fi; \
		sleep 2; \
	done

# Gate for anything that runs nixos-rebuild inside the guest. Switching into
# the wait-exec-only window fails with "cannot connect to socket
# .../daemon-socket/socket: Connection refused" - a switch issued right after
# a reboot races stage-2. Requires all three: activation linked a real store
# path (the boot graft is current-system -> /), systemd answers on the bus,
# and the daemon responds. run/root/status stay on wait-exec so a machine
# with a broken stage-2 remains reachable for rescue and diagnosis.
.PHONY: wait-ready
wait-ready: wait-exec ## wait-exec + stage-2/systemd/nix-daemon all up
	@i=0; \
	while :; do \
		ready=1; \
		cur=$$(container machine run -n $(MACHINE_NAME) --root 'readlink /run/current-system 2>/dev/null' 2>/dev/null || true); \
		case "$$cur" in /nix/store/*) ;; *) ready=0 ;; esac; \
		if [ $$ready -eq 1 ]; then \
			st=$$(container machine run -n $(MACHINE_NAME) --root 'systemctl is-system-running 2>/dev/null' 2>/dev/null || true); \
			case "$$st" in running|degraded) ;; *) ready=0 ;; esac; \
		fi; \
		if [ $$ready -eq 1 ]; then \
			container machine run -n $(MACHINE_NAME) --root '. /etc/set-environment && nix store ping >/dev/null 2>&1' >/dev/null 2>&1 || ready=0; \
		fi; \
		[ $$ready -eq 1 ] && exit 0; \
		i=$$((i+1)); \
		if [ $$i -ge 60 ]; then \
			echo "error: machine '$(MACHINE_NAME)' never became ready (stage-2/systemd/nix-daemon) after 180s" >&2; \
			exit 1; \
		fi; \
		sleep 3; \
	done

# Open an interactive shell as the machine user / as root.
.PHONY: run
run: wait-exec ## Shell in as the machine user
	container machine run -n $(MACHINE_NAME)

.PHONY: root
root: wait-exec ## Shell in as root
	container machine run -n $(MACHINE_NAME) --root

.PHONY: current-system
current-system: wait-exec ## Show the linked system generation
	container machine run -n $(MACHINE_NAME) --root 'readlink /run/current-system || echo "not linked yet"'

.PHONY: status
status: wait-exec ## Show linked system + config source (overlay|baked) + count of failed units
	container machine run -n $(MACHINE_NAME) --root '\
		echo "current-system: $$(readlink /run/current-system)"; \
		echo "config source: $$(if [ -e /etc/nixos/machine-configuration ]; then echo overlay; else echo baked; fi)"; \
		echo "failed units: $$(systemctl list-units --state=failed --no-legend | wc -l)"; \
	'

# Confirm this repo's machine name and the guest's hostname still agree.
# Reporting only: apple/container cannot rename a machine, and this edits
# neither this repo nor the Nix code. See bin/check-machine-name.sh.
.PHONY: check-machine-name
check-machine-name: wait-exec ## Confirm the machine name and the guest's hostname agree
	MACHINE_NAME="$(MACHINE_NAME)" ./bin/check-machine-name.sh

# Only reclaims *free* blocks - delete first, then trim. Not destructive alone.
.PHONY: fstrim
fstrim: wait-exec ## Reclaim host disk for freed guest blocks
	container machine run -n $(MACHINE_NAME) --root 'fstrim -v /'

# Nested virtualization (KVM). One-time setup: build the kernel (kvm-kernel),
# point the machine at it (enable-kvm; restarts, state kept), then check
# inside the guest (kvm-verify). Needs Apple Silicon M3+ / macOS 15+: the CLI
# only passes /dev/kvm through when the machine boots with a CONFIG_KVM=y
# kernel AND virtualization=true. The kernel build compiles in an Apple
# `container` sandbox (kernel/Makefile: image + build.sh). Both settings live
# in the machine-level config: they survive stop/start but NOT recreate or
# delete (the machine comes back on the default kata kernel, no virtualization).
.PHONY: kvm-kernel
kvm-kernel: ## Build the pinned KVM-capable kernel into the cache (no-op if built)
	@mkdir -p "$(KVM_CACHE)/kernels"
	@if [ -f "$(KVM_KERNEL)" ]; then \
		echo "already built: $(KVM_KERNEL)"; \
	else \
		echo "building KVM kernel (Apple container sandbox; first build also fetches source.tar.xz)"; \
		{ [ -d "$(KVM_SRC)/.git" ] || git clone https://github.com/apple/containerization "$(KVM_SRC)"; } && \
		git -C "$(KVM_SRC)" checkout -q "$(KVM_REF)" && \
		$(MAKE) -C "$(KVM_SRC)/kernel" KSOURCE="$(KVM_KSRC)" && \
		cp "$(KVM_SRC)/kernel/vmlinux-arm64" "$(KVM_KERNEL)" && \
		echo "built: $(KVM_KERNEL)"; \
	fi

# Apply it to the machine: stop, set kernel + virtualization, boot again.
# `set` takes effect at the next boot; wait-exec boots a stopped machine and
# returns once it accepts commands. State persists across the restart.
.PHONY: enable-kvm
enable-kvm: kvm-kernel ## Stop, apply kernel= + virtualization=true, boot (state persists)
	container machine stop $(MACHINE_NAME) 2>/dev/null || true
	container machine set -n $(MACHINE_NAME) kernel="$(KVM_KERNEL)" virtualization=true
	@$(MAKE) wait-exec
	@echo "kvm enabled on '$(MACHINE_NAME)'; now: make kvm-verify"

# Undo handle for enable-kvm: back on the CLI's default kernel with
# virtualization off (same restart semantics; state persists). The reset goes
# through the default-kernel symlink since `kernel=` (empty) is rejected.
.PHONY: disable-kvm
disable-kvm: ## Restore the default kernel + virtualization=false (restarts)
	container machine stop $(MACHINE_NAME) 2>/dev/null || true
	container machine set -n $(MACHINE_NAME) kernel="$(KVM_DEFAULT_KERNEL)" virtualization=false
	@$(MAKE) wait-exec
	@echo "kvm disabled on '$(MACHINE_NAME)' (default kernel restored)"

# In-guest proof: custom kernel, EL2 entry, /dev/kvm (with udev mode), and
# CONFIG_KVM=y. Non-zero exit when /dev/kvm or the config flag is missing -
# exactly the two things a default-kernel machine lacks.
.PHONY: kvm-verify
kvm-verify: wait-exec ## Verify nested KVM in the guest (kernel, EL2, /dev/kvm, config)
	container machine run -n $(MACHINE_NAME) --root '\
		echo "kernel: $$(uname -r)"; \
		dmesg | grep -q "started at EL2" && echo "EL2: yes" || echo "EL2: not in dmesg ring (was seen at boot)"; \
		if [ -c /dev/kvm ]; then echo "/dev/kvm: $$(ls -l /dev/kvm)"; else echo "/dev/kvm: MISSING"; exit 1; fi; \
		if [ -r /proc/config.gz ]; then \
			zcat /proc/config.gz | grep -q "^CONFIG_KVM=y" && echo "CONFIG_KVM=y" || { echo "CONFIG_KVM not set"; exit 1; }; \
		else \
			echo "/proc/config.gz unreadable - skipping config check"; \
		fi \
	'

# Cheap L1 KVM lab: a throwaway alpine machine (TEST_MACHINE, default
# kvm-test) carrying the same KVM kernel, so boot/accel tests never touch
# the real machine. create = bring up + apply the kernel (via enable-kvm),
# test = the strict-KVM L2 boot inside it (bin/kvm-test.sh), clean = delete
# the scratch machine (its state is disposable by definition).
.PHONY: kvm-test-create
kvm-test-create: kvm-kernel ## Create the scratch KVM test machine (alpine) + apply the kernel
	@container machine list 2>/dev/null | grep -qE '^$(TEST_MACHINE)([ \t]|$$)' || \
		container machine create alpine:3.22 --name $(TEST_MACHINE) --cpus 2 --memory 2G
	@$(MAKE) enable-kvm MACHINE_NAME=$(TEST_MACHINE)

.PHONY: kvm-test
kvm-test: kvm-test-create ## L1 smoke on the scratch machine: strict -enable-kvm L2 boot
	TEST_MACHINE=$(TEST_MACHINE) ./bin/kvm-test.sh

.PHONY: kvm-test-clean
kvm-test-clean: ## Delete the scratch KVM test machine (confirms)
	@container machine list 2>/dev/null | grep -qE '^$(TEST_MACHINE)([ \t]|$$)' || \
		{ echo "scratch machine '$(TEST_MACHINE)' not found - nothing to clean"; exit 0; }; \
	read -p "Delete scratch test machine '$(TEST_MACHINE)' (test state only, disposable)? [y/N] " ans; \
	if [ "$$ans" = "y" ] || [ "$$ans" = "Y" ]; then \
		container machine stop $(TEST_MACHINE) 2>/dev/null || true; \
		container machine delete $(TEST_MACHINE); \
		echo "Deleted '$(TEST_MACHINE)'."; \
	else \
		echo "Aborted."; \
	fi


# DNS: bin/dns.sh matches every machine to the IP its <name>.machine resolves
# to. The suffix is fixed by apple/container (defaultDNSDomain = "machine" in
# MachineConfiguration.swift), so there is nothing to configure - README
# "DNS (Host Side)" has the source link and the full picture. dns-set/dns-rm
# register or unregister that one fixed `machine` domain (sudo; thin wrappers
# over `container system dns create|delete`) - no argument, neither can change
# the machine name suffix.
.PHONY: dns
dns: ## List DNS info + match each machine to its <name>.machine IP
	./bin/dns.sh

.PHONY: dns-set
dns-set: ## Register the machine DNS domain (sudo)
	sudo container system dns create machine

.PHONY: dns-rm
dns-rm: ## Unregister the machine DNS domain (sudo)
	sudo container system dns delete machine

# Transient artifacts only; LEAVE the machine intact. Machine removal is only
# via the confirmation-gated `recreate` / `delete` targets above.
# `container prune` removes ALL stopped containers (CLI has no filter) - not
# only build leftovers; the prompt and README say so explicitly.
.PHONY: clean
clean: ## Remove build artifacts + loaded image + ALL stopped containers (confirms)
	@read -p "Remove build artifacts, the loaded image '$(IMAGE)', and ALL stopped containers (container prune has no filter; running machine is kept)? Type yes to confirm: " ans; \
	if [ "$$ans" = "yes" ]; then \
		rm -rf build; \
		container image delete $(IMAGE) 2>/dev/null || true; \
		nbefore=$$(container ls -a 2>/dev/null | tail -n +2 | wc -l | tr -d ' '); \
		container prune || true; \
		nafter=$$(container ls -a 2>/dev/null | tail -n +2 | wc -l | tr -d ' '); \
		echo "Stopped containers pruned (all stopped, unfiltered): $$nbefore -> $$nafter."; \
		echo "Removed build artifacts and image '$(IMAGE)'; machine '$(MACHINE_NAME)' left intact."; \
	else \
		echo "Aborted."; \
	fi

# ------------------------------------------------------------------------------
# Applying configuration to the running machine (the usual update loop).

# Copy machine-configuration/ into the running machine as the live overlay
# (the path that wins configuration precedence; no image build). Expanded on
# host; the guest reads it via the machine's --home-mount rw (so run make
# from this directory). Gates on wait-ready: this is the first half of
# every switch target, and nixos-rebuild right after it needs the daemon.
.PHONY: sync-config
sync-config: wait-ready ## Write machine-configuration/ as the guest's live overlay (wins precedence)
	@test -d "$(HOST_BASE)" || { echo "missing $(HOST_BASE)" >&2; exit 2; }
	container machine run -n $(MACHINE_NAME) --root \
		'rm -rf /etc/nixos/machine-configuration && mkdir -p /etc/nixos/machine-configuration && cp -a "$(HOST_BASE)/." /etc/nixos/machine-configuration/'

# `container machine run --root 'cmd'` runs bash -c (not a login shell), so
# NIX_PATH only exists after /etc/set-environment (sessionVariables from
# nix.nixPath / upstream default) is sourced. Do not hardcode NIX_PATH here -
# the Nix config is the single source.
.PHONY: switch
switch: sync-config ## Sync machine-configuration (live overlay) and switch the running machine
	container machine run -n $(MACHINE_NAME) --root \
		'. /etc/set-environment && nixos-rebuild switch'

# ------------------------------------------------------------------------------
# Example switches: TEST-ONLY targets for exercising `switch` with examples/
# instead of your own config. Each example switches against either base, one
# target per base:
#   nonflake  its configuration.nix imports /etc/nixos/configuration.nix, whose
#             precedence picks the base: live overlay when it exists
#             (sync-config first), image copy (.baked) when it does not - so
#             the -baked target parks the overlay to take that branch.
#   flake     its `cm` input IS the base: baked is declared in the example,
#             live is selected with --override-input (never written to the
#             lock), hence sync-config first there.
# A flake never reads configuration.nix. nixos-config is PREPENDED so it wins
# over the default entry from /etc/set-environment.
.PHONY: switch-nonflake
switch-nonflake: sync-config ## [test] examples/nonflake, base = live machine-configuration overlay
	@test -f "$(HOST_EXAMPLES)/nonflake/configuration.nix" || \
		{ echo "missing $(HOST_EXAMPLES)/nonflake/configuration.nix" >&2; exit 2; }
	container machine run -n $(MACHINE_NAME) --root \
		'. /etc/set-environment && NIX_PATH="nixos-config=$(HOST_EXAMPLES)/nonflake/configuration.nix:$$NIX_PATH" nixos-rebuild switch'

# Park (mv, not rm) the live overlay so the baked branch can run. One slot:
# when a backup is already parked, fail with the ways out instead of
# overwriting it. Inverse: restore-config.
.PHONY: switch-nonflake-baked
switch-nonflake-baked: wait-ready ## [test] examples/nonflake, base = image copy (parks live overlay in .bak)
	@test -f "$(HOST_EXAMPLES)/nonflake/configuration.nix" || \
		{ echo "missing $(HOST_EXAMPLES)/nonflake/configuration.nix" >&2; exit 2; }
	container machine run -n $(MACHINE_NAME) --root \
		'set -e; \
		live=/etc/nixos/machine-configuration; \
		if [ -e "$$live" ]; then \
			if [ -e "$$live.bak" ]; then \
				echo "error: a parked overlay already sits at $$live.bak" >&2; \
				echo "  make restore-config   brings it back (then re-run this target)" >&2; \
				echo "  or discard it:        container machine run -n $(MACHINE_NAME) --root rm -rf $$live.bak" >&2; \
				exit 2; \
			fi; \
			mv "$$live" "$$live.bak"; \
			echo "parked live overlay -> $$live.bak"; \
		elif [ -e "$$live.bak" ]; then \
			echo "note: already parked at $$live.bak (nothing to move)"; \
		fi; \
		. /etc/set-environment && NIX_PATH="nixos-config=$(HOST_EXAMPLES)/nonflake/configuration.nix:$$NIX_PATH" nixos-rebuild switch'

# Inverse of the park in switch-nonflake-baked: moves the backup back,
# replacing whatever sits at the overlay path (sync-config recreates that from
# the host tree). Directory state only - run `make switch` to activate it.
.PHONY: restore-config
restore-config: wait-exec ## [test] Bring the parked live overlay back (replaces the current one)
	container machine run -n $(MACHINE_NAME) --root \
		'set -e; \
		live=/etc/nixos/machine-configuration; \
		if [ ! -e "$$live.bak" ]; then \
			echo "error: nothing parked at $$live.bak" >&2; \
			exit 2; \
		fi; \
		rm -rf "$$live"; \
		mv "$$live.bak" "$$live"; \
		echo "restored parked overlay -> $$live (run make switch to activate)"'

.PHONY: switch-flake
switch-flake: sync-config ## [test] examples/flake, cm = image copy (.baked)
	@test -f "$(HOST_EXAMPLES)/flake/flake.nix" || \
		{ echo "missing $(HOST_EXAMPLES)/flake/flake.nix" >&2; exit 2; }
	container machine run -n $(MACHINE_NAME) --root \
		'. /etc/set-environment && nixos-rebuild switch --flake "$(HOST_EXAMPLES)/flake#default"'

.PHONY: switch-flake-live
switch-flake-live: sync-config ## [test] examples/flake, cm = live overlay (override-input)
	@test -f "$(HOST_EXAMPLES)/flake/flake.nix" || \
		{ echo "missing $(HOST_EXAMPLES)/flake/flake.nix" >&2; exit 2; }
	container machine run -n $(MACHINE_NAME) --root \
		'. /etc/set-environment && nixos-rebuild switch --flake "$(HOST_EXAMPLES)/flake#default" --override-input cm path:/etc/nixos/machine-configuration'
