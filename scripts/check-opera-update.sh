#!/usr/bin/env bash
set -euo pipefail

info() { echo -e "\e[32m[INFO]\e[0m $*"; }
warn() { echo -e "\e[33m[WARN]\e[0m $*" >&2; }

# Extract the version from a .nix file (first occurrence of version = "x.y.z.w";)
get_current_version_from_nix() {
  local file="$1"
  grep -Eo 'version\s*=\s*"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' "$file" \
    | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
    | head -n1
}

# List candidate versions from the CDN HTML index, highest to lowest
get_all_versions() {
  local base="$1"
  curl -fsSL "$base" \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
    | sort -Vu \
    | sort -Vr
}

# Check whether the URL exists (HTTP 200)
url_exists() {
  local url="$1"
  local status
  status="$(curl -sSL -o /dev/null -w "%{http_code}" "$url" || true)"
  [[ "$status" == "200" ]]
}

# Return the first (newest) version with a valid .deb
get_latest_valid_version() {
  local base="$1"
  local kind="$2"   # stable | gx
  local v deb

  while read -r v; do
    [[ -z "$v" ]] && continue
    if [[ "$kind" == "stable" ]]; then
      deb="${base}${v}/linux/opera-stable_${v}_amd64.deb"
    else
      deb="${base}${v}/linux/opera-gx-stable_${v}_amd64.deb"
    fi

    if url_exists "$deb"; then
      echo "$v"
      return 0
    else
      warn "Discarding $v (no valid Linux .deb)"
    fi
  done < <(get_all_versions "$base")

  return 1
}

main() {
  local stable_base="https://download3.operacdn.com/ftp/pub/opera/desktop/"
  local gx_base="https://download3.operacdn.com/ftp/pub/opera_gx/"

  local current_stable current_gx latest_stable latest_gx update_needed
  current_stable="$(get_current_version_from_nix one.nix)"
  current_gx="$(get_current_version_from_nix gx.nix)"

  if [[ -z "${current_stable:-}" || -z "${current_gx:-}" ]]; then
    echo "Could not read the current version from one.nix/gx.nix" >&2
    exit 1
  fi

  info "Current Opera Stable version: $current_stable"
  info "Current Opera GX version:     $current_gx"

  latest_stable="$(get_latest_valid_version "$stable_base" "stable" || true)"
  latest_gx="$(get_latest_valid_version "$gx_base" "gx" || true)"

  if [[ -z "${latest_stable:-}" || -z "${latest_gx:-}" ]]; then
    echo "Could not determine the latest valid version from the CDN" >&2
    exit 1
  fi

  info "Latest valid Stable version: $latest_stable"
  info "Latest valid GX version:     $latest_gx"

  update_needed=false
  [[ "$latest_stable" != "$current_stable" ]] && update_needed=true
  [[ "$latest_gx" != "$current_gx" ]] && update_needed=true

  echo "stable_current=$current_stable" >> "$GITHUB_OUTPUT"
  echo "stable_latest=$latest_stable" >> "$GITHUB_OUTPUT"
  echo "gx_current=$current_gx" >> "$GITHUB_OUTPUT"
  echo "gx_latest=$latest_gx" >> "$GITHUB_OUTPUT"
  echo "update_needed=$update_needed" >> "$GITHUB_OUTPUT"

  if [[ "$update_needed" == "true" ]]; then
    info "New version available: update.sh must be run"
  else
    info "No version changes"
  fi
}

main "$@"