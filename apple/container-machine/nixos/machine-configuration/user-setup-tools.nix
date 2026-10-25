# Commands Apple's container machine user setup runs inside the guest.
#
# container <= 1.5 ran that setup once, through /sbin.machine/init -u.
# container >= 1.6 runs it on every boot as `/bin/sh -c <embedded script>`
# (MachineUserSetup), with
#   PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# and before stage-2 activation links /run/current-system. NixOS keeps every
# one of these commands in the system profile only, so none of them resolve on
# that PATH. The script then reads empty passwd lookups and refuses the home it
# created on an earlier boot:
#   container machine: refusing to use existing path '/home/<user>' as the
#   home directory for user '<user>'
#
# Two consumers, one list:
#   - image/common.nix grafts them into /bin (fresh machines: setup can run
#     before any activation, so only image content is available)
#   - machine-configuration/users.nix links them into /usr/local/bin on the
#     persistent rootfs at activation (repairs machines whose image predates
#     the graft; /usr/local/bin is first on the runtime PATH)
#
# Keep this additive: 1.5's create path uses a subset (no `date`) and only
# benefits from the commands being reachable.
{ pkgs }:
{
  chown = "${pkgs.coreutils}/bin/chown";
  cut = "${pkgs.coreutils}/bin/cut";
  grep = "${pkgs.gnugrep}/bin/grep";
  id = "${pkgs.coreutils}/bin/id";
  getent = "${pkgs.getent}/bin/getent";
  date = "${pkgs.coreutils}/bin/date";
  mkdir = "${pkgs.coreutils}/bin/mkdir";
  cp = "${pkgs.coreutils}/bin/cp";
  chmod = "${pkgs.coreutils}/bin/chmod";
  tr = "${pkgs.coreutils}/bin/tr";
}
