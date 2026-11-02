# buildbox

A Docker container on the Synology NAS at home that runs Claude Code with Remote Control for any number of repos, so a Claude Code session in the cloud can work on the home network while I'm away. It started for Widgetkeeper: Athom's cloud relay to the Homey turns down app uploads (every `POST /api/manager/devkit/` came back 500 through it; Homey CLI 4.6.1, firmware 13.5.3, 2026-11-01), so the Homey CLI has to run at home.

`rc.sh` keeps a `claude remote-control` running for this folder, always, and for every repo or worktree on its list, and adds more on request.

## Layout in the container

| Path | What |
|---|---|
| `/work` | the volume (`docker/buildbox` on the NAS) |
| `/work/buildbox` | this repo, the base folder: its Remote Control always runs and can't be removed; `state/` (gitignored) has the folder list and `rc.log` |
| `/work/<repo>` | a repo cloned with `rc.sh clone` |
| `/work/<repo>-<name>` | a worktree made with `rc.sh add` |

## Setting it up (DSM in a browser; SETUP.md has every step, from a new NAS on)

1. Package Center → **Container Manager**. File Station → the folder `docker/buildbox`.
2. Container Manager → Registry → `node` → Download → tag `22-bookworm`.
3. Image → `node:22-bookworm` → Run: name `buildbox`, **Enable auto-restart**, volume `docker/buildbox` → `/work`, execution command `sleep infinity` (for now).
4. Container → `buildbox` → Action → Open terminal → Create → `bash`:
   ```
   apt-get update && apt-get install -y tmux
   npm install -g @anthropic-ai/claude-code
   git config --global credential.helper store
   git clone https://github.com/thomassidor/buildbox.git /work/buildbox
   claude        # log in once, then /exit
   ```
   `git clone` asks for a GitHub user and a personal access token (the repo is private); the credential helper keeps it, so later clones and fetches don't ask.
5. Stop the container, change its execution command to `bash /work/buildbox/rc.sh supervise` and start it again. From then on a container or NAS restart brings every Remote Control back by itself.
6. Add the repos, here or from a session in the buildbox folder:
   ```
   /work/buildbox/rc.sh clone https://github.com/thomassidor/widgetkeeper.git
   ```

The logins (Claude, GitHub, and those of tools like the Homey CLI) and what step 4 installed live in the container, so they survive a restart, not a re-created container.

## Using it

- `rc.sh clone <git-url> [name] [branch]`: clones a repo to `/work/<name>` (default the repo's name), sets it up and starts its Remote Control. An existing folder is only put on the list.
- `rc.sh add <repo> <name> [branch]`: a worktree `/work/<repo>-<name>` of `/work/<repo>`, on a new branch `<name>` from `origin/<branch>` (default the repo's current branch; an existing branch `<name>` is checked out instead), set up, with its own Remote Control. One Remote Control serves every session in its folder, so this is only for work that needs its own copy of the code.
- `rc.sh remove <folder>`: stops its Remote Control and takes it off the list. The folder stays (`git -C /work/<repo> worktree remove /work/<repo>-<name>` deletes a worktree). The buildbox folder can't be removed, so one Remote Control always runs.
- `rc.sh list`: the folders and whether each one's Remote Control runs.
- Setting up a folder runs its `.buildbox/setup.sh` if it has one (executable, run in the folder), else `npm ci` (`npm install` without a lockfile) for a Node project, else nothing.
- A Remote Control that exits is started again after 5 s; a window that was closed, within 15 s. `state/rc.log` has the starts and exits; `tmux attach -t rc` shows them (Ctrl-b d leaves).
- A supervised folder is marked trusted in `~/.claude.json`, as nobody is there to answer Claude Code's question.
- Folder names are letters, digits, `.`, `_` and `-`, and unique by name (each is a tmux window).
- Settings by environment variable: `WORK` (`/work`), `STATE` (`state/` here), `CLAUDE_BIN`, `TMUX_SESSION` (`rc`), `CHECK_EVERY` (15 s).

## Widgetkeeper

`/work/widgetkeeper`: `npx homey login` prints a link; open it, and paste the code from the page it ends on (an address on `localhost` that won't load: the code is after `code=`). The NAS is on the home network, so `npx homey app install`, `npm run diagnostics` and `npm run test-dashboards` work as from the PC.

## Tested

`rc.sh` was tested in a Linux container with a stand-in `claude` that exits after a few seconds (2026-11-02): the base folder under the supervisor, `clone` of a Node repo (`npm ci`) and of one with `.buildbox/setup.sh`, `add` with a real worktree, a killed window brought back, `remove`, and the refusals (the base folder, a repo not cloned, names with `/` or `..`). Not yet with the real `claude remote-control` or on the Synology.
