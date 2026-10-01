#!/usr/bin/env bash
# Check apple/container's DNS naming from the host: the root domain and which
# resolvable name maps to each machine.
#
# The root domain is FIXED: apple/container hardcodes "machine"
# (MachineConfiguration.swift - defaultDNSDomain, used by the computed dnsName),
# so every instance answers as <name>.machine from the host (bare <name> works
# too - the resolver file carries a search domain) and from inside the guest
# (guest queries travel through the vmnet gateway to the same embedded server
# at 127.0.0.1:2053). `container system dns create <d>` registers domains for
# *container* hostnames only (apple/container networking docs) - it does not
# move machine names. Only existing instances answer, and the name is the
# stable handle: DHCP IPs can change across restarts, so match instances by
# name, not by IP.
#
# Usage: bin/dns.sh
# Output: per machine - name, FQDN, host-resolved IP, MATCH/DIFFERS verdict.
set -euo pipefail

if [ $# -gt 0 ]; then
  echo "usage: bin/dns.sh (machine root domain is fixed to .machine - see README DNS section)" >&2
  exit 64
fi

command -v container >/dev/null || { echo "Apple 'container' CLI not found" >&2; exit 1; }
command -v dscacheutil >/dev/null || { echo "dscacheutil not found (macOS only)" >&2; exit 1; }

domain="machine"
registered="$(container system dns list 2>/dev/null | tail -n +2)"
case "
$registered
" in
  *"
$domain
"*) ;;
  *) echo "warning: '$domain' is not registered (container system dns list) - queries may fail" ;;
esac

echo "machine root domain: .$domain (fixed by apple/container - README DNS section)"
echo
echo "registered root domains:"
if [ -n "$registered" ]; then
  printf '%s\n' "$registered" | sed 's/^/  /'
else
  echo "  (none registered)"
fi
echo
echo "macOS resolver files:"
find /etc/resolver -mindepth 1 -maxdepth 1 2>/dev/null | sed 's|.*/|  |' || true
echo

if ! listed="$(container machine list 2>&1)"; then
  echo "error: container machine list failed:" >&2
  printf '%s\n' "$listed" >&2
  echo "hint: the system service may be down - try: container system start" >&2
  exit 1
fi
rows="$(printf '%s\n' "$listed" | tail -n +2)"
if [ -z "$rows" ]; then
  echo "(no machines)"
  exit 0
fi
while read -r name _date _time ip _rest; do
  fqdn="$name.$domain"
  resolved="$(dscacheutil -q host -a name "$fqdn" | awk '/^ip_address:/{print $2}' | head -1)"
  if [ -z "$resolved" ]; then
    verdict="not resolvable (machine stopped?)"
  elif [ "$resolved" = "$ip" ]; then
    verdict="MATCH"
  else
    verdict="DIFFERS (list: $ip, dns: $resolved)"
  fi
  printf '  %-12s %-24s %-16s %s\n' "$name" "$fqdn" "${resolved:--}" "$verdict"
done <<< "$rows"
