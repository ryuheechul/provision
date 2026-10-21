arch := $(shell arch | xargs test "arm64" = && echo "aarch64" || echo "x86_64")
# current stable channel - bump when the previous one goes EOL
channel := nixos-26.05
# the graphical iso replaced the gnome iso in recent channels
img := https://channels.nixos.org/$(channel)/latest-nixos-graphical-$(arch)-linux.iso
iso_file = $(channel).iso

# delete the target when its recipe fails or is interrupted, so a partial
# iso download is never mistaken for a complete one on the next run
.DELETE_ON_ERROR:

# fail early with a useful hint instead of a bare "command not found" - tart is
# declared in the repo's mise.toml (see the root README for `mise install`)
.PHONY: check-tart
check-tart:
	@command -v tart >/dev/null || { echo "tart not found - run 'mise install' at the repo root, or put tart on PATH" >&2; exit 1; }

.PHONY: run
run: check-tart .vm-created
	tart run nixos-vm

.PHONY: delete
delete:
	-tart delete nixos-vm
	rm -f .vm-created

.vm-created: $(iso_file)
	tart create --linux nixos-vm \
	&& tart run --disk $(iso_file) nixos-vm \
	&& touch .vm-created

$(iso_file):
	curl -fL -o $(iso_file) $(img)
