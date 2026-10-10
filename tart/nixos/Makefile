arch := $(shell arch | xargs test "arm64" = && echo "aarch64" || echo "x86_64")
# current stable channel - bump when the previous one goes EOL
channel := nixos-26.05
# the graphical iso replaced the gnome iso in recent channels
img := https://channels.nixos.org/$(channel)/latest-nixos-graphical-$(arch)-linux.iso
iso_file = $(channel).iso

# delete the target when its recipe fails or is interrupted, so a partial
# iso download is never mistaken for a complete one on the next run
.DELETE_ON_ERROR:

.PHONY: run
run: .tart-installed .vm-created
	tart run nixos-vm

.PHONY: delete
delete:
	-tart delete nixos-vm
	rm -f .vm-created

.vm-created: $(iso_file)
	tart create --linux nixos-vm \
	&& tart run --disk $(iso_file) nixos-vm \
	&& touch .vm-created

# via nixpkgs rather than the cirruslabs brew tap: the tap formula does not
# parse on current Homebrew (depends_on macos DSL removal); tart carries an
# unfree license so allow it for this one invocation only; command -v keeps
# this a no-op when tart is already on PATH by any means
.tart-installed:
	command -v tart >/dev/null || NIXPKGS_ALLOW_UNFREE=1 nix profile add --impure nixpkgs#tart
	touch .tart-installed

$(iso_file):
	curl -fL -o $(iso_file) $(img)
