# buildbox — notes for Claude

The NAS build box: a container on the Synology at home (`node:22-bookworm`, the volume at `/work`) running Claude Code's Remote Control for this folder and for repos cloned next to it (`/work/<repo>`, each with its own CLAUDE.md), so their tools run on the home network. README.md has the setup and the layout.

- `rc.sh` is the container's command (`rc.sh supervise`) and the only script: `rc.sh list | logs <folder> [lines] | clone <git-url> [name] [branch] | add <repo> <name> [branch] | remove <folder>`. A session here that's asked to work on a repo not yet on the box clones it with `rc.sh clone`; the user then picks that folder for a session of its own. Keep it plain bash with no dependencies beyond tmux, git, node and claude, which the container has.
- The supervisor pulls this repo every hour and restarts itself on a new `rc.sh`, so pushing to `main` is how a change reaches the box. Leave the working copy on the box clean (commit, push) or the pull is skipped.
- `HOME` is `/work/home` on the volume (rc.sh switches to it), so logins survive a re-created container.
- Its state is `state/` (gitignored): `folders` (one path per line; this folder is always supervised, whether listed or not) and `rc.log`.
- A repo sets itself up with an executable `.buildbox/setup.sh`; without one, a Node project gets `npm ci`/`npm install`.
- Never stop the Remote Control of the folder a session runs in from inside that session: it's the session's own connection (the supervisor brings it back, but the session drops).
- Test a change with a stand-in `claude` (a script that echoes and sleeps) and `WORK`, `STATE`, `BOX_HOME`, `CLAUDE_BIN`, `TMUX_SESSION`, `CHECK_EVERY`, `UPDATE_EVERY` pointed elsewhere, as README.md's *Tested* says.
