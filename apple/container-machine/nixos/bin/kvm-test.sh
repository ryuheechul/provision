#!/usr/bin/env bash
# L1 KVM smoke on the scratch test machine: boot a tiny L2 userspace on
# STRICT hardware virtualization. qemu started with -enable-kvm has no tcg
# fallback, so a completed boot IS the proof that /dev/kvm works end to end
# inside the machine - without touching the real machine (nixos-cm).
#
# What it does inside the machine (root): installs qemu + the alpine lts
# kernel on first run (apk, cached afterwards), then boots that kernel plus
# its initramfs under `qemu-system-aarch64 -M virt -enable-kvm` with
# `rdinit=/bin/sh`, feeds `echo L2OK` a few seconds after start, and greps
# for L2OK in the console output. The delay matters: bytes written before
# the guest shell polls the UART are dropped by the emulated fifo, so input
# sent at t=0 never reaches the shell (observed on first attempt).
#
# Usage: bin/kvm-test.sh         (machine first: make kvm-test-create)
# Exit:  0 on L1 PASS, 1 on failure
# Env:   TEST_MACHINE (default "kvm-test")
set -euo pipefail

name="${TEST_MACHINE:-kvm-test}"

container machine list 2>/dev/null | grep -qE "^${name}([[:space:]]|$)" || {
  echo "error: scratch machine '$name' not found (run: make kvm-test-create)" >&2
  exit 1
}

echo "provisioning '$name' (qemu + linux-lts; idempotent, apk cached)..."
container machine run --root -n "$name" '
  apk info -e qemu-system-aarch64 >/dev/null 2>&1 || apk add --no-cache qemu-system-aarch64
  apk info -e linux-lts >/dev/null 2>&1 || apk add --no-cache linux-lts
'

echo "booting L2 on strict KVM (-enable-kvm; boot success = KVM proof)..."
# The inner run is expected to end in timeout (qemu has no reason to exit on
# its own: the initramfs shell lacks poweroff), hence the `|| true` - the
# verdict is the L2OK marker, not the exit code.
out="$(container machine run --root -n "$name" '
  ( sleep 6; printf "echo L2OK\n"; sleep 20 ) |
  timeout 25 qemu-system-aarch64 -M virt -enable-kvm -cpu host -smp 1 -m 512 \
    -kernel /boot/vmlinuz-lts -initrd /boot/initramfs-lts \
    -append "console=ttyAMA0 rdinit=/bin/sh" \
    -nographic -no-reboot -monitor none 2>&1
' || true)"

if echo "$out" | grep -q L2OK; then
  echo "L1 PASS: L2 booted on strict KVM inside '$name'"
else
  echo "L1 FAIL: L2OK never appeared; last output:" >&2
  echo "$out" | tail -25 >&2
  exit 1
fi
