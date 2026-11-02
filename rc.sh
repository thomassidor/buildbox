#!/usr/bin/env bash
# The NAS build box's Remote Control sessions (see README.md).
#
#   rc.sh supervise                       the container's command: keeps a `claude remote-control`
#                                         running in tmux for this folder and every one on the list
#   rc.sh clone <git-url> [name] [branch] clones a repo to /work/<name> (default: the repo's name),
#                                         sets it up and starts its Remote Control
#   rc.sh add <repo> <name> [branch]      a git worktree /work/<repo>-<name> of /work/<repo>, on a
#                                         new branch <name> from origin/<branch> (default: the
#                                         repo's current branch), set up, with its Remote Control
#   rc.sh remove <folder>                 stops a folder's Remote Control and takes it off the list
#                                         (the folder stays; this one can't be removed)
#   rc.sh list                            the folders and whether each one's Remote Control runs
#
# One `claude remote-control` serves every session in its folder, so a worktree is only for
# work that needs its own copy of the code. Setting up a folder runs its .buildbox/setup.sh
# if it has one, else `npm ci` (or `npm install` without a lockfile) for a Node project.
set -u

BOX="$(cd "$(dirname "$0")" && pwd)"
WORK="${WORK:-/work}"
STATE="${STATE:-$BOX/state}"
LIST="$STATE/folders"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
TMUX_SESSION="${TMUX_SESSION:-rc}"
CHECK_EVERY="${CHECK_EVERY:-15}"
export TERM="${TERM:-xterm-256color}"

mkdir -p "$STATE"
touch "$LIST"

log() { echo "$(date '+%F %T') $*" | tee -a "$STATE/rc.log" >&2; }
die() { echo "$*" >&2; exit 1; }

# This folder first, always, then the list.
folders() { echo "$BOX"; grep -v '^\s*\(#\|$\)' "$LIST" | grep -vx "$BOX"; }

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
  # The loop inside restarts it when it exits; supervise brings back the window itself.
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

setup() {
  local dir="$1"
  if [ -x "$dir/.buildbox/setup.sh" ]; then (cd "$dir" && ./.buildbox/setup.sh)
  elif [ -f "$dir/package-lock.json" ]; then (cd "$dir" && npm ci)
  elif [ -f "$dir/package.json" ]; then (cd "$dir" && npm install)
  fi || die "setting up $dir failed"
}

# A folder name: no slashes, no leading dot, nothing a shell or tmux would trip on.
plain() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "'$1': letters, digits, . _ - only"; }

# Two folders with one name would share a tmux window.
unique() {
  local dir="$1" other
  while read -r other; do
    [ "$other" != "$dir" ] && [ "$(window "$other")" = "$(window "$dir")" ] &&
      die "$(window "$dir") is already the name of $other"
  done < <(folders)
  return 0
}

supervise_folder() {
  local dir="$1"
  unique "$dir"
  grep -qx "$dir" "$LIST" || echo "$dir" >> "$LIST"
  running "$dir" || start "$dir"
  echo "$dir: Remote Control running"
}

case "${1:-}" in
  supervise)
    trap 'log "supervisor stopped"; exit 0' TERM INT
    log "supervisor started"
    while true; do ensure; sleep "$CHECK_EVERY" & wait $!; done
    ;;
  clone)
    url="${2:?usage: rc.sh clone <git-url> [name] [branch]}"
    name="${3:-$(basename "${url%/}" .git)}"
    plain "$name"
    dir="$WORK/$name"
    if [ ! -d "$dir" ]; then
      git clone ${4:+-b "$4"} "$url" "$dir" || die "cloning $url failed"
      setup "$dir"
    fi
    supervise_folder "$dir"
    ;;
  add)
    repo="${2:?usage: rc.sh add <repo> <name> [branch]}"
    name="${3:?usage: rc.sh add <repo> <name> [branch]}"
    plain "$repo"; plain "$name"
    src="$WORK/$repo"
    git -C "$src" rev-parse --git-dir >/dev/null 2>&1 || die "$src isn't a git clone (rc.sh clone it first)"
    dir="$WORK/$repo-$name"
    if [ ! -d "$dir" ]; then
      base="${4:-$(git -C "$src" rev-parse --abbrev-ref HEAD)}"
      git -C "$src" fetch origin "$base" || die "fetching $base failed"
      git -C "$src" worktree add -b "$name" "$dir" "origin/$base" 2>/dev/null ||
        git -C "$src" worktree add "$dir" "$name" || die "making the worktree failed"
      setup "$dir"
    fi
    supervise_folder "$dir"
    ;;
  remove)
    name="${2:?usage: rc.sh remove <folder>}"
    dir="$WORK/$(basename "$name")"
    [ "$dir" = "$BOX" ] && die "this folder always keeps its Remote Control"
    grep -qx "$dir" "$LIST" || die "$dir isn't on the list"
    grep -vx "$dir" "$LIST" > "$LIST.tmp"; mv "$LIST.tmp" "$LIST"
    stop "$dir"
    echo "$dir: off the list (the folder is still there)"
    ;;
  list)
    while read -r dir; do
      if running "$dir"; then echo "running  $dir"; else echo "stopped  $dir"; fi
    done < <(folders)
    ;;
  *)
    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
