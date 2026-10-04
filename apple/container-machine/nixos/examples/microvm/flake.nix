# microvm.nix smoke test: boots a tiny NixOS microvm on REAL hardware
# virtualization - the L2 proof behind the README "Nested Virtualization
# (KVM)" section (qemu holds /dev/kvm: kvm-vm, kvm-vcpu, vgic fds).
#
# Requirements: nested virtualization on the machine first (make enable-kvm).
# The repo sits at the same path inside the machine (home mount), so from
# the host:
#
#   container machine run --root -n nixos-cm \
#     'cd <repo>/examples/microvm && nix build && ./result/bin/microvm-run'
#
# Expect the console to reach "Welcome to NixOS"; kill qemu with Ctrl-a x or
# pkill -f microvm. The qemu backend passes accel=kvm:tcg - where /dev/kvm is
# absent it silently falls back to TCG, so check the acceleration with
# kvm-verify on the host side first (or inspect qemu open fds on /dev/kvm
# while it runs).
#
# flake.lock is committed: plain GitHub pins, reproducible anywhere - unlike
# examples/flake, whose lock pins machine-specific NAR hashes and stays out
# of git on purpose.
#
# L3 (KVM inside this microvm) does not work yet. Default -M virt gives the
# guest no EL2 (so no /dev/kvm); adding virtualization=on makes L1's qemu
# refuse to start:
#   qemu-system-aarch64: mach-virt: host kernel KVM does not support
#   providing Virtualization extensions to the guest CPU
# That is KVM_CAP_ARM_EL2=0 in L1. Mainline arm64 (6.18) reports the cap only
# if the kernel boots with the experimental kvm-arm.mode=nested arg (our L1
# cmdline has none) and the CPUID carries FEAT_NV2 from the layer above -
# arch/arm64/kvm/nested.c + cpufeature.c. We run L1 with virtualization=true;
# the untried bit is the boot arg. Nested-guest docs exist for x86 only:
# https://www.kernel.org/doc/html/latest/virt/kvm/x86/running-nested-guests.html
# Apple nested EL2 arrived in macOS 15 (hv_vm_config_set_el2_enabled):
# https://github.com/actions/runner-images/issues/13505
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    microvm.url = "github:astro/microvm.nix";
  };

  outputs = { self, nixpkgs, microvm }: {
    nixosConfigurations.l2 = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        microvm.nixosModules.microvm
        {
          system.stateVersion = "26.11";
          networking.hostName = "l2-microvm";
          services.getty.autologinUser = "root";

          microvm = {
            hypervisor = "qemu";
            vcpu = 1;
            mem = 256;
            shares = [
              {
                tag = "ro-store";
                source = "/nix/store";
                mountPoint = "/nix/.ro-store";
                proto = "9p";
              }
            ];
            interfaces = [
              {
                type = "user";
                id = "qemu";
                mac = "02:00:00:01:01:01";
              }
            ];
          };
        }
      ];
    };

    packages.aarch64-linux.default =
      self.nixosConfigurations.l2.config.microvm.runner.qemu;
  };
}
