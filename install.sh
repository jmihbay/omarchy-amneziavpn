#!/usr/bin/env bash
set -euo pipefail
source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
config_root="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy"
plugin_id="j1z3.amneziaVPN"
destination="$config_root/plugins/$plugin_id"
legacy="$config_root/plugins/local.amnezia"
first_install=0
if [[ ! -f "$destination/manifest.json" && ! -f "$legacy/manifest.json" ]]; then
  first_install=1
fi
omarchy plugin validate "$source_dir"
mkdir -p "$destination/i18n"
cp -- "$source_dir/logo.svg" "$destination/"
cp -- "$source_dir/profile.py" "$destination/"
cp -- "$source_dir/Panel.qml" "$destination/"
cp -- "$source_dir/i18n/en.json" "$source_dir/i18n/ru.json" "$destination/i18n/"
cp -- "$source_dir/manifest.json" "$destination/"
rm -f -- "$destination/AmneziaWidget.qml"
# Migrate the legacy ID in place, retaining section, index and settings.
if [[ -f "$config_root/shell.json" ]] && jq -e '.. | strings | select(. == "local.amnezia")' "$config_root/shell.json" >/dev/null; then
  cp -p -- "$config_root/shell.json" "$config_root/shell.json.before-amnezia-id-migration.bak"
  temporary=$(mktemp "$config_root/shell.json.amnezia.XXXXXX")
  jq 'walk(if type == "string" and . == "local.amnezia" then "j1z3.amneziaVPN" else . end)' "$config_root/shell.json" > "$temporary"
  mv -- "$temporary" "$config_root/shell.json"
fi
if [[ -f "$legacy/manifest.json" ]]; then
  mv -- "$legacy/manifest.json" "$legacy/manifest.json.before-id-migration.bak"
fi
omarchy-shell shell rescanPlugins >/dev/null
discovered=0
for ((attempt = 0; attempt < 40; attempt++)); do
  if omarchy plugin list --json | jq -e 'any(.[]; .id == "j1z3.amneziaVPN")' >/dev/null; then
    discovered=1
    break
  fi
  sleep 0.05
done
if (( ! discovered )); then
  echo "Amnezia plugin was copied, but the shell did not discover it." >&2
  exit 1
fi
# Updates preserve placement and disabled state.
if (( first_install )); then
  omarchy plugin enable "$plugin_id" --section right
else
  echo "Updated $plugin_id; placement and enabled state preserved."
fi
