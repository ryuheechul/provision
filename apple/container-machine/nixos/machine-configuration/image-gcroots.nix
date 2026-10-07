# GC roots for the image's baked rootfs references (manifest written by
# image/bin/make-rootfs.sh): nix-collect-garbage only protects store paths
# reachable from roots, and it cannot see that /init, /bin/* and friends
# point at image-build-time store paths. Without roots, a guest GC keeps the
# rootfs files but collects their targets - boot dies at exec /sbin/init
# (127) and `container machine run` has no way back into the machine to
# repair it. Plain symlinks under /nix/var/nix/gcroots/image count as
# regular GC roots, so one pass at first activation protects the paths for
# the machine's lifetime; re-running on later switches only refreshes them
# (ln -sfn, idempotent). Roots persist independently of whichever system
# generation happens to be active, so this script can live in the switched
# configuration without weakening the guarantee it gives the image.
# The script also prunes links the manifest no longer lists, so the
# gcroots directory always mirrors the manifest: if it is ever replaced
# by a smaller scan (this one dropped the build toolchain that
# nix-path-registration leaked in), the dropped targets become
# collectable instead of staying rooted - and on disk - forever.
{ pkgs, ... }:

{
  system.activationScripts.containerMachineImageGcroots.text = ''
    manifest=/etc/nixos/image-gcroots.manifest
    roots=/nix/var/nix/gcroots/image
    # -s, not -e: an empty manifest means the scan produced nothing, and
    # pruning on that would drop every root at once.
    if [ -s "$manifest" ]; then
      ${pkgs.coreutils}/bin/mkdir -p "$roots"
      while IFS= read -r p; do
        case "$p" in
          /nix/store/*)
            if [ -e "$p" ]; then
              ${pkgs.coreutils}/bin/ln -sfn "$p" "$roots/''${p##*/}"
            fi
            ;;
        esac
      done < "$manifest"
      # Link names are manifest basenames, so any symlink here without an
      # exact manifest line is stale (grep -F -x: store names contain
      # regex characters like . and ?).
      for link in "$roots"/*; do
        if [ -L "$link" ] && \
           ! ${pkgs.gnugrep}/bin/grep -qxF "/nix/store/''${link##*/}" "$manifest"; then
          ${pkgs.coreutils}/bin/rm -f "$link"
        fi
      done
    fi
  '';
}
