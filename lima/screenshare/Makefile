LIMA_INSTANCE ?= screenshare

.PHONY: forward
forward:
	LIMA_INSTANCE=$(LIMA_INSTANCE) ../bin/start-or-resume.sh
	./bin/open.sh
	LIMA_INSTANCE=$(LIMA_INSTANCE) lima ./bin/forward.sh

.PHONY: start
start:
	LIMA_INSTANCE=$(LIMA_INSTANCE) \
		../bin/start-or-resume.sh \
		&& $(MAKE) enter

.PHONY: enter
enter:
	LIMA_INSTANCE=$(LIMA_INSTANCE) lima

.PHONY: ip 
ip:
	@LIMA_INSTANCE=$(LIMA_INSTANCE) ../bin/start-or-resume.sh 2> /dev/null
	@LIMA_INSTANCE=$(LIMA_INSTANCE) lima ./bin/print-assigned-ip.sh

.PHONY: teardown
teardown: stop
	limactl delete $(LIMA_INSTANCE)

.PHONY: stop
stop:
	limactl stop $(LIMA_INSTANCE) || true
