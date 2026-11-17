#!/usr/bin/env bash
set -euo pipefail
plugin_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
shell_dir="${OMARCHY_PATH:-/usr/share/omarchy}/shell"
qml_linter="${QMLLINT:-/usr/lib/qt6/bin/qmllint}"
[[ -d "$shell_dir/Commons" && -d "$shell_dir/Ui" ]] || {
  echo "Omarchy shell imports not found in $shell_dir" >&2
  exit 1
}
# Quickshell supplies the qs namespace at runtime. Give qmllint the same
# mapping without adding symlinks to the plugin or modifying system files.
import_dir=$(mktemp -d "${TMPDIR:-/tmp}/amnezia-qmllint.XXXXXX")
trap 'rm -rf -- "$import_dir"' EXIT
ln -s -- "$shell_dir" "$import_dir/qs"
"$qml_linter" --ignore-settings --max-warnings 0 -I "$import_dir" "$plugin_dir/Panel.qml"
