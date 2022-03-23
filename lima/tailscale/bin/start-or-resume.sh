#!/usr/bin/env bash

set -e

instance="${LIMA_INSTANCE}"

does_exist="$(limactl ls -f "{{eq .Name \"${instance}\"}}" | grep true)"

# if exist, resume
# if not, start
if test "${does_exist}" == "true"
then
	limactl start --tty=false ${LIMA_INSTANCE}
else
	limactl start --tty=false --name=${LIMA_INSTANCE} ./config.yaml
fi
