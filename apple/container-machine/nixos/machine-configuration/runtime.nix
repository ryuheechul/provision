# Boot quirk of the Apple runtime: /run/systemd must exist before systemd
# starts. /run/current-system needs no unit here - stage-2 activation
# recreates it from the baked-in systemConfig before systemd runs.
{ lib, ... }:

{
  boot.postBootCommands = lib.mkBefore ''
    mkdir -p /run/systemd
  '';
}
