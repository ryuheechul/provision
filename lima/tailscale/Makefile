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

# run this inside vm
.PHONY: tailscale
tailscale:
	sudo tailscale up --ssh

# run this inside vm
.PHONY: host
host:
	ssh host.lima.internal
