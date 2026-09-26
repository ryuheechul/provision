# Sudo for the locked Apple account: direct setuid binary (no capability
# wrapper), pam_permit account rule, and sudo-fix boot service.
{ config, lib, pkgs, ... }:

let
  # PATH-visible `sudo` that execs the setuid binary on the persistent rootfs
  # (cannot live in /nix/store or /run - see below).
  sudoCommand = pkgs.writeShellScriptBin "sudo" ''
    exec /usr/local/bin/sudo "$@"
  '';
in
{
  # Apple creates a locked account without a password. A direct setuid sudo
  # binary is used instead of NixOS's capability-aware wrapper: the Apple
  # kernel rejects the wrapper's capability probing. /run itself is a nosuid
  # tmpfs, and /nix/store is read-only, so the binary must live on the writable
  # persistent root filesystem. /usr/local/bin is also a conventional PATH
  # location and is included in sudo's secure_path below.
  security.sudo.enable = lib.mkDefault false;
  # Global clear (not sudo-only): the option is one attrset, so mkForce {} drops
  # every module's wrappers (ping, mount, ...), not just sudo. Accepted here -
  # minimal image, direct setuid sudo instead. Downstream configs can re-add
  # individual entries with their own mkForce.
  security.wrappers = lib.mkForce { };
  # Apple provisions the machine user with a locked shadow entry. NOPASSWD
  # skips password authentication, but normal pam_unix account validation
  # still rejects that locked account, making sudo unusable in a bare image.
  # Scope: sudo's PAM *account* phase only (not auth/session; other services
  # like login/sshd untouched). This is an explicit compatibility rule, not a
  # general user-policy default: account expiry/lock checks are skipped for
  # sudo in favor of sudoers as the authority. A downstream config can change
  # it by setting security.pam.services.sudo.rules.account (e.g. re-enable
  # unix.enable) rather than lib.mkForce on the whole service.
  security.pam.services.sudo = {
    enable = true;
    rules.account = {
      unix.enable = false;
      permit = {
        control = "required";
        modulePath = "${config.security.pam.package}/lib/security/pam_permit.so";
        order = 10000;
      };
    };
  };
  environment.etc."sudoers".text = ''
    Defaults secure_path="/usr/local/bin:/run/current-system/sw/bin:/usr/bin:/bin"
    root ALL=(ALL:ALL) ALL
    @includedir /etc/sudoers.d
  '';

  environment.systemPackages = [ sudoCommand ];

  systemd.services.container-machine-sudo-fix = {
    description = "Install direct sudo for the container machine user";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-tmpfiles-setup.service" "container-machine-user-fix.service" ];
    path = [ pkgs.coreutils pkgs.shadow ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      install -d -m 755 /usr/local/bin
      install -m 4755 ${pkgs.sudo}/bin/sudo /usr/local/bin/sudo
    '';
  };
}
