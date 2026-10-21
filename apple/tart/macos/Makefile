# macOS inside a tart VM, cloned from a prebuilt Cirrus Labs vanilla image -
# no installer or Setup Assistant, unlike the nixos flavor's ISO boot
codename := golden-gate
image := ghcr.io/cirruslabs/macos-$(codename)-base:latest
vm := macos-vm
cpu ?= 4
memory ?= 8192

# tart is called as-is rather than resolved through mise's 'latest' symlink:
# the sandbox_extension warning it can print is harmless (see the README)

# delete the target when its recipe fails or is interrupted, so a half-made
# clone is never mistaken for a complete one on the next run
.DELETE_ON_ERROR:

# fail early with a useful hint instead of a bare "command not found" - tart is
# declared in the repo's mise.toml (see the root README for `mise install`)
.PHONY: check-tart
check-tart:
	@command -v tart >/dev/null || { echo "tart not found - run 'mise install' at the repo root, or put tart on PATH" >&2; exit 1; }

.PHONY: run
run: check-tart .vm-created
	tart run $(vm)

.PHONY: run-vnc
run-vnc: check-tart .vm-created
	tart run --vnc $(vm)

.PHONY: run-headless
run-headless: check-tart .vm-created
	tart run --no-graphics $(vm)

.PHONY: delete
delete:
	-tart delete $(vm)
	rm -f .vm-created

.PHONY: clean
clean: delete
	-tart delete $(image)

# tart clone pulls the remote base on first use and clones it copy-on-write,
# so the clone claims almost no space until written
.vm-created:
	tart clone $(image) $(vm) \
	&& tart set $(vm) --cpu $(cpu) --memory $(memory) \
	&& touch .vm-created

