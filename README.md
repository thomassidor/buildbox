# buildbox

A Docker container on the Synology NAS at home that runs Claude Code with Remote Control for any number of repos, so a Claude Code session in the cloud can work on the home network while I'm away. It started for Widgetkeeper: Athom's cloud relay to the Homey turns down app uploads (every `POST /api/manager/devkit/` came back 500 through it; Homey CLI 4.6.1, firmware 13.5.3, 2026-11-01), so the Homey CLI has to run at home.

`rc.sh` keeps a `claude remote-control` running for this folder, always, and for every repo or worktree on its list, and adds more on request. It keeps the home folder on the volume, installs what a re-created container lacks, and pulls this repo every hour, so a change pushed to `rc.sh` reaches the box by itself.

## Layout in the container

| Path | What |
|---|---|
| `/work` | the volume (`docker/buildbox` on the NAS) |
| `/work/home` | the home folder (`HOME`): the logins of Claude, git and tools like the Homey CLI |
| `/work/buildbox` | this repo, the base folder: its Remote Control always runs and can't be removed; `state/` (gitignored) has the folder list and `rc.log` |
| `/work/<repo>` | a repo cloned with `rc.sh clone` |
| `/work/<repo>-<name>` | a worktree made with `rc.sh add` |

## Setting it up (DSM in a browser; SETUP.md has every step, from a new NAS on)

