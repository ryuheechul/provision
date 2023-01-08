#!/usr/bin/env bash

set -e
set -x

instance="${LIMA_INSTANCE}"

extracted_name="$(limactl ls --json | jq -r ". | select(.name == \"${instance}\") | .name")"

if test "${extracted_name}" = "${instance}"; then
	# if exist, resume
	limactl start --tty=false "${LIMA_INSTANCE}"
	# wait how do I make an update to an existing machine?
	# 1. edit config.yaml for future reiteration
	# 2. `limactl edit "${LIMA_INSTANCE}"` and apply the same change
	# 3. verify the changes are made - if it's actually applied is up to lima
else
	# if not, start
  config_file_path="./config.yaml"
  # config.yaml will be loaded if exist
	if test -f "${config_file_path}"; then
		limactl start --tty=false --name="${LIMA_INSTANCE}" ${config_file_path}
	else
		# I know this is weird but it is what it is for now as of version lima v0.9.1
		limactl start --tty=false "${LIMA_INSTANCE}"
	fi
fi
