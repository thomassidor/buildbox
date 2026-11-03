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
#   rc.sh logs <folder> [lines]           the end of a folder's Remote Control screen and its log lines
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
UPDATE_EVERY="${UPDATE_EVERY:-3600}"   # seconds between pulls of this repo; 0 turns them off
BOX_HOME="${BOX_HOME:-$WORK/home}"
export TERM="${TERM:-xterm-256color}"

mkdir -p "$STATE"
touch "$LIST"

log() { echo "$(date '+%F %T') $*" | tee -a "$STATE/rc.log" >&2; }
die() { echo "$*" >&2; exit 1; }

# The home folder lives on the volume, so the logins (Claude, git, Homey CLI...) survive a
# re-created container. The first time, it starts as a copy of the container's own.
if [ "$HOME" != "$BOX_HOME" ]; then
  if [ ! -d "$BOX_HOME" ]; then
    mkdir -p "$BOX_HOME" && cp -a "$HOME/." "$BOX_HOME/" 2>/dev/null
    log "home: $BOX_HOME made from $HOME"
  fi
  export HOME="$BOX_HOME"
fi

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

# The supervisor and a clone or add run at the same time can both find a folder not running;
# the lock makes the second one see the first one's window, so a folder never gets two.
start() {
  # tmux's server lives on and would keep the lock, so what start_window runs gets it closed.
  ( flock 9 && { running "$1" || start_window "$1" 9>&-; } ) 9>"$STATE/start.lock"
}

start_window() {
  local dir="$1" name cmd
  name="$(window "$dir")"
  [ -d "$dir" ] || { log "$dir is missing; skipped"; return 1; }
  trust "$dir"
  # A tmux window gets the tmux server's environment, not ours, so the settings go along.
  printf -v cmd '%q ' env "HOME=$HOME" "WORK=$WORK" "STATE=$STATE" "BOX_HOME=$BOX_HOME" \
    "CLAUDE_BIN=$CLAUDE_BIN" "TMUX_SESSION=$TMUX_SESSION" bash "$BOX/rc.sh" run "$dir"
  if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    tmux new-window -d -t "$TMUX_SESSION" -n "$name" "$cmd"
  else
    tmux new-session -d -s "$TMUX_SESSION" -n "$name" "$cmd"
  fi
  log "$name: started in $dir"
}

# What runs in a folder's window: its Remote Control, started again when it exits; supervise
# brings back the window itself. One that keeps exiting right away (a login that expired, a
# question nobody answers) is retried less and less often, up to every 5 minutes.
run() {
  local dir="$1" name began took code quick=0 wait
  name="$(window "$dir")"
  cd "$dir" || exit 1
  while true; do
    began=$SECONDS
    "$CLAUDE_BIN" remote-control
    code=$? took=$((SECONDS - began))
    if [ "$took" -lt 60 ]; then quick=$((quick + 1)); else quick=0; fi
    wait=$((5 << (quick > 6 ? 6 : quick))); [ "$wait" -gt 300 ] && wait=300
    [ "$quick" -le 1 ] && wait=5
    log "$name: remote-control exited ($code) after ${took}s, restarting in ${wait}s"
    [ "$quick" -eq 3 ] && log "$name: keeps exiting right away; see rc.sh logs $name"
    sleep "$wait"
  done
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

# What the container lacks after it's re-created (the volume keeps the rest).
install_missing() {
  command -v tmux >/dev/null || { log "installing tmux"; apt-get update -q && apt-get install -y -q tmux; } ||
    log "installing tmux failed"
  command -v "$CLAUDE_BIN" >/dev/null || { log "installing Claude Code"; npm install -g @anthropic-ai/claude-code; } ||
    log "installing Claude Code failed"
  [ -n "$(git config --global credential.helper)" ] || git config --global credential.helper store
}

# Pulls this repo; a new rc.sh takes over the supervisor (the windows keep running).
update() {
  local before after
  before="$(git -C "$BOX" rev-parse HEAD 2>/dev/null)" || return 0
  git -C "$BOX" pull --ff-only -q >/dev/null 2>&1 || { log "update: pulling $BOX failed (local changes?)"; return 0; }
  after="$(git -C "$BOX" rev-parse HEAD)"
  [ "$before" = "$after" ] && return 0
  log "update: $BOX at ${after:0:7}"
  if ! git -C "$BOX" diff --quiet "$before" "$after" -- rc.sh; then
    log "update: rc.sh changed, supervisor restarting"
    exec bash "$BOX/rc.sh" supervise
  fi
}

# rc.log keeps its last 1000 lines.
trim_log() {
  local f="$STATE/rc.log"
  [ -f "$f" ] && [ "$(wc -l < "$f")" -gt 2000 ] && tail -n 1000 "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  return 0
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
    install_missing
    last_update=-$UPDATE_EVERY
    while true; do
      if [ "$UPDATE_EVERY" -gt 0 ] && [ $((SECONDS - last_update)) -ge "$UPDATE_EVERY" ]; then
        last_update=$SECONDS; update
      fi
      ensure; trim_log
      sleep "$CHECK_EVERY" & wait $!
    done
    ;;
  run)
    run "${2:?usage: rc.sh run <folder>}"
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
  logs)
    name="$(basename "${2:?usage: rc.sh logs <folder> [lines]}")"
    lines="${3:-40}"
    echo "== $name: the end of its screen"
    if tmux list-windows -t "$TMUX_SESSION" -F '#{window_name}' 2>/dev/null | grep -qx "$name"; then
      tmux capture-pane -p -J -t "$TMUX_SESSION:$name" -S "-$lines" | awk 'NF { while (n) { print ""; n-- } print; next } { n++ }'
    else
      echo "(no window: rc.sh list shows whether it runs)"
    fi
    echo "== $name in rc.log"
    grep -F " $name: " "$STATE/rc.log" | tail -n 10
    ;;
  list)
    while read -r dir; do
      if running "$dir"; then echo "running  $dir"; else echo "stopped  $dir"; fi
    done < <(folders)
    ;;
  *)
    sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
