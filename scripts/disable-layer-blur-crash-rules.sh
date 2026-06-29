#!/usr/bin/env bash
set -euo pipefail

# Hyprland 0.55.x + some AMD iGPU setups can crash in
# CSurfacePassElement::needsLiveBlur()/CMonitor::useFP16() when compositor blur is
# active on layer-shell surfaces during overview/workspace transitions. This
# script disables the dangerous blur path in the user's active Hyprland config.
# It makes timestamped .bak files before editing.

scan_roots=(
  "$HOME/.config/hypr"
  "$HOME/hypr-quickshell/config"
  "$HOME/hypr-quickshell/user-configs/current/hypr"
)

changed=0

for root in "${scan_roots[@]}"; do
  [ -d "$root" ] || continue
  while IFS= read -r -d '' file; do
    if grep -Eq '^[[:space:]]*layerrule[[:space:]]*=[[:space:]]*blur(_popups)?[[:space:]]+' "$file" || \
       python3 - "$file" <<'PYCHECK'
import re
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(errors='ignore')
# Detect an enabled=true line inside a blur { ... } block.
for m in re.finditer(r'(^[ \t]*blur[ \t]*\{[\s\S]*?^[ \t]*\})', text, re.M):
    if re.search(r'^[ \t]*enabled[ \t]*=[ \t]*(true|yes|1)\b', m.group(1), re.M):
        raise SystemExit(0)
raise SystemExit(1)
PYCHECK
    then
      backup="$file.bak.$(date +%Y%m%d%H%M%S)"
      cp "$file" "$backup"
      python3 - "$file" <<'PYEDIT'
import re
import sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text(errors='ignore')

# Comment every active layer blur rule, not only known Quickshell namespaces.
# The crash report is inside Hyprland's layer-surface live-blur path, so any
# blurred layer surface can keep the bug alive.
lines = []
for line in text.splitlines():
    stripped = line.lstrip()
    indent = line[:len(line) - len(stripped)]
    if re.match(r'layerrule\s*=\s*blur(?:_popups)?\s+', stripped):
        if not stripped.startswith('#'):
            lines.append(indent + '# disabled for stability: ' + stripped)
        else:
            lines.append(line)
    else:
        lines.append(line)
text = '\n'.join(lines) + ('\n' if text.endswith('\n') else '')

# Disable compositor blur globally in blur { ... } blocks. This is intentionally
# global because Hyprland's crash is in the shared compositor blur code, not in a
# specific plugin function.
def disable_blur_block(match: re.Match[str]) -> str:
    block = match.group(0)
    new_block = re.sub(
        r'(^[ \t]*enabled[ \t]*=[ \t]*)(true|yes|1)\b',
        r'\1false',
        block,
        flags=re.M,
    )
    if new_block != block and 'Hyprland 0.55.x blur crash hardening' not in new_block:
        new_block = new_block.replace('blur {', '# Hyprland 0.55.x blur crash hardening\n    blur {', 1)
    return new_block

text = re.sub(r'^[ \t]*blur[ \t]*\{[\s\S]*?^[ \t]*\}', disable_blur_block, text, flags=re.M)
path.write_text(text)
PYEDIT
      echo "disabled Hyprland blur crash path in $file"
      echo "backup: $backup"
      changed=1
    fi
  done < <(find "$root" -type f \( -name '*.conf' -o -name '*.snippet' \) -print0)
done

# Also apply the runtime keyword for the current session. A full Hyprland restart
# is still recommended to recreate all layer-shell surfaces cleanly.
if command -v hyprctl >/dev/null 2>&1; then
  hyprctl keyword decoration:blur:enabled false >/dev/null 2>&1 || true
fi

if [ "$changed" -eq 0 ]; then
  echo "no active Hyprland blur rules or enabled blur blocks found"
fi
