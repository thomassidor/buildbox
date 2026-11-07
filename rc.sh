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
#   rc.sh login                           logs Claude Code and the GitHub CLI in (what isn't already),
#                                         has git use gh's login and sets git's name: a new box's one step
#   rc.sh install                         installs what the container lacks: tmux, Claude Code, the
#                                         GitHub CLI (gh), python (python-is-python3, Pillow), and what
#                                         state/extras lists (`chromium`: a browser for renders, also on the PATH)
#
# One `claude remote-control` serves every session in its folder, so a worktree is only for
# work that needs its own copy of the code. Setting up a folder runs its .buildbox/setup.sh
# if it has one, else `npm ci` (or `npm install` without a lockfile) for a Node project.
set -u

# No command (or an unknown one): only the help, before anything touches the disk.
case "${1:-}" in
  supervise|run|clone|add|remove|list|logs|login|install) ;;
  *) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac

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

# The tmux ID of a window by its name. tmux can't target a name with a dot (wk-1.2.0): it reads
# what follows the dot as a pane.
window_id() {
  tmux list-windows -t "$TMUX_SESSION" -F '#{window_id} #{window_name}' 2>/dev/null |
    while read -r id name; do [ "$name" = "$1" ] && echo "$id"; done
}

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
    "$CLAUDE_BIN" remote-control --spawn=same-dir
    code=$? took=$((SECONDS - began))
    if [ "$took" -lt 60 ]; then quick=$((quick + 1)); else quick=0; fi
    wait=$((5 << (quick > 6 ? 6 : quick))); [ "$wait" -gt 300 ] && wait=300
    [ "$quick" -le 1 ] && wait=5
    log "$name: remote-control exited ($code) after ${took}s, restarting in ${wait}s"
    if [ "$quick" -eq 3 ]; then
      logged_in || log "$name: Claude Code isn't logged in; run rc.sh login in a terminal"
      log "$name: keeps exiting right away; see rc.sh logs $name"
    fi
    sleep "$wait"
  done
}

stop() {
  local name id
  name="$(window "$1")"
  id="$(window_id "$name")"
  [ -n "$id" ] && tmux kill-window -t "$id" 2>/dev/null && log "$name: stopped"
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

# What the container lacks after it's re-created (the volume keeps the rest). Locked, as a login
# typed into a new container's terminal can come while the supervisor is still installing.
install_missing() {
  ( flock 9 && install_missing_now 9>&- ) 9>"$STATE/install.lock"
}

install_missing_now() {
  command -v tmux >/dev/null || { log "installing tmux"; apt-get update -q && apt-get install -y -q tmux; } ||
    log "installing tmux failed"
  command -v "$CLAUDE_BIN" >/dev/null || { log "installing Claude Code"; npm install -g @anthropic-ai/claude-code; } ||
    log "installing Claude Code failed"
  command -v gh >/dev/null || install_gh || log "installing the GitHub CLI failed"
  # `python` as on the PC (python -m http.server) and Pillow for the odd image snippet.
  { command -v python >/dev/null && python3 -c 'import PIL' 2>/dev/null; } ||
    { log "installing python-is-python3 and python3-pil"; apt-get update -q && apt-get install -y -q python-is-python3 python3-pil; } ||
    log "installing python failed"
  extra chromium && install_chromium
  return 0
}

# The GitHub CLI, from GitHub's apt repository. Its login (~/.config/gh) is on the volume, and
# `gh auth setup-git` has git use it for github.com, so only the program needs installing again.
install_gh() {
  log "installing the GitHub CLI"
  local key=/etc/apt/keyrings/githubcli-archive-keyring.gpg
  mkdir -p /etc/apt/keyrings &&
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o "$key" &&
    echo "deb [arch=$(dpkg --print-architecture) signed-by=$key] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list &&
    apt-get update -q && apt-get install -y -q gh
}

# What state/extras asks for, one word a line (an opt-in, as it downloads a lot from outside).
extra() { grep -qx "$1" "$STATE/extras" 2>/dev/null; }

# chromium: Playwright's Chromium headless shell for renders (chromium-render here), its system libraries
# and the fonts the pages use, and /usr/local/bin/chromium linked to chromium-render. The browser lands in
# ~/.cache on the volume, so a re-created container only needs the libraries, the fonts and the link again.
PLAYWRIGHT_VERSION="${PLAYWRIGHT_VERSION:-1.64.1}"
install_chromium() {
  local fonts="fonts-roboto fonts-liberation2 fonts-noto-color-emoji" pw=(npx -y "playwright@$PLAYWRIGHT_VERSION")
  # On the PATH as `chromium` too, so a session looking for a browser finds one (not `msedge`: it isn't Edge).
  [ "$(readlink /usr/local/bin/chromium 2>/dev/null)" = "$BOX/chromium-render" ] ||
    ln -sfn "$BOX/chromium-render" /usr/local/bin/chromium || log "linking /usr/local/bin/chromium failed"
  "$BOX/chromium-render" --version >/dev/null 2>&1 && dpkg -s $fonts >/dev/null 2>&1 && return 0
  log "installing Chromium for renders (Playwright $PLAYWRIGHT_VERSION) and fonts"
  { "${pw[@]}" install chromium-headless-shell && "${pw[@]}" install-deps chromium-headless-shell &&
    apt-get install -y -q $fonts; } >> "$STATE/install.log" 2>&1 &&
    "$BOX/chromium-render" --version >/dev/null 2>&1 ||
    { log "installing Chromium failed; see state/install.log"; return 0; }
  log "Chromium: $("$BOX/chromium-render" --version 2>/dev/null)"
}

# claude-user.md here is the box's ~/.claude/CLAUDE.md, the instructions of every session in
# every folder: this file is the original, so a change made only there is overwritten.
apply_instructions() {
  [ -f "$BOX/claude-user.md" ] || return 0
  mkdir -p "$HOME/.claude"
  cmp -s "$BOX/claude-user.md" "$HOME/.claude/CLAUDE.md" && return 0
  cp "$BOX/claude-user.md" "$HOME/.claude/CLAUDE.md" &&
    log "instructions: $HOME/.claude/CLAUDE.md updated from claude-user.md"
}

# claude-settings.json here, merged into the box's ~/.claude/settings.json (objects merged,
# lists joined, the rest of that file kept), written only when it changes. New sessions read it.
apply_settings() {
  [ -f "$BOX/claude-settings.json" ] || return 0
  mkdir -p "$HOME/.claude"
  local out
  out="$(node -e '
    const fs = require("fs"), [src, dst] = process.argv.slice(1);
    let text = "{}"; try { text = fs.readFileSync(dst, "utf8"); } catch {}
    let current; try { current = JSON.parse(text); } catch { console.log("broken"); process.exit(); }
    const isObj = v => v && typeof v === "object" && !Array.isArray(v);
    const merge = (a, b) => {
      for (const [k, v] of Object.entries(b)) {
        if (isObj(v) && isObj(a[k])) merge(a[k], v);
        else if (Array.isArray(v) && Array.isArray(a[k])) a[k] = [...new Set([...a[k], ...v])];
        else a[k] = v;
      }
      return a;
    };
    const after = merge(JSON.parse(text), JSON.parse(fs.readFileSync(src, "utf8")));
    if (JSON.stringify(current) !== JSON.stringify(after)) {
      fs.writeFileSync(dst, JSON.stringify(after, null, 2) + "\n");
      console.log("changed");
    }
  ' "$BOX/claude-settings.json" "$HOME/.claude/settings.json" 2>&1)" || true
  case "$out" in
    changed) log "settings: $HOME/.claude/settings.json updated from claude-settings.json" ;;
    broken) log "settings: $HOME/.claude/settings.json isn't valid JSON; left as it is" ;;
    ?*) log "settings: couldn't apply claude-settings.json: $out" ;;
  esac
  return 0
}

