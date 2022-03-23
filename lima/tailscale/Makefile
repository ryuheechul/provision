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
	bin/start-or-resume.sh && $(MAKE) enter

.PHONY: enter
enter:
	lima

.PHONY: teardown
teardown: stop
	limactl delete $(LIMA_INSTANCE)

.PHONY: stop
stop:
	limactl stop $(LIMA_INSTANCE) || true

# run this inside vm
.PHONY: tailscale
tailscale:
	sudo tailscale up

# run this inside vm
.PHONY: host
host:
	ssh host.lima.internal
