#!/usr/bin/env bash
# update.sh v1.0.3

set -euo pipefail

info() { echo -e "\e[32m[INFO]\e[0m $*"; }
warn() { echo -e "\e[33m[WARN]\e[0m $*"; }

# ==========================================
# Hash validation
# ==========================================
is_valid_sri() {
  [[ "${1:-}" =~ ^sha256-[A-Za-z0-9+/=]+$ ]]
}

is_valid_hash() {
  is_valid_sri "${1:-}"
}

# ==========================================
# Update the .nix file
# ==========================================
update_nix_file() {
  local file="$1"
  local version="$2"
  local hash="$3"

  [[ -n "${version:-}" ]] || { echo "::error::Empty version"; exit 1; }
  [[ -n "${hash:-}" ]] || { echo "::error::Empty hash"; exit 1; }
  is_valid_sri "$hash" || { echo "::error::Invalid hash detected: $hash"; exit 1; }

  sed -Ei "s|^([[:space:]]*version[[:space:]]*=[[:space:]]*\").*(\";[[:space:]]*)$|\1${version}\2|" "$file"
  sed -Ei "s|^([[:space:]]*hash[[:space:]]*=[[:space:]]*\").*(\";[[:space:]]*)$|\1${hash}\2|" "$file"

  info "$file updated to v${version}"
}

# ==========================================
# Get the Nix hash
# ==========================================
get_nix_hash() {
  local url="$1"
  info "Downloading and calculating hash for: $url"
  local raw_hash
  raw_hash=$(nix-prefetch-url --type sha256 "$url")
  nix hash to-sri --type sha256 "$raw_hash"
}

# ==========================================
# Read the current version/hash from the .nix file
# ==========================================
get_current_version_from_nix() {
  local file="$1"
  grep -Eo 'version\s*=\s*"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' "$file" \
    | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
    | head -n1
}

get_current_hash_from_nix() {
  local file="$1"
  grep -Eo 'hash\s*=\s*"[^"]+"' "$file" \
    | grep -Eo '"[^"]+"' \
    | tr -d '"' \
    | head -n1
}

# ==========================================
# List versions from the CDN
# ==========================================
get_all_versions() {
  local base="$1"
  curl -fsSL "$base" \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
    | sort -Vu \
    | sort -Vr
}

# ==========================================
# Check whether a URL exists
# ==========================================
url_exists() {
  local url="$1"
  local status
  status="$(curl -fsSL -o /dev/null -w "%{http_code}" "$url" || true)"
  [[ "$status" == "200" ]]
}

# ==========================================
# Get the first valid version
# ==========================================
get_latest_valid_version() {
  local base="$1"
  local kind="$2"
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

# ==========================================
# Main
# ==========================================
main() {
  local stable_base="https://download3.operacdn.com/ftp/pub/opera/desktop/"
  local gx_base="https://download3.operacdn.com/ftp/pub/opera_gx/"

  local current_stable current_gx latest_stable latest_gx update_needed
  local stable_hash gx_hash
  local force_update="${FORCE_UPDATE:-false}"

  current_stable="$(get_current_version_from_nix one.nix || true)"
  current_gx="$(get_current_version_from_nix gx.nix || true)"
  stable_hash="$(get_current_hash_from_nix one.nix || true)"
  gx_hash="$(get_current_hash_from_nix gx.nix || true)"

  if [[ -z "${current_stable:-}" || -z "${current_gx:-}" ]]; then
    echo "Could not read the current version from one.nix/gx.nix" >&2
    exit 1
  fi

  info "Current Opera Stable version: $current_stable (hash: ${stable_hash:-EMPTY})"
  info "Current Opera GX version:     $current_gx (hash: ${gx_hash:-EMPTY})"

  if ! is_valid_hash "$stable_hash"; then
    warn "Invalid hash detected in one.nix. Forcing update."
    force_update="true"
  fi
  if ! is_valid_hash "$gx_hash"; then
    warn "Invalid hash detected in gx.nix. Forcing update."
    force_update="true"
  fi

  if [[ "$force_update" == "true" ]]; then
    info "Update manually forced."
    update_needed="true"
    latest_stable="$current_stable"
    latest_gx="$current_gx"
  else
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
  fi

  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
      echo "stable_current=$current_stable"
      echo "stable_latest=$latest_stable"
      echo "gx_current=$current_gx"
      echo "gx_latest=$latest_gx"
      echo "update_needed=$update_needed"
    } >> "$GITHUB_OUTPUT"
  fi

  if [[ "$update_needed" != "true" ]]; then
    info "No version changes"
    return 0
  fi

  info "New version or broken hash found: updating .nix files"

  if [[ "$latest_stable" != "$current_stable" || "$force_update" == "true" ]]; then
    local stable_url="${stable_base}${latest_stable}/linux/opera-stable_${latest_stable}_amd64.deb"
    local stable_new_hash
    stable_new_hash="$(get_nix_hash "$stable_url")"
    update_nix_file "one.nix" "$latest_stable" "$stable_new_hash"
  fi

  if [[ "$latest_gx" != "$current_gx" || "$force_update" == "true" ]]; then
    local gx_url="${gx_base}${latest_gx}/linux/opera-gx-stable_${latest_gx}_amd64.deb"
    local gx_new_hash
    gx_new_hash="$(get_nix_hash "$gx_url")"
    update_nix_file "gx.nix" "$latest_gx" "$gx_new_hash"
  fi

  info "Update completed."
}

main "$@"