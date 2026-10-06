# Shell / PATH shims for the Apple runtime: container-machine-shell wrapper,
# the /bin pre-activation bootstrap it hands off from, shell-fix boot service,
# declarative passwd shells resolved to store paths, and USER/LOGNAME profile
# hooks.
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

  # Persist declarative /run/current-system/* passwd shells as the absolute
  # store path they name. Why this exists:
  #   - NixOS normalizes a declared shell *package* to
  #     /run/current-system/sw/<path> in the users spec
  #     (nixos/lib/utils.nix toShellPath), so the `users` activation snippet
  #     writes that form on every switch - any configuration declaring the
  #     shell as a package (users.users.<name>.shell = pkgs.zsh) lands here
  #     as /run/current-system/sw/bin/zsh.
  #   - /run/current-system only exists mid-activation: stage-2 mounts /run
  #     as tmpfs (killing the image's baked graft), activation re-links at
  #     its *end*, and systemd starts after that. Apple's init, however,
  #     greps field 7 and execs it the instant the vminitd API accepts
  #     commands - so the spec form is ENOENT on every boot until activation
  #     finishes (the rc 127 boot race; the boot service and /bin bootstrap
  #     only cover the /bin/container-machine-shell entries, not declared
  #     ones, which the case guard in fixMachineUserShell deliberately
  #     leaves to the declarative configuration).
  #   - The store path needs no link: it lives on the rootfs from power-on,
  #     is byte-for-byte the shell the configuration declares (readlink -f
  #     against $1 = $systemConfig, the generation being activated, whose
  #     sw paths are valid even before the final link flip), and is GC-safe
  #     because the system profile roots its closure. Persisting it in the
  #     mutable passwd closes the boot window without touching the spec,
  #     the image, or anything downstream; each activation re-resolves, so
  #     a later shell change still lands.
  #   - The value is only ever written atomically (single mv over
  #     /etc/passwd): init -s reads passwd live and must never see a torn
  #     file. No-op (no mv) when nothing matches.
  resolvePasswdShells = pkgs.writeShellScript "container-machine-resolve-passwd-shells" ''
    # $1 = the generation being activated (the hook passes $systemConfig);
    # its sw/ tree is valid on the rootfs before /run/current-system flips
    # to it at the end of activation.
    syscfg="$1"
    # Distinct field-7 values still in the spec form; none means passwd has
    # only /bin or store shells already - exit without touching the file.
    shells="$(${pkgs.gawk}/bin/awk -F: '$7 ~ /^\/run\/current-system\// { print $7 }' /etc/passwd \
      | ${pkgs.coreutils}/bin/sort -u)"
    [ -n "$shells" ] || exit 0
    # The temp lives in /etc - same filesystem as passwd - so the final mv
    # is a rename(2), not a cross-device copy: passwd readers (init -s
    # greps it live) always see a complete old or new file.
    tmp="$(${pkgs.coreutils}/bin/mktemp /etc/passwd.container-machine.XXXXXX)"
    ${pkgs.coreutils}/bin/cat /etc/passwd > "$tmp"
    changed=0
    for spec in $shells; do
      # /run/current-system/sw/bin/zsh -> sw/bin/zsh, to replay under $syscfg
      rel="''${spec#/run/current-system/}"
      # -f follows the whole chain (sw/bin/zsh is itself a symlink into the
      # store) down to one absolute store path; $syscfg instead of
      # /run/current-system is what makes the value valid at next power-on
      resolved="$(${pkgs.coreutils}/bin/readlink -f "$syscfg/$rel")"
      # Target missing from this generation: keep the old entry rather
      # than persist a dangling path
      [ -e "$resolved" ] || continue
      # Exact field-7 match only; rewrite the temp copy, so the temp stays
      # a complete passwd at every loop step (still old value below)
      ${pkgs.gawk}/bin/awk -F: -v OFS=: -v old="$spec" -v new="$resolved" \
        '$7 == old { $7 = new } { print }' "$tmp" > "$tmp.next"
      ${pkgs.coreutils}/bin/mv -f "$tmp.next" "$tmp"
      changed=1
    done
    # Single commit point: mv only when something matched (a passwd without
    # spec-form shells is never rewritten), chmod first because mktemp
    # creates 0600 while passwd must stay 0644 for getpwnam as non-root
    if [ "$changed" = 1 ]; then
      ${pkgs.coreutils}/bin/chmod 0644 "$tmp"
      ${pkgs.coreutils}/bin/mv -f "$tmp" /etc/passwd
    else
      ${pkgs.coreutils}/bin/rm -f "$tmp"
    fi
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
  #
  # Plain install is delete-then-copy: unlink the old file, then copy the
  # bytes (store read, write loop, chmod), and that copy is not instant.
  # Readers of the destination during the gap - root's passwd shell execs
  # this path mid-switch, plus existence probes (truncation misses were
  # observed in testing) - see a missing or half-written file:
  #
  #   install:     --old file--|--empty/half--|--new file-->
  #                             ^ exec here: file not found or broken script
  #   staged mv:   --old file----------------|--new file-->
  #                             ^ exec here: complete old or complete new
  #
  # So write the full copy under a name nobody opens, then publish the real
  # name with a single mv: same filesystem, so the swap is one atomic step,
  # never a gap. Mode is set on the temp first, so the name never exists
  # un-executable. A crash between the two lines leaves an orphan .new plus
  # the intact old file; the next activation restages over it.
  system.activationScripts.containerMachineShellBootstrap.text = ''
    ${pkgs.coreutils}/bin/install -m 0755 ${shellBootstrap} /bin/.container-machine-shell.new
    ${pkgs.coreutils}/bin/mv -f /bin/.container-machine-shell.new /bin/container-machine-shell
  '';
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

  # Last in the chain (users -> userFix -> shellFix): perl has just written
  # the spec form, the Apple-shell fix has just run, and $systemConfig is the
  # new generation - resolve any remaining /run/current-system/* shell to its
  # store path so the value that persists on disk is valid at power-on.
  system.activationScripts.containerMachineShellResolve = {
    deps = [ "containerMachineShellFix" ];
    text = "${resolvePasswdShells} \"$systemConfig\"\n";
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
