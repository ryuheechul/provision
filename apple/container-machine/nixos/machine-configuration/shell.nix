# Shell / PATH shims for the Apple runtime: container-machine-shell wrapper,
# the /bin pre-activation bootstrap it hands off from, shell-fix boot service,
# and USER/LOGNAME profile hooks.
{ lib, pkgs, ... }:

let
  # PATH wrapper Apple's minimal passwd shell lacks; also derives USER/LOGNAME
  # from HOME (see profile.local below for why that matters everywhere).
  containerShell = pkgs.writeShellScriptBin "container-machine-shell" ''
    # Extend PATH first so commands (basename below) resolve in a minimal env.
    export PATH="/usr/local/bin:/run/wrappers/bin:/run/current-system/sw/bin''${PATH:+:}$PATH"
    export USER="''${USER:-$(basename "$HOME")}"
    export LOGNAME="''${LOGNAME:-$USER}"
    exec /run/current-system/sw/bin/bash "$@"
  '';

  # Pre-activation bootstrap, grafted at /bin/container-machine-shell by the
  # image (image/bin/make-rootfs.sh) and re-installed by the activation snippet
  # below. Apple's init execs the passwd shell as soon as the vminitd API
  # accepts commands - before stage-2 activation links /run/current-system, so
  # the wrapper path in passwd does not exist yet (transient ENOENT on early
  # execs, /run is a tmpfs the runtime mounts over the image's graft). Wait
  # for the wrapper here instead, then hand off to it unchanged.
  shellBootstrap = pkgs.writeShellScript "container-machine-shell-bootstrap" ''
    i=0
    while [ ! -e /run/current-system/sw/bin/container-machine-shell ]; do
      i=$((i + 1))
      if [ "$i" -ge 100 ]; then
        echo "container-machine-shell: /run/current-system not ready after 10s" >&2
        exit 127
      fi
      ${pkgs.coreutils}/bin/sleep 0.1
    done
    exec /run/current-system/sw/bin/container-machine-shell "$@"
  '';

  fixMachineUserShell = pkgs.writeShellScript "container-machine-fix-user-shell" ''
    # Reconcile machine-user passwd shells with the bootstrap. Walk-through,
    # since the script is dense:
    #   - /home/* only: root and declaratively created users belong to the
    #     `users` activation snippet; this exists for the Apple-provisioned
    #     account, which mutable passwd keeps outside that machinery.
    #   - the uid check: the home owner must match the passwd uid, so an
    #     entry that merely shares the name is left alone.
    #   - the case guard is the non-interference rule: rewrite ONLY Apple's
    #     initial /bin/sh and the legacy pre-bootstrap /run/... wrapper
    #     (the ENOENT window the bootstrap closes). Every other shell value -
    #     e.g. one a later configuration declares for this user - is left
    #     untouched, so a subsequent configuration always wins. The one
    #     exception is a configuration declaring the literal /bin/sh: that is
    #     textually identical to Apple's initial entry, so it still gets
    #     rewritten, exactly as it did before the bootstrap existed.
    #   - tmp file + mv: readers never observe a torn /etc/passwd.
    for home in /home/*; do
      [ -d "$home" ] || continue
      user="$(basename "$home")"
      uid="$(${pkgs.coreutils}/bin/stat -c %u "$home")"
      entry="$(${pkgs.gnugrep}/bin/grep "^''${user}:" /etc/passwd || true)"
      [ -n "$entry" ] || continue
      entry_uid="$(printf '%s\n' "$entry" | ${pkgs.coreutils}/bin/cut -d: -f3)"
      shell="$(printf '%s\n' "$entry" | ${pkgs.coreutils}/bin/cut -d: -f7)"
      [ "$entry_uid" = "$uid" ] || continue
      # Apple's initial /bin/sh, plus the legacy pre-bootstrap wrapper path
      # (the ENOENT window it lived in is exactly what the bootstrap closes).
      # Anything else belongs to the declarative configuration.
      case "$shell" in
        /bin/sh | /run/current-system/sw/bin/container-machine-shell) ;;
        *) continue ;;
      esac
      ${pkgs.gawk}/bin/awk -F: -v user="$user" \
        -v shell=/bin/container-machine-shell \
        'BEGIN { OFS = ":" } $1 == user { $7 = shell } { print }' \
        /etc/passwd > /etc/passwd.container-machine.tmp
      ${pkgs.coreutils}/bin/mv /etc/passwd.container-machine.tmp /etc/passwd
    done
  '';
in
{
  environment.systemPackages = [ containerShell ];
  # NixOS's generated profile otherwise replaces PATH after the shell wrapper
  # starts, dropping the persistent location where direct sudo is installed.
  environment.localBinInPath = true;

  # Expose the bootstrap to the image (image/rootfs.nix grafted at
  # /bin/container-machine-shell by image/bin/make-rootfs.sh).
  system.build.containerMachineShellBootstrap = shellBootstrap;

  # Reinstall the bootstrap on every activation so a switch onto an image that
  # predates the graft still gets it. Ordered before the users snippet (deps
  # below) so passwd pointing at /bin/container-machine-shell never lands
  # before the file exists.
  system.activationScripts.containerMachineShellBootstrap.text =
    "${pkgs.coreutils}/bin/install -m 0755 ${shellBootstrap} /bin/container-machine-shell\n";
  system.activationScripts.users.deps = [ "containerMachineShellBootstrap" ];

  # 900 (not mkDefault): NixOS sets root.shell at mkDefault (1000) priority,
  # so a plain mkDefault here would conflict with it. 900 beats NixOS's
  # default but still loses to a downstream plain assignment - a later
  # configuration can override the shell without mkForce, matching the
  # mutableUsers.mkDefault precedent in users.nix.
  users.users.root.shell = lib.mkOverride 900 "/bin/container-machine-shell";

  systemd.services.container-machine-shell-fix = {
    description = "Point the container machine user's shell at the /bin bootstrap";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-tmpfiles-setup.service" ];
    path = [ pkgs.coreutils pkgs.gawk pkgs.gnugrep ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = "${fixMachineUserShell}";
  };

  # Same reconciliation during activation, so `nixos-rebuild switch` migrates
  # the passwd shell before the next boot's early execs (after users and the
  # user restore, which may just have appended the account).
  system.activationScripts.containerMachineShellFix = {
    deps = [ "containerMachineUserFix" ];
    text = "${fixMachineUserShell}\n";
  };

  # Apple's runtime forks the passwd shell with no USER/LOGNAME; a bare switch
  # may have no passwd entry either ($(id -un) -> numeric uid). Always derive
  # from HOME (set by Apple). profile.local covers bash/login; zshenv.local
  # covers every zsh - needed for set -u scripts and NixOS set-environment.
  environment.etc."profile.local".text = ''
    export USER="''${USER:-$(basename "$HOME")}"
    export LOGNAME="''${LOGNAME:-$USER}"
  '';
  environment.etc."zshenv.local".text = ''
    export USER="''${USER:-$(basename "$HOME")}"
    export LOGNAME="''${LOGNAME:-$USER}"
  '';
}
