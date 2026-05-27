#!/usr/bin/env bash
# uninstall.sh — remove Loom from ~/.claude/skills/loom/
#
# Default: keeps state/ (your accumulated reflections, sessions, research briefs).
# Pass --purge to wipe state too. settings.json hooks block is removed by default;
# pass --keep-hooks to leave it in place (only useful if you're keeping the scripts
# in a different location).

set -euo pipefail

DEST_DIR="${HOME}/.claude/skills/loom"
SETTINGS="${HOME}/.claude/settings.json"

say()   { printf '\033[36m[loom]\033[0m %s\n' "$*"; }
warn()  { printf '\033[33m[loom]\033[0m %s\n' "$*" >&2; }
fatal() { printf '\033[31m[loom]\033[0m %s\n' "$*" >&2; exit 1; }
hr()    { printf '%s\n' "────────────────────────────────────────────────────────"; }

PURGE_STATE=0
REMOVE_HOOKS=1
ASSUME_YES=0
while [ $# -gt 0 ]; do
    case "$1" in
        --purge)         PURGE_STATE=1 ;;
        --keep-hooks)    REMOVE_HOOKS=0 ;;
        -y|--yes)        ASSUME_YES=1 ;;
        -h|--help)
            cat <<EOF
Usage: $0 [options]

Options:
  --purge        Also delete ~/.claude/skills/loom/state/ (reflections,
                 sessions, research briefs, hooks log). Default: state preserved.
  --keep-hooks   Leave the hooks block in ~/.claude/settings.json. Default: removed.
  -y, --yes      Skip confirmation prompt.
  -h, --help     Show this help.
EOF
            exit 0
            ;;
        *) warn "unknown flag: $1"; exit 2 ;;
    esac
    shift
done

hr
say "Loom uninstaller"
hr

if [ ! -d "${DEST_DIR}" ]; then
    say "Loom is not installed (${DEST_DIR} does not exist). Nothing to do."
    exit 0
fi

# ────────────────────────────────────────────────────────────────────────────
#  Confirm
# ────────────────────────────────────────────────────────────────────────────
say "About to remove:"
say "  - ${DEST_DIR}/SKILL.md"
say "  - ${DEST_DIR}/scripts/"
if [ "${PURGE_STATE}" = "1" ]; then
    say "  - ${DEST_DIR}/state/  (purge)"
else
    say "  - (keeping ${DEST_DIR}/state/ — pass --purge to wipe it)"
fi
if [ "${REMOVE_HOOKS}" = "1" ]; then
    say "  - hooks block in ${SETTINGS}"
fi

if [ "${ASSUME_YES}" = "0" ]; then
    printf 'Continue? [y/N] '
    read -r answer
    case "${answer:-N}" in
        [Yy]*) ;;
        *) say "Aborted."; exit 0 ;;
    esac
fi

# ────────────────────────────────────────────────────────────────────────────
#  Hooks removal
# ────────────────────────────────────────────────────────────────────────────
if [ "${REMOVE_HOOKS}" = "1" ] && [ -f "${SETTINGS}" ]; then
    if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "${SETTINGS}" 2>/dev/null; then
        BACKUP="${SETTINGS}.bak.loom-uninstall-$(date +%Y%m%d-%H%M%S)"
        cp "${SETTINGS}" "${BACKUP}"
        say "settings.json backed up to: ${BACKUP}"

        python3 - "${SETTINGS}" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    cfg = json.load(f)

hooks = cfg.get("hooks", {})
removed = 0

def is_loom(cmd):
    return "/.claude/skills/loom/scripts/hooks/" in (cmd or "")

for slot_name in list(hooks.keys()):
    new_groups = []
    for group in hooks[slot_name] or []:
        keep_hooks_in_group = []
        for h in group.get("hooks", []) or []:
            if h.get("type") == "command" and is_loom(h.get("command", "")):
                removed += 1
                continue
            keep_hooks_in_group.append(h)
        if keep_hooks_in_group:
            new_group = dict(group)
            new_group["hooks"] = keep_hooks_in_group
            new_groups.append(new_group)
    if new_groups:
        hooks[slot_name] = new_groups
    else:
        del hooks[slot_name]

if not hooks:
    cfg.pop("hooks", None)
else:
    cfg["hooks"] = hooks

with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
print(f"loom-hooks: removed {removed} hook(s) from settings.json")
PY
    else
        warn "${SETTINGS} is not valid JSON; skipping hooks removal"
    fi
fi

# ────────────────────────────────────────────────────────────────────────────
#  Files removal
# ────────────────────────────────────────────────────────────────────────────
rm -f "${DEST_DIR}/SKILL.md"
rm -rf "${DEST_DIR}/scripts"
say "removed scripts and SKILL.md"

if [ "${PURGE_STATE}" = "1" ]; then
    rm -rf "${DEST_DIR}/state"
    say "purged state directory"
fi

# Remove the now-empty parent if nothing else lives there
if [ -d "${DEST_DIR}" ] && [ -z "$(ls -A "${DEST_DIR}" 2>/dev/null)" ]; then
    rmdir "${DEST_DIR}"
    say "removed empty ${DEST_DIR}"
elif [ -d "${DEST_DIR}" ]; then
    say "left ${DEST_DIR}/ in place (state preserved)"
fi

hr
say "Loom uninstalled."
if [ "${PURGE_STATE}" = "0" ] && [ -d "${DEST_DIR}/state" ]; then
    say "State preserved at ${DEST_DIR}/state/ — pass --purge next time to remove."
fi
hr
