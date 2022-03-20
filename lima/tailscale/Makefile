LIMA_INSTANCE ?= tailscale

.PHONY: debug
debug: teardown-debug
	limactl start --debug --tty=false --name=tailscale-debug ./config.yaml
	$(MAKE) debug-enter

.PHONY: debug-enter
debug-enter:
	LIMA_INSTANCE=tailscale-debug lima

.PHONY: teardown-debug
teardown-debug:
	limactl stop tailscale-debug || limactl delete tailscale-debug

.PHONY: start
start:
	limactl start --tty=false --name=$(LIMA_INSTANCE) ./config.yaml
	$(MAKE) enter

.PHONY: enter
enter:
	lima

.PHONY: teardown
teardown:
	limactl stop $(LIMA_INSTANCE) || limactl delete $(LIMA_INSTANCE)

# run this inside vm
.PHONY: tailscale
tailscale:
	sudo tailscale up

# run this inside vm
.PHONY: host
host:
	ssh host.lima.internal
