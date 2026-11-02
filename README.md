# buildbox

A Docker container on the Synology NAS at home that runs the Homey CLI and Claude Code with Remote Control. A Claude Code session in the cloud connects to it and installs Widgetkeeper on the Homey, runs its diagnostics and builds its test dashboards over the home network while I'm away. Athom's cloud relay to the Homey turns down app uploads: every `POST /api/manager/devkit/` came back 500 through it (Homey CLI 4.6.1, firmware 13.5.3, 2026-11-01).

`rc.sh` keeps a `claude remote-control` running for every folder on its list (`state/folders`, `/work/widgetkeeper` first) and starts more on request.

## Layout in the container

| Path | What |
|---|---|
| `/work` | the volume (`docker/buildbox` on the NAS) |
| `/work/buildbox` | this repo; `state/` (gitignored) has the folder list and `rc.log` |
| `/work/widgetkeeper` | the app's clone, the main Remote Control folder |
| `/work/<name>` | worktrees made by `rc.sh add` |

## Setting it up (DSM in a browser)

1. Package Center → **Container Manager**. File Station → the folder `docker/buildbox`.
2. Container Manager → Registry → `node` → Download → tag `22-bookworm`.
3. Image → `node:22-bookworm` → Run: name `buildbox`, **Enable auto-restart**, volume `docker/buildbox` → `/work`, execution command `sleep infinity` (for now).
4. Container → `buildbox` → Action → Open terminal → Create → `bash`:
   ```
   apt-get update && apt-get install -y tmux
   npm install -g @anthropic-ai/claude-code
   git config --global credential.helper store
   cd /work
   git clone https://github.com/thomassidor/buildbox.git
   git clone https://github.com/thomassidor/widgetkeeper.git
   cd widgetkeeper && npm ci
   claude        # log in once, then /exit
   ```
   The first `git clone` asks for a GitHub user and a personal access token (both repos are private); the credential helper keeps it, so the second clone and `rc.sh add` don't ask.
5. Stop the container, change its execution command to `bash /work/buildbox/rc.sh supervise` and start it again. From then on a container or NAS restart brings the Remote Control back by itself.

The logins (Claude, GitHub, Homey CLI) and the tools installed in step 4 live in the container, so they survive a restart, not a re-created container.

## Using it

- `/work/buildbox/rc.sh list`: the folders and whether each one's Remote Control runs.
- `/work/buildbox/rc.sh add <name> [branch]`: a git worktree `/work/<name>` on a new branch `<name>` from `origin/<branch>` (default the main clone's branch), `npm ci`, and its own Remote Control. One Remote Control serves every session in its folder, so this is only for work that needs its own copy of the code.
- `/work/buildbox/rc.sh remove <name>`: stops it and takes it off the list; the main folder always keeps one. The worktree stays (`git -C /work/widgetkeeper worktree remove /work/<name>` deletes it).
- A Remote Control that exits is started again after 5 s; a window that was closed, within 15 s. `state/rc.log` has the starts and exits; `tmux attach -t rc` shows them (Ctrl-b d leaves).
- A supervised folder is marked trusted in `~/.claude.json`, as nobody is there to answer Claude Code's question.
- To work on this repo from a session too, add `/work/buildbox` as a line in `state/folders`.
- Settings by environment variable: `WORK` (`/work`), `MAIN` (`$WORK/widgetkeeper`), `STATE` (`state/` here), `CLAUDE_BIN`, `TMUX_SESSION` (`rc`), `CHECK_EVERY` (15 s).

## The Homey CLI there

`npx homey login` (in `/work/widgetkeeper`) prints a link; open it, and paste the code from the page it ends on (an address on `localhost` that won't load: the code is after `code=`). The NAS is on the home network, so `npx homey app install`, `npm run diagnostics` and `npm run test-dashboards` work as from the PC.

## Tested

`rc.sh` was tested in a Linux container with a stand-in `claude` that exits after a few seconds (2026-11-02): started under the supervisor, restarted after an exit, a killed window brought back, `add` with a real worktree and `remove`. Not yet with the real `claude remote-control` or on the Synology.
