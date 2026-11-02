# buildbox — notes for Claude

The NAS build box: a container on the Synology at home (`node:22-bookworm`, the volume at `/work`) running Claude Code's Remote Control for the Widgetkeeper app (`/work/widgetkeeper`, its own CLAUDE.md), so the Homey CLI runs on the home network. README.md has the setup and the layout.

- `rc.sh` is the container's command (`rc.sh supervise`) and the only script: `rc.sh list|add <name> [branch]|remove <name>`. Keep it plain bash with no dependencies beyond tmux, git, node and claude, which the container has.
- Its state is `state/` (gitignored): `folders` (one path per line, the main clone first) and `rc.log`.
- Never stop the main folder's Remote Control from inside a session running on it: it's the session's own connection (the supervisor brings it back, but the session drops).
- Test a change with a stand-in `claude` (a script that echoes and sleeps) and `WORK`, `STATE`, `CLAUDE_BIN`, `TMUX_SESSION`, `CHECK_EVERY` pointed elsewhere, as README.md's *Tested* says.
