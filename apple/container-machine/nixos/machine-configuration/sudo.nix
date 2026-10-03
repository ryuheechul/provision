# Sudo for the locked Apple account: direct setuid binary (no capability
# wrapper), pam_permit account rule, and sudo-fix boot service - plus the raw
# unix_chkpwd helper that sshd's PAM account check depends on.
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
  # individual entries with their own mkForce - but a declarative entry cannot
  # serve sshd here, which is what the suid-sgid-wrappers postStart below works
  # around.
  security.wrappers = lib.mkForce { };

  # pam_unix is hardwired to exec /run/wrappers/bin/unix_chkpwd, and sshd runs
  # its PAM account check in the unprivileged privsep child (running as the
  # logging-in user), which cannot read /etc/shadow itself. Without the helper
  # every ssh login is rejected right after the key is accepted:
  #   fatal: Access denied for user <name> by PAM account configuration
  # The pam_permit rule further down scopes to sudo only, so it cannot cover
  # this. Re-adding a security.wrappers entry does NOT work either: NixOS's
  # compiled security wrapper probes file capabilities on /proc/self/exe, which
  # this kernel rejects ("cannot get capabilities for /proc/self/exe: Not
  # supported") - it exits 1 before execing the helper, the same kernel quirk
  # that makes sudo a raw setuid binary above. So install the real helper into
  # the wrappers dir right after the unit (re)builds it: postStart fires at boot
  # and on every switch, always after the atomic dir swap.
  # Setuid works even though /run is nosuid because /run/wrappers is its own
  # tmpfs mounted without nosuid - the mount NixOS sets up for exactly this.
  systemd.services.suid-sgid-wrappers.postStart = lib.mkAfter ''
    ${pkgs.coreutils}/bin/install -m 4755 -o root -g root ${config.security.pam.package}/bin/unix_chkpwd /run/wrappers/bin/unix_chkpwd
  '';
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
