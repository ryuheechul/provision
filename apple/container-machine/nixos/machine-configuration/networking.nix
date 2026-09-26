# Networking for the Apple `container` container-machine: systemd-resolved
# pointed at the runtime's gateway resolver, firewall left off.
{ lib, pkgs, ... }:

{
  # The Apple container runtime's VM bridge self-provisions the guest's IP, a
  # default gateway, and a working DNS resolver AT that gateway (verified
  # empirically and in Apple source: getDefaultNameservers returns the vmnet
  # gateway as the resolver, and macOS mDNSResponder binds :53 on it). The
  # subnet is NOT fixed (unprivileged: 192.168.64.0/24, root: 192.168.2.0/24,
  # or a custom one), so the resolver is derived from the default route instead
  # of a hardcoded address. `useHostResolvConf` must be off for systemd-resolved
  # (nixpkgs asserts it); container-config.nix mkDefaults it true whenever
  # boot.isContainer, so use an override that a downstream plain assignment
  # can still beat.
  networking.useHostResolvConf = lib.mkOverride 200 false;
  services.resolved.enable = true;
  # Apple container does not expose the network namespace capabilities needed
  # by the NixOS firewall. Users can explicitly re-enable it if their runtime
  # supports it.
  networking.firewall.enable = lib.mkDefault false;

  # systemd-resolved gets no DNS from DHCP: no DHCPv4 server answers (dhcpcd
  # falls back to IPv4LL), and although an RA with RDNSS does arrive, dhcpcd
  # cannot apply it (resolved owns resolv.conf -> "Access denied"). Point
  # resolved at the runtime's resolver, which is the default-route gateway
  # (Apple's own getDefaultNameservers does the same). This adapts to any
  # vmnet subnet instead of hardcoding an address.
  systemd.services.runtime-gateway-dns = {
    description = "Point systemd-resolved at the runtime gateway resolver";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-resolved.service" "systemd-networkd.service" ];
    path = [ pkgs.iproute2 pkgs.gawk pkgs.systemd pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      i=0
      while [ "$i" -lt 20 ]; do
        route="$(${pkgs.iproute2}/bin/ip route show default 2>/dev/null)"
        if [ -n "$route" ]; then
          iface="$(${pkgs.gawk}/bin/awk '{ for (i=1;i<=NF;i++) if ($i == "dev") { print $(i+1); exit } }' <<<"$route")"
          gateway="$(${pkgs.gawk}/bin/awk '{ for (i=1;i<=NF;i++) if ($i == "via") { print $(i+1); exit } }' <<<"$route")"
          if [ -n "$iface" ] && [ -n "$gateway" ]; then
            ${pkgs.systemd}/bin/resolvectl dns "$iface" "$gateway" && exit 0
          fi
        fi
        sleep 1
        i=$((i + 1))
      done
      # Fail visibly (exit 1) after the retry window: a successful exit would
      # leave the oneshot active forever and hide a DNS misconfiguration from
      # `systemctl --failed` / `make status`. wantedBy only - boot continues.
      echo "runtime-gateway-dns: no default route after 20s; DNS not configured" >&2
      exit 1
    '';
  };

  # systemd-resolved owns /etc/resolv.conf; no openresolv override (resolved
  # manages resolv.conf; openresolv is off and the old setfacl workaround
  # would fail).
}
