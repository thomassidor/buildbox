# buildbox — notes for Claude

The NAS build box: a container on the Synology at home (`node:22-bookworm`, the volume at `/work`) running Claude Code's Remote Control for this folder and for repos cloned next to it (`/work/<repo>`, each with its own CLAUDE.md), so their tools run on the home network. README.md has the setup and the layout.

- `rc.sh` is the container's command (`rc.sh supervise`) and the only script: `rc.sh list | logs <folder> [lines] | clone <git-url> [name] [branch] | add <repo> <name> [branch] | remove <folder> | login | install`. The container is `compose.yaml`, a Container Manager project whose command clones this repo on an empty volume; `rc.sh login` (Claude Code and gh, each only when missing) is the one step a new box needs in a terminal. A session here that's asked to work on a repo not yet on the box clones it with `rc.sh clone`; the user then picks that folder for a session of its own. Keep it plain bash with no dependencies beyond tmux, git, gh, node and claude, which the container has (rc.sh installs tmux, gh and claude when missing).
- The supervisor pulls this repo every hour and restarts itself on a new `rc.sh`, so pushing to `main` is how a change reaches the box. Leave the working copy on the box clean (commit, push) or the pull is skipped.
- GitHub: `gh` is logged in with full access to the user's repos and is git's credential for github.com (README.md's *GitHub*); push and open PRs with it.
- `HOME` is `/work/home` on the volume (rc.sh switches to it), so logins survive a re-created container.
- `claude-settings.json` is merged into `~/.claude/settings.json` on the box (`apply_settings`): sessions start in auto mode, the user's choice over an allowlist or `bypassPermissions`. Don't loosen it without asking.
- `state/extras` opts into downloads (`chromium`: Playwright's headless shell, its libraries and fonts, for renders through `chromium-render`, which `EDGE` points at). The user turns one on; a session doesn't add to it by itself.
- Its state is `state/` (gitignored): `folders` (one path per line; this folder is always supervised, whether listed or not) and `rc.log`.
- A repo sets itself up with an executable `.buildbox/setup.sh`; without one, a Node project gets `npm ci`/`npm install`.
- Never stop the Remote Control of the folder a session runs in from inside that session: it's the session's own connection (the supervisor brings it back, but the session drops).
- Test a change with a stand-in `claude` (a script that echoes and sleeps) and `WORK`, `STATE`, `BOX_HOME`, `CLAUDE_BIN`, `TMUX_SESSION`, `CHECK_EVERY`, `UPDATE_EVERY` pointed elsewhere, as README.md's *Tested* says.
