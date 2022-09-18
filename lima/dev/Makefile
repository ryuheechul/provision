LIMA_INSTANCE ?= dev

.PHONY: debug
debug: teardown-debug
	limactl start --debug --tty=false --name=dev-debug ./config.yaml
	$(MAKE) debug-enter

.PHONY: debug-enter
debug-enter:
	LIMA_INSTANCE=dev-debug lima

.PHONY: teardown-debug
teardown-debug:
	limactl stop dev-debug || limactl delete dev-debug

.PHONY: start
start:
	../bin/start-or-resume.sh && $(MAKE) enter

.PHONY: enter
enter:
	lima

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
.PHONY: host
host:
	ssh host.lima.internal
