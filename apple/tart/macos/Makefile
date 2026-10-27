# macOS inside a tart VM, cloned from a prebuilt Cirrus Labs vanilla image -
# no installer or Setup Assistant, unlike the nixos flavor's ISO boot
codename := golden-gate
image := ghcr.io/cirruslabs/macos-$(codename)-base:latest
vm := macos-vm
cpu ?= 4
memory ?= 8192
# per-user service declared in mise.toml; the name becomes the label dev.mise.<name>
service := tart-macos

# the run targets call tart as-is rather than resolving it through mise's
# 'latest' symlink: the sandbox_extension warning it can print is harmless
# (see the README). The service bakes in the resolved path instead, since
# launchd has no shell PATH.

# delete the target when its recipe fails or is interrupted, so a half-made
# clone is never mistaken for a complete one on the next run
.DELETE_ON_ERROR:

# fail early with a useful hint instead of a bare "command not found" - tart is
# declared in the repo's mise.toml (see the root README for `mise install`)
.PHONY: check-tart
check-tart:
	@command -v tart >/dev/null || { echo "tart not found - run 'mise install' at the repo root, or put tart on PATH" >&2; exit 1; }

# the service is applied with mise's launchd bootstrap, so mise (not tart)
# is the tool that must be on PATH for the service-* targets
.PHONY: check-mise
check-mise:
	@command -v mise >/dev/null || { echo "mise not found - install mise (https://mise.jdx.dev), or run 'tart run --vnc $(vm)' manually" >&2; exit 1; }

.PHONY: run
run: check-tart .vm-created
	tart run $(vm)

.PHONY: run-vnc
run-vnc: check-tart .vm-created
	tart run --vnc $(vm)

.PHONY: run-headless
run-headless: check-tart .vm-created
	tart run --no-graphics $(vm)

# print hostname
.PHONY: hostname
hostname: check-tart .vm-created
	@tart exec $(vm) hostname

# ping hostname
.PHONY: ping
ping: check-tart .vm-created
	@ping $$($(MAKE) -s hostname)

# exec a command in the running VM; defaults to zsh
.PHONY: exec
exec: check-tart .vm-created
	tart exec -it $(vm) zsh

# mise parses this directory's mise.toml for every bootstrap command, and a
# config with templates is not trusted until it is marked so
.PHONY: trust-mise
trust-mise: check-mise
	@mise trust -q mise.toml

# register `tart run --vnc` as a per-user service. mise owns the plist
# (~/Library/LaunchAgents/dev.mise.$(service).plist) and its load/unload, so
# applying and removing are each one command. RunAtLoad starts the VM now too.
.PHONY: service-install
service-install: trust-mise check-tart .vm-created
	TART_BIN="$$(command -v tart)" mise bootstrap macos launchd-agents apply --yes
	@echo "registered dev.mise.$(service) - starts now and at every login"
	@echo "logs: $(HOME)/Library/Logs/tart-service-macos-vm.log"

# stop the VM but keep the service registered. `tart stop` sends SIGINT, which
# makes tart shut the guest down and exit 0, so keep_alive_on_failure does not
# bring it back until the next login or `make service-start`.
.PHONY: service-stop
service-stop: check-tart
	@if launchctl print gui/$$(id -u)/dev.mise.$(service) 2>/dev/null | grep -q 'state = running'; then \
		tart stop $(vm) \
		&& echo "stopped $(vm) - dev.mise.$(service) is still registered; 'make service-start' boots it again"; \
	else \
		echo "$(vm) is not running"; \
	fi

# kickstart the loaded job without re-registering or re-rendering the plist
.PHONY: service-start
service-start:
	@launchctl print gui/$$(id -u)/dev.mise.$(service) >/dev/null 2>&1 || { echo "dev.mise.$(service) is not registered - run 'make service-install' first" >&2; exit 1; }
	launchctl kickstart gui/$$(id -u)/dev.mise.$(service)

.PHONY: service-status
service-status: trust-mise
	@mise bootstrap macos launchd-agents status

# unloading also stops the tart process launchd started; `make service-stop`
# first if the guest should shut down gracefully
.PHONY: service-uninstall
service-uninstall: trust-mise
	-mise bootstrap services remove $(service)
	@echo "unregistered dev.mise.$(service)"

.PHONY: delete
delete:
	-tart delete $(vm)
	rm -f .vm-created

# show the real space cost of the VM and its cached base image. tart clone is
# copy-on-write, so `tart list` / `du` double-count the shared APFS blocks;
# deleting only the base image frees just the VM's divergence, not its full
# image. `make clean` reclaims the VM and the base image entirely.
.PHONY: size
size:
	@./bin/tart-size $(vm) $(image)

.PHONY: clean
clean: delete
	-tart delete $(image)

# tart clone pulls the remote base on first use and clones it copy-on-write,
# so the clone claims almost no space until written
.vm-created:
	tart clone $(image) $(vm) \
	&& tart set $(vm) --cpu $(cpu) --memory $(memory) \
	&& touch .vm-created

