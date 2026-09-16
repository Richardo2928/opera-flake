#!/usr/bin/env bash
set -euo pipefail

info() { echo -e "\e[32m[INFO]\e[0m $*"; }
warn() { echo -e "\e[33m[WARN]\e[0m $*"; }

# Extrae versión desde un archivo .nix (primera ocurrencia de version = "x.y.z.w";)
get_current_version_from_nix() {
  local file="$1"
  grep -Eo 'version\s*=\s*"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' "$file" \
    | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
    | head -n1
}

# Lista versiones candidatas desde el índice HTML del CDN, de mayor a menor
get_all_versions() {
  local base="$1"
  curl -fsSL "$base" \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
    | sort -Vu \
    | sort -Vr
}

# Verifica si la URL existe (HTTP 200)
url_exists() {
  local url="$1"
  local status
  status="$(curl -fsSL -o /dev/null -w "%{http_code}" "$url" || true)"
  [[ "$status" == "200" ]]
}

# Retorna la primera versión (más nueva) que tenga .deb válido
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
      warn "Descartando $v (sin .deb Linux válido)"
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
    echo "No pude leer versión actual desde one.nix/gx.nix" >&2
    exit 1
  fi

  info "Versión actual Opera Stable: $current_stable"
  info "Versión actual Opera GX:     $current_gx"

  latest_stable="$(get_latest_valid_version "$stable_base" "stable" || true)"
  latest_gx="$(get_latest_valid_version "$gx_base" "gx" || true)"

  if [[ -z "${latest_stable:-}" || -z "${latest_gx:-}" ]]; then
    echo "No pude determinar última versión válida desde CDN" >&2
    exit 1
  fi

  info "Última versión válida Stable: $latest_stable"
  info "Última versión válida GX:     $latest_gx"

  update_needed=false
  [[ "$latest_stable" != "$current_stable" ]] && update_needed=true
  [[ "$latest_gx" != "$current_gx" ]] && update_needed=true

  echo "stable_current=$current_stable" >> "$GITHUB_OUTPUT"
  echo "stable_latest=$latest_stable" >> "$GITHUB_OUTPUT"
  echo "gx_current=$current_gx" >> "$GITHUB_OUTPUT"
  echo "gx_latest=$latest_gx" >> "$GITHUB_OUTPUT"
  echo "update_needed=$update_needed" >> "$GITHUB_OUTPUT"

  if [[ "$update_needed" == "true" ]]; then
    info "Hay nueva versión: se debe ejecutar update.sh"
  else
    info "No hay cambios de versión"
  fi
}

main "$@"