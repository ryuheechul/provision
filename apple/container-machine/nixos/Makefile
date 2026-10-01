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
#   make status        # key facts about the running config
#   make dns           # machine DNS check: <name>.machine -> IP match
#   make dns-set       # register the machine DNS domain (sudo)
#   make dns-rm        # unregister the machine DNS domain (sudo)
#   make switch        # apply machine-configuration/ to the running machine
#   make fstrim        # reclaim host disk for blocks freed in the guest
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
MACHINE_NAME ?= nixos
# Image tag (single host-side default; passed through to launch.sh). Matches
# image/default.nix imageName:imageTag. Override: `make launch IMAGE=other:tag`.
IMAGE        ?= local/nixos-cm:latest
# Source tree for sync-config (the live overlay written into the guest).
HOST_BASE    := $(CURDIR)/machine-configuration
# Example configurations (switch-nonflake / switch-flake). Host paths, read in
# the guest via the machine's --home-mount rw.
HOST_EXAMPLES := $(CURDIR)/examples

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

# Open an interactive shell as the machine user / as root.
.PHONY: run
run: ## Shell in as the machine user
	container machine run -n $(MACHINE_NAME)

.PHONY: root
root: ## Shell in as root
	container machine run -n $(MACHINE_NAME) --root

.PHONY: current-system
current-system: ## Show the linked system generation
	container machine run -n $(MACHINE_NAME) --root 'readlink /run/current-system || echo "not linked yet"'

.PHONY: status
status: ## Show linked system + config source (overlay|baked) + count of failed units
	container machine run -n $(MACHINE_NAME) --root '\
		echo "current-system: $$(readlink /run/current-system)"; \
		echo "config source: $$(if [ -e /etc/nixos/machine-configuration ]; then echo overlay; else echo baked; fi)"; \
		echo "failed units: $$(systemctl list-units --state=failed --no-legend | wc -l)"; \
	'

# Only reclaims *free* blocks - delete first, then trim. Not destructive alone.
.PHONY: fstrim
fstrim: ## Reclaim host disk for freed guest blocks
	container machine run -n $(MACHINE_NAME) --root 'fstrim -v /'

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
# the host; the guest reads it via the machine's --home-mount rw (so run make
# from this directory).
.PHONY: sync-config
sync-config: ## Write machine-configuration/ as the guest's live overlay (wins precedence)
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
switch-nonflake-baked: ## [test] examples/nonflake, base = image copy (parks live overlay in .bak)
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
restore-config: ## [test] Bring the parked live overlay back (replaces the current one)
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
		'. /etc/set-environment && nixos-rebuild switch --flake "$(HOST_EXAMPLES)/flake"'

.PHONY: switch-flake-live
switch-flake-live: sync-config ## [test] examples/flake, cm = live overlay (override-input)
	@test -f "$(HOST_EXAMPLES)/flake/flake.nix" || \
		{ echo "missing $(HOST_EXAMPLES)/flake/flake.nix" >&2; exit 2; }
	container machine run -n $(MACHINE_NAME) --root \
		'. /etc/set-environment && nixos-rebuild switch --flake "$(HOST_EXAMPLES)/flake" --override-input cm path:/etc/nixos/machine-configuration'
