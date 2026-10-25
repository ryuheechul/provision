# Provisioned-user reconciliation: keep the Apple-created machine account
# across reboots and switches without fighting a declarative users.users entry.
{ lib, pkgs, ... }:

let
  restoreMachineUser = pkgs.writeShellScript "container-machine-restore-user" ''
    # Apple persists /home but may let NixOS regenerate /etc/passwd. Restore
    # only a missing account; a declarative users.users entry always wins (the
    # grep checks below skip any account NixOS has already declared).
    # Skip root-owned homes only: the host user is typically uid 501.
    for home in /home/*; do
      [ -d "$home" ] || continue
      user="$(basename "$home")"
      uid="$(${pkgs.coreutils}/bin/stat -c %u "$home")"
      gid="$(${pkgs.coreutils}/bin/stat -c %g "$home")"
      [ "$uid" = 0 ] && continue
      ${pkgs.gnugrep}/bin/grep -q "^''${user}:" /etc/passwd && continue
      # Field 3 only: bare ":uid:" also matches another account's gid (or any field).
      ${pkgs.gnugrep}/bin/grep -q "^[^:]*:[^:]*:''${uid}:" /etc/passwd && continue
      printf '%s:x:%s:%s::%s:/bin/container-machine-shell\n' \
        "$user" "$uid" "$gid" "$home" >> /etc/passwd
      # shadow: password locked (!), lastchange 19000, min 0, max 99999,
      # warn 7; inactive/expire/reserved empty (no lockout, no expiry)
      printf '%s:!:19000:0:99999:7:::\n' "$user" >> /etc/shadow
    done
  '';

  # Apple's user setup needs these commands on its minimal PATH
  # (user-setup-tools.nix explains why). The image grafts them into /bin, but
  # a machine created from an image built before that graft has no such files:
  # link the same set into /usr/local/bin, which is first on the runtime PATH
  # and lives on the persistent rootfs. /bin/sh itself is replaced by NixOS's
  # own activation (environment.binsh), so /bin is not a durable place.
  userSetupTools = import ./user-setup-tools.nix { inherit pkgs; };
  installUserSetupTools = pkgs.writeShellScript "container-machine-user-setup-tools" (
    ''
      ${pkgs.coreutils}/bin/install -d -m 0755 /usr/local/bin
    ''
    + lib.concatStrings (lib.mapAttrsToList (name: path: ''
      ${pkgs.coreutils}/bin/ln -sfn ${path} /usr/local/bin/${name}
    '') userSetupTools)
  );
in
{
  # Explicit pin (matches NixOS default): passwd must stay mutable so
  # restoreMachineUser can append the Apple-provisioned account and the first
  # dotfiles switch can declare it. With mutableUsers = false, activation
  # would replace /etc/passwd from users.users only and wipe that account.
  # mkDefault so a downstream plain assignment can still override.
  users.mutableUsers = lib.mkDefault true;

  # NixOS may regenerate /etc/passwd while /home/<user> remains on disk -
  # restore the runtime user from home ownership. container >= 1.6 also reruns
  # its own setup every boot; the image shims (user-setup-tools.nix) are what
  # keep that succeeding. Runs before the sudo/shell fixes; a declarative
  # users.users entry always wins.
  systemd.services.container-machine-user-fix = {
    description = "Restore the Apple container machine user after reboot";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-tmpfiles-setup.service" ];
    before = [
      "container-machine-sudo-fix.service"
      "container-machine-shell-fix.service"
    ];
    path = [ pkgs.coreutils pkgs.gnugrep ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = "${restoreMachineUser}";
  };

  # Same reconciliation after the boot service, because a switch can rewrite
  # /etc/passwd again (see service above).
  system.activationScripts.containerMachineUserFix = {
    deps = [ "users" ];
    text = "${restoreMachineUser}\n";
  };

  # container >= 1.6 reruns Apple's user setup on every boot, so keep the
  # commands it needs reachable even on a machine built from an older image.
  # Runs on every switch and every boot, and is cheap and idempotent.
  system.activationScripts.containerMachineUserSetupTools.text = "${installUserSetupTools}\n";
}
