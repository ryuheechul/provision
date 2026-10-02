#!/usr/bin/env bash
# Confirm that this repo's machine name and the guest's hostname agree.
#
# A container machine's name is fixed when it is created: apple/container has
# no rename subcommand (container machine set --name selects a machine, it does
# not rename one), so once a guest-side rebuild gives the machine a different
# hostname there is no supported way to make the host refer to it by that name
# - short of deleting and recreating the machine, which destroys its persisted
# /home. This script therefore only reports. It changes nothing: not the
# machine, not files in this repo, and not the Nix code.
#
# Note: immediately after create the guest may briefly answer with the machine
# name as its own hostname, before the system has applied /etc/hostname. Re-run
# a few seconds after the machine is up for a settled reading.
#
# Usage: bin/check-machine-name.sh
# Exit:  0 when the two agree, 1 on a mismatch, 2/1 on the errors below
# Env:   MACHINE_NAME (default "nixos-cm")
set -euo pipefail

name="${MACHINE_NAME:-nixos-cm}"

command -v container >/dev/null || { echo "Apple 'container' CLI not found" >&2; exit 1; }

# stderr gets its own capture: folding it into the result would let a CLI
# warning pass for the hostname, and a mismatch is reported as a fact.
err="$(mktemp)"
trap 'rm -f "$err"' EXIT
if ! host="$(container machine run -n "$name" --root hostname 2>"$err")"; then
  echo "error: could not read a hostname from machine '$name':" >&2
  cat "$err" >&2
  exit 1
fi
[ -n "$host" ] || { echo "error: machine '$name' reported an empty hostname" >&2; exit 1; }
if [ -s "$err" ]; then
  echo "note: container also said:" >&2
  cat "$err" >&2
fi

echo "machine name:   $name"
echo "guest hostname: $host"

if [ "$host" = "$name" ]; then
  echo "in step"
  exit 0
fi

cat >&2 <<EOF

MISMATCH - the guest answers as '$host' but you refer to it as '$name'.

Renaming a container machine is currently not supported: the CLI has no rename
subcommand, and 'container machine set --name' only selects which machine to
configure, so the name is fixed at creation. Lining the two up would mean
deleting and recreating the machine under '$host', which destroys its
persisted /home.

Nothing was changed.
EOF
exit 1
