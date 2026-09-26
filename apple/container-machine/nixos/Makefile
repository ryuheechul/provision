# Make targets for building and launching an Apple `container` container-machine
# from the NixOS image in this directory. A convenience wrapper over the scripts
# in bin/, which also work directly from any directory; targets without a
# script (clean, recreate, delete, sync-config, switch, status) live here.
#
#   make build         # build the OCI archive (Apple `container` sandbox)
#   make build-context # alternate: Dockerfile context for container build (fallback)
#   make launch        # load the image + create the machine (create-if-missing)
#   make run           # shell in as the machine user
#   make root          # root shell
#   make status        # key facts about the running config
#   make fstrim        # reclaim host disk for blocks freed in the guest
#   make clean         # remove build artifacts + loaded image + ALL stopped containers (prune is unfiltered; leaves the machine)
#   make recreate      # DELETE the machine + re-create it (DESTROYS state; confirms)
#   make delete        # DELETE the machine + its state, no recreate (DESTROYS; confirms)
#   make help
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
