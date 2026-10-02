#!/usr/bin/env bash
# Publish the built OCI archive to the GitHub Container Registry (ghcr.io).
#
# The archive from bin/build.sh / bin/build-on-container.sh is already a
# spec-compliant OCI image archive, so skopeo copies it straight to the
# registry - no docker daemon involved. Two tags are published:
#   sha-<short>   pinned to the git commit the archive was built from
#   latest        moved to point at the same image
#
# Auth: GitHub Packages accepts classic PATs only *for now* - fine-grained
# PATs are still on GitHub's known-gaps list (tracked in
# https://github.com/ryuheechul/provision/issues/1; gap list:
# https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)
# and `gh` OAuth tokens are rejected outright
# (https://github.com/cli/cli/issues/5174). If GitHub lifts the limitation,
# revisit issue #1 - a fine-grained PAT should work here unchanged.
#   1. GHCR_USER + GHCR_TOKEN env - what CI passes (actor + GITHUB_TOKEN)
#   2. stored login: skopeo login ghcr.io -u ryuheechul, token from
#      https://github.com/settings/tokens/new?scopes=write:packages
#   3. otherwise runs skopeo login once (needs a TTY)
#
# Usage:
#   bin/publish.sh                     # archive = this project's build/
#   bin/publish.sh path/to/archive.tar # custom archive
# Env:
#   GHCR_IMAGE (default ghcr.io/ryuheechul/provision/nixos-cm)
#   TAGS       (space-separated, default "latest sha-<short>" - order irrelevant)
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
project="$(dirname "$script_dir")"
cd "$script_dir"

command -v skopeo >/dev/null || {
  echo "skopeo not found (e.g. nix profile install nixpkgs#skopeo, brew install skopeo)" >&2
  exit 1
}

image="${GHCR_IMAGE:-ghcr.io/ryuheechul/provision/nixos-cm}"
archive="${1:-$project/build/nixos-machine-image.tar}"
[ -f "$archive" ] || {
  echo "archive not found: $archive (run bin/build-on-container.sh first)" >&2
  exit 2
}

short="$(git -C "$project" rev-parse --short HEAD)"
tags="${TAGS:-sha-$short latest}"

# Registry credentials: env pair > stored skopeo login > interactive login.
# With none of these, skopeo falls back to ~/.config/containers/auth.json.
creds=()
if [ -n "${GHCR_TOKEN:-}" ]; then
  creds=(--dest-creds "${GHCR_USER:-ryuheechul}:$GHCR_TOKEN")
elif [ -n "${GHCR_USER:-}" ]; then
  echo "GHCR_USER is set but GHCR_TOKEN is not" >&2
  exit 4
elif ! grep -q '"ghcr.io"' "${XDG_CONFIG_HOME:-$HOME/.config}/containers/auth.json" 2>/dev/null; then
  echo "no stored ghcr.io login - starting interactive login"
  echo "(classic PAT: https://github.com/settings/tokens/new?scopes=write:packages)"
  skopeo login ghcr.io --username "${GHCR_USER:-ryuheechul}" || {
    echo "login failed (needs a TTY and a classic PAT; non-interactive: export GHCR_USER/GHCR_TOKEN)" >&2
    exit 5
  }
fi

echo "publishing $archive"
echo "  as $image:$tags"

pushed=""
for tag in $tags; do
  # --insecure-policy: pushing verifies no signatures, and macOS/nix skopeo
  # ships no policy.json (skopeo refuses to run without one).
  skopeo --insecure-policy copy ${creds[@]+"${creds[@]}"} \
    "oci-archive:$archive" "docker://$image:$tag" || {
      echo "push failed for $image:$tag" >&2
      echo '("owner not found" = image name has a wrong owner (must be your ghcr login), or a stale/wrong login: skopeo logout ghcr.io && skopeo login ghcr.io -u ryuheechul)' >&2
      exit 1
    }
  pushed="$pushed $image:$tag"
done

echo
echo "published:$pushed"
echo "pull (anonymous, once the package is public):"
echo "  container machine create $image:latest --name nixos-cm --cpus 4 --memory 8G --home-mount rw"
