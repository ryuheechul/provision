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
in
{
  # Explicit pin (matches NixOS default): passwd must stay mutable so
  # restoreMachineUser can append the Apple-provisioned account and the first
  # dotfiles switch can declare it. With mutableUsers = false, activation
  # would replace /etc/passwd from users.users only and wipe that account.
  # mkDefault so a downstream plain assignment can still override.
  users.mutableUsers = lib.mkDefault true;

  # Apple provisions the user only when the machine is initially created.
  # After a restart, NixOS may regenerate /etc/passwd while /home/<user>
  # remains on disk - restore the runtime user from home ownership. Runs
  # before the sudo/shell fixes; a declarative users.users entry always wins.
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
}
