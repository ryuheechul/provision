#!/usr/bin/env bash

set -e
set -x

instance="${LIMA_INSTANCE}"

extracted_name="$(limactl ls --json | jq -r ". | select(.name == \"${instance}\") | .name")"

# if exist, resume
# if not, start
if test "${extracted_name}" == "${instance}"; then
	limactl start --tty=false "${LIMA_INSTANCE}"
else
  config_file_path="./config.yaml"
  # config.yaml will be loaded if exist
	if test -f "${config_file_path}"; then
		limactl start --tty=false --name="${LIMA_INSTANCE}" ${config_file_path}
	else
		# I know this is weird but it is what it is now as of version lima v0.9.1
		limactl start --tty=false "${LIMA_INSTANCE}"
	fi
fi
