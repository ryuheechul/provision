# Shared data for the container-machine image build: platform facts, static
# file contents, and OCI JSON templates. Imported by rootfs.nix and oci.nix;
# wired up from default.nix.
{ pkgs, system, imageName, imageTag }:

let
  inherit (pkgs) lib;

  # OCI config/index platform architecture, derived from the NixOS system
  # (a hardcode of "arm64" would be wrong for any non-aarch64 build).
  ociArchitecture = {
    "aarch64-linux" = "arm64";
    "x86_64-linux" = "amd64";
  }.${system} or (throw "image: no OCI architecture mapping for system '${system}'");

  # Shared tar flags for every archive this build produces: normalize owners,
  # sort entries, pin mtime - so rebuilds are byte-reproducible.
  tarFlags = "--hard-dereference --numeric-owner --owner=0 --group=0 --sort=name --mtime=@1";

  # Timestamp baked into the OCI config/history (matches tar --mtime=@1).
  ociEpoch = "1970-01-01T00:00:01Z";

  # Static file contents, held as Nix data instead of shell heredocs so the
  # exact bytes are reviewable without untangling $-escaping.
  osRelease = pkgs.writeText "os-release" ''
    ID=nixos
    NAME=NixOS
  '';

  # /bin/sh always carrying the NixOS system profile on PATH. The bare
  # bash shim leaves non-login shells with an empty PATH (container execs
  # shells non-login; /run is tmpfs, so stage-2 activation re-creates
  # /run/current-system after the image's static graft is gone).
  binSh = pkgs.writeText "sh" ''
    #!${pkgs.bashInteractive}/bin/bash
    export PATH="/run/wrappers/bin:/run/current-system/sw/bin:$PATH"
    exec ${pkgs.bashInteractive}/bin/bash "$@"
  '';

  # /bin shims the system tarball alone doesn't ship (early boot / provisioning
  # expect them before the system profile is on PATH). One attrset = one place
  # to add or drop a shim. Serialized as "name=path" lines for make-rootfs.sh.
  binShims = {
    chown = "${pkgs.coreutils}/bin/chown";
    cut = "${pkgs.coreutils}/bin/cut";
    grep = "${pkgs.gnugrep}/bin/grep";
    id = "${pkgs.coreutils}/bin/id";
  };
  binShimsEnv = lib.concatStrings (lib.mapAttrsToList (name: path: "${name}=${path}\n") binShims);

  ociLayout = pkgs.writeText "oci-layout" ''
    {"imageLayoutVersion":"1.0.0"}
  '';

  dockerfile = pkgs.writeText "Dockerfile" ''
    FROM scratch
    ADD rootfs.tar.xz /
    ENV container container
    STOPSIGNAL SIGRTMIN+4
    CMD ["/sbin/init"]
  '';

  # OCI JSON templates: structure is pure Nix data (builtins.toJSON), not shell
  # string assembly. Digests/sizes only exist at build time, so they are left
  # as @TOKEN@ placeholders for sed in pack-oci-image.sh. Size placeholders
  # ride as JSON strings and get unquoted by that sed (so the final value is
  # a number, as the OCI spec requires).
  ociConfigTemplate = pkgs.writeText "oci-config.json" (builtins.toJSON {
    created = ociEpoch;
    architecture = ociArchitecture;
    os = "linux";
    config = {
      Cmd = [ "/sbin/init" ];
      # Make `container machine stop` send systemd's poweroff signal
      # (SIGRTMIN+4). Without this the runtime falls back to SIGTERM,
      # which systemd PID 1 only re-execs on (sysvinit compat), forcing
      # a 10s SIGKILL - unclean. Machine create copies this from the
      # image config, so recreate the machine after changing it.
      StopSignal = "SIGRTMIN+4";
    };
    rootfs = {
      type = "layers";
      diff_ids = [ "sha256:@DIFF_ID@" ];
    };
    history = [
      { created = ociEpoch; created_by = "nixos-machine"; }
    ];
  });

  ociManifestTemplate = pkgs.writeText "oci-manifest.json" (builtins.toJSON {
    schemaVersion = 2;
    mediaType = "application/vnd.oci.image.manifest.v1+json";
    config = {
      mediaType = "application/vnd.oci.image.config.v1+json";
      digest = "sha256:@CONFIG_DIGEST@";
      size = "@CONFIG_SIZE@";
    };
    layers = [
      {
        mediaType = "application/vnd.oci.image.layer.v1.tar+gzip";
        digest = "sha256:@LAYER_DIGEST@";
        size = "@LAYER_SIZE@";
      }
    ];
  });

  ociIndexTemplate = pkgs.writeText "oci-index.json" (builtins.toJSON {
    schemaVersion = 2;
    mediaType = "application/vnd.oci.image.index.v1+json";
    manifests = [
      {
        mediaType = "application/vnd.oci.image.manifest.v1+json";
        digest = "sha256:@MANIFEST_DIGEST@";
        size = "@MANIFEST_SIZE@";
        platform = { architecture = ociArchitecture; os = "linux"; };
        annotations."org.opencontainers.image.ref.name" = "${imageName}:${imageTag}";
      }
    ];
  });
in
{
  inherit
    tarFlags
    osRelease
    binSh
    binShimsEnv
    ociLayout
    dockerfile
    ociConfigTemplate
    ociManifestTemplate
    ociIndexTemplate
    ;
}
