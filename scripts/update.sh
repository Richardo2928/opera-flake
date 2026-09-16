#!/usr/bin/env bash
# update.sh v1.0.2 (Definitive Version)

# 1. strict mode: fail on errors, unset variables, or pipeline failures
set -euo pipefail

info() { echo -e "\e[32m[INFO]\e[0m $*"; }
warn() { echo -e "\e[33m[WARN]\e[0m $*"; }

# 2. Hash security validation
is_valid_sri() {
  [[ "${1:-}" =~ ^sha256-[A-Za-z0-9+/=]+$ ]]
}

# 3. Safely update the .nix file
update_nix_file() {
  local file="$1"
  local version="$2"
  local hash="$3"

  [[ -n "${version:-}" ]] || { echo "::error::Empty version"; exit 1; }
  [[ -n "${hash:-}" ]] || { echo "::error::Empty hash"; exit 1; }
  is_valid_sri "$hash" || { echo "::error::Invalid hash detected: $hash"; exit 1; }

  # Robust sed commands that preserve the original spacing and format
  sed -Ei "s|^([[:space:]]*version[[:space:]]*=[[:space:]]*\").*(\";[[:space:]]*)$|\1${version}\2|" "$file"
  sed -Ei "s|^([[:space:]]*hash[[:space:]]*=[[:space:]]*\").*(\";[[:space:]]*)$|\1${hash}\2|" "$file"
  
  info "$file updated to v${version}"
}

# 4. Get the Nix hash
get_nix_hash() {
  local url="$1"
  info "Downloading and calculating hash for: $url"
  local raw_hash
  raw_hash=$(nix-prefetch-url --type sha256 "$url")
  nix hash to-sri --type sha256 "$raw_hash"
}

# ==========================================
# 5. Main logic: Opera Stable
# ==========================================
info "Looking for an update for Opera Stable..."
STABLE_BASE="https://download3.operacdn.com/ftp/pub/opera/desktop/"

# Get versions sorted from highest to lowest
mapfile -t STABLE_VERSIONS < <(curl -fsSL "$STABLE_BASE" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -V -r)

for OPERA_VERSION in "${STABLE_VERSIONS[@]}"; do
  OPERA_URL="${STABLE_BASE}${OPERA_VERSION}/linux/opera-stable_${OPERA_VERSION}_amd64.deb"
  
  # Check whether the file exists (HTTP 200) without downloading it
  STATUS=$(curl -fsSL -o /dev/null -w "%{http_code}" "$OPERA_URL" || true)
  
  if [[ "$STATUS" == "200" ]]; then
    info "Found valid version: $OPERA_VERSION"
    OPERA_HASH=$(get_nix_hash "$OPERA_URL")
    update_nix_file "one.nix" "$OPERA_VERSION" "$OPERA_HASH"
    break # Exit the loop after finding the first valid version
  else
    warn "Version $OPERA_VERSION has no Linux .deb (HTTP $STATUS). Trying the previous version..."
  fi
done

# ==========================================
# 6. Main logic: Opera GX
# ==========================================
info "Looking for an update for Opera GX..."
GX_BASE="https://download3.operacdn.com/ftp