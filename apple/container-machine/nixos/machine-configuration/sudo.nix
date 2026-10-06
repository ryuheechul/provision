# Sudo for the locked Apple account: direct setuid binary (no capability
# wrapper), pam_permit account rule (for sudo and su), and sudo-fix boot
# service - plus the raw unix_chkpwd helper that sshd's PAM account check
# depends on.
{ config, lib, pkgs, ... }:

let
  # PATH-visible `sudo` that execs the setuid binary on the persistent rootfs
  # (cannot live in /nix/store or /run - see below).
  sudoCommand = pkgs.writeShellScriptBin "sudo" ''
    exec /usr/local/bin/sudo "$@"
  '';

  # Shared PAM *account*-phase compatibility for the locked Apple account,
  # used by both services below: pam_unix account validation rejects the
  # locked shadow entry even when authentication is skipped (NOPASSWD for
  # sudo, pam_rootok in su's auth phase), so only the account phase is
  # replaced - pam_unix drops out, pam_permit is required. Auth/session
  # phases and every other service (login/sshd) keep their stacks; account
  # expiry stays unenforced for these two services only (sshd and login
  # still enforce it). Downstream overrides stay per service via
  # security.pam.services.<name>.rules.account (e.g. re-enable
  # unix.enable) rather than lib.mkForce on the whole service.
  lockedAccountRules = {
    unix.enable = false;
    permit = {
      control = "required";
      modulePath = "${config.security.pam.package}/lib/security/pam_permit.so";
      order = 10000;
    };
  };
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
  # The pam_permit rules further down scope to sudo/su, so they cannot cover
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
  # For sudo: NOPASSWD skips password authentication, but without the shared
  # account rule above the locked account was rejected anyway, making sudo
  # unusable in a bare image. sudoers is the authority for this account, not
  # pam_unix aging checks.
  security.pam.services.sudo = {
    enable = true;
    rules.account = lockedAccountRules;
  };

  # For su: the guest's shell startup re-execs the first shell after boot
  # through it (`sudo su`), so the same rejection surfaced as
  #   su: Authentication service cannot retrieve authentication info
  #   (Ignored)
  # on that shell's terminal (the re-exec itself still succeeded; later
  # shells on the same boot were quiet). The auth phase keeps pam_rootok
  # for root and the pam_unix password check for everyone else.
  security.pam.services.su = {
    enable = true;
    rules.account = lockedAccountRules;
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