1. Package Center → **Container Manager**. File Station → the folder `docker/buildbox`.
2. Container Manager → Registry → `node` → Download → tag `22-bookworm`.
3. Image → `node:22-bookworm` → Run: name `buildbox`, **Enable auto-restart**, volume `docker/buildbox` → `/work`, execution command `bash -c 'until [ -x /work/buildbox/rc.sh ]; do sleep 10; done; exec bash /work/buildbox/rc.sh supervise'` (it waits for this repo, then supervises; Container Manager may not let it be changed later), environment variable `HOME` = `/work/home`.
4. A terminal in the container (DSM's Open terminal, or SSH and `sudo docker exec -it buildbox bash`, where pasting works on a phone):
   ```
   mkdir -p /work/home && cd /work/home
   apt-get update && apt-get install -y tmux
   npm install -g @anthropic-ai/claude-code
   git config --global credential.helper store
   git clone https://github.com/thomassidor/buildbox.git /work/buildbox
   claude        # log in once, then /exit
   ```
   The repo is public, so the clone needs no login. Pushing does: see *GitHub* below.
5. The supervisor starts by itself once the clone is there. From then on a container or NAS restart brings every Remote Control back by itself.
6. Add the repos, here or from a session in the buildbox folder:
   ```
   /work/buildbox/rc.sh clone https://github.com/thomassidor/widgetkeeper.git
   ```

The logins (Claude, GitHub, and those of tools like the Homey CLI) live in `/work/home`, so they survive a re-created container too. A container made without `HOME=/work/home` still works: `rc.sh` moves to `/work/home` by itself (the first time copying the container's own home there), but a terminal opened in DSM then has the old home. What step 4 installed is lost with the container; the supervisor installs tmux and Claude Code again when they're missing. So a new container needs only step 3.

## Using it

- `rc.sh clone <git-url> [name] [branch]`: clones a repo to `/work/<name>` (default the repo's name), sets it up and starts its Remote Control. An existing folder is only put on the list.
- `rc.sh add <repo> <name> [branch]`: a worktree `/work/<repo>-<name>` of `/work/<repo>`, on a new branch `<name>` from `origin/<branch>` (default the repo's current branch; an existing branch `<name>` is checked out instead), set up, with its own Remote Control. One Remote Control serves every session in its folder, so this is only for work that needs its own copy of the code.
- `rc.sh remove <folder>`: stops its Remote Control and takes it off the list. The folder stays (`git -C /work/<repo> worktree remove /work/<repo>-<name>` deletes a worktree). The buildbox folder can't be removed, so one Remote Control always runs.
- `rc.sh list`: the folders and whether each one's Remote Control runs.
- `rc.sh logs <folder> [lines]`: the end of that folder's Remote Control screen (40 lines) and its last lines in `rc.log`. The first thing to look at when one doesn't come up.
- Setting up a folder runs its `.buildbox/setup.sh` if it has one (executable, run in the folder), else `npm ci` (`npm install` without a lockfile) for a Node project, else nothing.
- A Remote Control that exits is started again after 5 s; one that keeps exiting within a minute of starting (an expired login, say), after 20 s, 40 s, … up to every 5 minutes, with a line in `rc.log` after the third time. A window that was closed comes back within 15 s.
- Every hour (and when it starts) the supervisor runs `git pull --ff-only` here; when `rc.sh` changed it restarts itself with the new one, leaving the Remote Controls running. A pull that fails (local changes, a diverged branch) is logged and skipped.
- `rc.log` keeps its last 1000 lines. `state/rc.log` has the starts and exits; `tmux attach -t rc` shows them (Ctrl-b d leaves).
- **Extras** (`state/extras`, one word a line; an opt-in, as each downloads a lot from outside): `chromium`, a browser for renders. The NAS is arm64 and Edge has no arm64 build for Linux, so it's Playwright's Chromium headless shell (`playwright@1.64.1`, in `~/.cache/ms-playwright` on the volume) with its system libraries and the fonts the pages use (Roboto, Liberation, Noto Color Emoji). `rc.sh install` installs what's listed (the supervisor does at every start, so a re-created container gets the libraries and fonts again); its output goes to `state/install.log`. `chromium-render` runs it the way the render scripts call Edge (`EDGE`, set in `claude-settings.json`'s `env`): `--headless=new` dropped, `--no-sandbox` added (the box runs as root). Linux draws text differently from Windows, so the box's renders match each other but not images made on Windows.
- `claude-settings.json` is merged into the box's `~/.claude/settings.json` when the supervisor starts and after each pull (objects merged, lists joined, the rest kept; a file that isn't valid JSON is left alone and logged). It starts sessions in **auto mode** (the user's pick, 2026-11-03: a classifier approves ordinary commands and stops risky ones for a prompt; the box holds the GitHub token and the Homey CLI's login, so not `bypassPermissions`). Sessions already open keep their mode.
- A supervised folder is marked trusted in `~/.claude.json`, as nobody is there to answer Claude Code's question.
- Folder names are letters, digits, `.`, `_` and `-`, and unique by name (each is a tmux window).
- Settings by environment variable: `WORK` (`/work`), `STATE` (`state/` here), `BOX_HOME` (`/work/home`), `CLAUDE_BIN`, `TMUX_SESSION` (`rc`), `CHECK_EVERY` (15 s), `UPDATE_EVERY` (3600 s; 0 for no pulls).

## GitHub

Sessions push and open pull requests with the GitHub CLI (`gh`), logged in as me with full access to my repos (scopes `repo`, `workflow`, `read:org`, `gist`; my choice, 2026-11-03). `gh auth setup-git` has git use that login for github.com, so `git push` works too. Commits on the box are authored as `Claude <noreply@anthropic.com>` (`~/.gitconfig`). The login is in `~/.config/gh` on the volume and doesn't expire; `rc.sh install` (and the supervisor at every start) installs `gh` again in a re-created container. To log in again, from a terminal or a session here:
```
gh auth login -h github.com -p https -w -s workflow && gh auth setup-git
```
It prints a code to enter at https://github.com/login/device. `gh auth status` shows the login; revoking it on GitHub (Settings → Applications → Authorized OAuth Apps → GitHub CLI) cuts the box off.

## Widgetkeeper

`/work/widgetkeeper`: `npx homey login` prints a link; open it, and paste the code from the page it ends on (an address on `localhost` that won't load: the code is after `code=`). The NAS is on the home network, so `npx homey app install`, `npm run diagnostics` and `npm run test-dashboards` work as from the PC.

## Tested

`rc.sh` was tested in a Linux container with a stand-in `claude` that exits after a few seconds (2026-11-02): the base folder under the supervisor, `clone` of a Node repo (`npm ci`) and of one with `.buildbox/setup.sh`, `add` with a real worktree, a killed window brought back, `remove`, and the refusals (the base folder, a repo not cloned, names with `/` or `..`). Then (same day, same way): the home folder made on `/work/home` from the old one and used by the Remote Controls, `logs`, the backoff of a folder whose stand-in exits at once, and a push of a changed `rc.sh` taking over the supervisor while the windows ran on. Not yet with the real `claude remote-control` or on the Synology.