# Pulls this repo; a new rc.sh takes over the supervisor (the windows keep running).
update() {
  local before after
  before="$(git -C "$BOX" rev-parse HEAD 2>/dev/null)" || return 0
  git -C "$BOX" pull --ff-only -q >/dev/null 2>&1 || { log "update: pulling $BOX failed (local changes?)"; return 0; }
  after="$(git -C "$BOX" rev-parse HEAD)"
  [ "$before" = "$after" ] && return 0
  log "update: $BOX at ${after:0:7}"
  apply_settings
  apply_instructions
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

logged_in() { "$CLAUDE_BIN" auth status >/dev/null 2>&1; }

# The one step a new box needs from someone: the logins, each only when it's missing. Claude Code's
# and gh's each print a link to open and take a code back; both stay in the home folder on the volume.
login() {
  local fresh=0 dir
  command -v "$CLAUDE_BIN" >/dev/null && command -v gh >/dev/null && command -v tmux >/dev/null ||
    { echo "installing what's missing first (a minute or two)"; install_missing; }
  if logged_in; then echo "Claude Code: logged in"
  else
    echo "== Claude Code: open the link, log in, paste the code back"
    "$CLAUDE_BIN" auth login || die "Claude Code's login failed; run rc.sh login again"
    logged_in || die "Claude Code still isn't logged in; run rc.sh login again"
    fresh=1; log "login: Claude Code logged in"
  fi
  if gh auth status -h github.com >/dev/null 2>&1; then echo "GitHub: logged in"
  else
    echo "== GitHub: enter the code it shows at https://github.com/login/device"
    gh auth login -h github.com -p https -w -s workflow || die "GitHub's login failed; run rc.sh login again"
    log "login: GitHub logged in"
  fi
  gh auth setup-git || die "gh auth setup-git failed"
  git config --global user.name >/dev/null || git config --global user.name Claude
  git config --global user.email >/dev/null || git config --global user.email noreply@anthropic.com
  # The Remote Controls were waiting for the login, up to 5 minutes apart: started again now, so
  # they come up at once. None of them was connected, so no session drops.
  if [ "$fresh" = 1 ]; then
    while read -r dir; do stop "$dir"; done < <(folders)
    if [ -n "$(pgrep -f 'rc\.sh supervise' 2>/dev/null)" ]; then
      echo "the Remote Controls start again within ${CHECK_EVERY}s"
    else
      echo "no supervisor running: the container's command starts it"
    fi
  fi
  echo "== done"
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
    logged_in || log "Claude Code isn't logged in; run rc.sh login in a terminal"
    apply_settings
    apply_instructions
    last_update=-$UPDATE_EVERY
    while true; do
      if [ "$UPDATE_EVERY" -gt 0 ] && [ $((SECONDS - last_update)) -ge "$UPDATE_EVERY" ]; then
        last_update=$SECONDS; update
      fi
      ensure; trim_log
      sleep "$CHECK_EVERY" & wait $!
    done
    ;;
  install)
    install_missing
    ;;
  login)
    login
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
    id="$(window_id "$name")"
    if [ -n "$id" ]; then
      tmux capture-pane -p -J -t "$id" -S "-$lines" | awk 'NF { while (n) { print ""; n-- } print; next } { n++ }'
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
    sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
