LIMA_INSTANCE ?= nixos

.PHONY: debug
debug: teardown-debug
	limactl start --debug --tty=false --name=nixos-debug ./config.yaml
	$(MAKE) debug-enter

.PHONY: debug-enter
debug-enter:
	LIMA_INSTANCE=nixos-debug lima

.PHONY: teardown-debug
teardown-debug:
	limactl stop nixos-debug || true
	limactl delete nixos-debug

.PHONY: start-notty
start-notty:
	LIMA_INSTANCE=$(LIMA_INSTANCE) \
		../bin/start-or-resume.sh

.PHONY: start
start:
	LIMA_INSTANCE=$(LIMA_INSTANCE) \
		../bin/start-or-resume.sh \
		&& $(MAKE) enter

.PHONY: enter
enter:
	LIMA_INSTANCE=$(LIMA_INSTANCE) lima

.PHONY: edit
edit:
	limactl edit $(LIMA_INSTANCE)

.PHONY: teardown
teardown: stop
	limactl delete $(LIMA_INSTANCE)

.PHONY: stop
stop:
	limactl stop $(LIMA_INSTANCE) || true

# run this on the host: build and boot a new generation from a flake in the
# current directory (home is mounted read-only into the guest)
.PHONY: rebuild
rebuild:
	limactl shell $(LIMA_INSTANCE) -- nixos-rebuild boot --flake .#nixos-aarch64 --sudo
	limactl restart $(LIMA_INSTANCE)

# run this inside vm
.PHONY: host
host:
	ssh host.lima.internal
