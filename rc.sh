#!/usr/bin/env bash
# The NAS build box's Remote Control sessions (see README.md).
#
#   rc.sh supervise            the container's command: keeps a `claude remote-control`
#                              running in tmux for every folder in the list, forever
#   rc.sh add <name> [branch]  a git worktree /work/<name> (a new branch <name> from
#                              origin/<branch>, default the main clone's branch), npm ci,
#                              and a Remote Control for it
#   rc.sh remove <name>        stops its Remote Control and takes it off the list
#                              (the worktree stays; `git worktree remove` deletes it)
#   rc.sh list                 the folders and whether each one's Remote Control runs
#
# One `claude remote-control` serves every session in its folder, so a new folder is
# only for work that needs its own copy of the code.
set -u

WORK="${WORK:-/work}"
MAIN="${MAIN:-$WORK/widgetkeeper}"
STATE="${STATE:-$(cd "$(dirname "$0")" && pwd)/state}"
LIST="$STATE/folders"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
TMUX_SESSION="${TMUX_SESSION:-rc}"
CHECK_EVERY="${CHECK_EVERY:-15}"
export TERM="${TERM:-xterm-256color}"

mkdir -p "$STATE"
[ -s "$LIST" ] || echo "$MAIN" > "$LIST"

log() { echo "$(date '+%F %T') $*" | tee -a "$STATE/rc.log" >&2; }

folders() { grep -v '^\s*\(#\|$\)' "$LIST" 2>/dev/null; }

# A window per folder, named after it.
window() { basename "$1"; }

running() {
  tmux has-session -t "$TMUX_SESSION" 2>/dev/null &&
    tmux list-windows -t "$TMUX_SESSION" -F '#{window_name}' | grep -qx "$(window "$1")"
}

# Claude Code asks whether to trust a folder the first time; a supervised one has
# nobody to answer, so it's marked trusted (the key Claude Code keeps in ~/.claude.json).
trust() {
  node -e '
    const fs = require("fs"), f = require("os").homedir() + "/.claude.json";
    let c = {}; try { c = JSON.parse(fs.readFileSync(f, "utf8")); } catch {}
    c.projects ??= {}; c.projects[process.argv[1]] ??= {};
    c.projects[process.argv[1]].hasTrustDialogAccepted = true;
    fs.writeFileSync(f, JSON.stringify(c, null, 2));
  ' "$1" 2>/dev/null || log "couldn't mark $1 trusted"
}

start() {
  local dir="$1" name
  name="$(window "$dir")"
  [ -d "$dir" ] || { log "$dir is missing; skipped"; return 1; }
  trust "$dir"
  # The loop inside restarts it when it exits; supervise() brings back the window itself.
  local cmd="cd '$dir' && while true; do $CLAUDE_BIN remote-control; echo \"\$(date '+%F %T') $name: remote-control exited (\$?), restarting\" >> '$STATE/rc.log'; sleep 5; done"
  if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    tmux new-window -d -t "$TMUX_SESSION" -n "$name" "$cmd"
  else
    tmux new-session -d -s "$TMUX_SESSION" -n "$name" "$cmd"
  fi
  log "$name: started in $dir"
}

stop() {
  local name
  name="$(window "$1")"
  tmux kill-window -t "$TMUX_SESSION:$name" 2>/dev/null && log "$name: stopped"
}

ensure() {
  local dir
  while read -r dir; do running "$dir" || start "$dir"; done < <(folders)
}

case "${1:-}" in
  supervise)
    trap 'log "supervisor stopped"; exit 0' TERM INT
    log "supervisor started"
    while true; do ensure; sleep "$CHECK_EVERY" & wait $!; done
    ;;
  add)
    name="${2:?usage: rc.sh add <name> [branch]}"
    case "$name" in */*|.*|'') echo "a plain folder name, please" >&2; exit 1 ;; esac
    dir="$WORK/$name"
    if [ ! -d "$dir" ]; then
      base="${3:-$(git -C "$MAIN" rev-parse --abbrev-ref HEAD)}"
      git -C "$MAIN" fetch origin "$base" || exit 1
      git -C "$MAIN" worktree add -b "$name" "$dir" "origin/$base" ||
        git -C "$MAIN" worktree add "$dir" "$name" || exit 1
      (cd "$dir" && npm ci) || { echo "npm ci failed in $dir" >&2; exit 1; }
    fi
    grep -qx "$dir" "$LIST" || echo "$dir" >> "$LIST"
    running "$dir" || start "$dir"
    echo "$dir: Remote Control running"
    ;;
  remove)
    name="${2:?usage: rc.sh remove <name>}"
    dir="$WORK/$name"
    [ "$dir" = "$MAIN" ] && { echo "the main folder always keeps one" >&2; exit 1; }
    grep -vx "$dir" "$LIST" > "$LIST.tmp"; mv "$LIST.tmp" "$LIST"
    stop "$dir"
    echo "$dir: off the list (the worktree is still there)"
    ;;
  list)
    while read -r dir; do
      if running "$dir"; then echo "running  $dir"; else echo "stopped  $dir"; fi
    done < <(folders)
    ;;
  *)
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
