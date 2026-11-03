# Setting it all up, step by step

From a phone or computer, in a browser. About 30–45 minutes for a new NAS, 10 for the box on one that runs; most of it waiting. Away from home, turn on the VPN to the home network first.

## 1. The NAS itself (skip what's already done)

1. **Find it.** Plugged in to the router and switched on, it gets an address on the home network. Find it in the router's list of devices (named like `DiskStation` or `Synology`), or open **find.synology.com** at home. Open `http://<its address>:5000`.
2. **Install DSM** (a new NAS shows *Install*): Install now → let it download the latest DSM → it wipes the drives and restarts (about 10 min).
3. **Create the admin account:** a device name (e.g. `nas`), your user name and a strong password. Skip QuickConnect if you only reach it through the VPN.
4. **Updates:** pick *Notify me and let me decide*, or automatic installs of important ones.
5. **Storage:** DSM opens Storage Manager (or open it: Main menu → Storage Manager) → **Create** storage pool → SHR (one or more drives) → choose the drives → Create volume → **Btrfs** → maximum size. Wait until the volume shows *Healthy* (checking the drives can run on in the background).
6. **Check it can run containers:** Main menu → **Package Center** → search **Container Manager**. If it isn't there, this model can't run containers and the rest won't work.

## 2. Container Manager

1. Package Center → **Container Manager** → **Install** (it creates the shared folder `docker`).
2. **File Station** → open `docker` → Create → **Create folder** → `buildbox`.

## 3. The container, as a project

1. Container Manager → **Project** → **Create**.
2. Project name **`buildbox`**, path → `docker/buildbox`, source **Create docker-compose.yml**.
3. Paste the contents of [`compose.yaml`](https://github.com/thomassidor/buildbox/blob/main/compose.yaml) from this repo (on GitHub: open it → *Raw* → select all, copy).
4. Next (skip the web portal) → **Done**. It downloads `node:22-bookworm` and starts the container, which clones this repo into `/work/buildbox`, installs tmux, Claude Code and the GitHub CLI, and starts the supervisor. A minute or two.

To change the container later: Project → `buildbox` → stop it, edit the YAML, **Build**. The volume keeps everything, so that's safe.

## 4. The logins

1. Open a terminal in the container, either:
   - Container → `buildbox` → **Action** → **Open terminal** → **Create** → type `bash` and press Enter (DSM's terminal: on a phone, pasting doesn't work), or
   - over SSH, where pasting works: Control Panel → **Terminal & SNMP** → **Enable SSH service**; an SSH app (e.g. Termius) to the NAS's address, port 22, your DSM user; then `sudo docker exec -it buildbox bash` (your DSM password).
2. Run:
   ```
   /work/buildbox/rc.sh login
   ```
   - **Claude:** it shows a link; open it, log in, and paste the code the page shows back into the terminal.
   - **GitHub:** it asks a few questions (pick the defaults) and shows a code; enter it at **github.com/login/device** and approve.
3. It ends with `== done`. `/work/buildbox/rc.sh list` shows `running  /work/buildbox` within seconds.

## 5. The repos

1. In the terminal run:
   ```
   /work/buildbox/rc.sh clone https://github.com/thomassidor/widgetkeeper.git
   /work/buildbox/rc.sh list
   ```
   (or ask a session in the buildbox folder to clone it)
2. `list` shows `running  /work/buildbox` and `running  /work/widgetkeeper`.

## 6. Use it

In the Claude app, a session can now ask to connect to `/work/widgetkeeper` (or `/work/buildbox`); approve it once. For Widgetkeeper the session then logs the Homey CLI in (a link to open, a code to paste back) and can install, read diagnostics and build test dashboards.

## If something goes wrong

- A command fails: copy what the terminal says.
- Nothing running: `/work/buildbox/rc.sh list`; `rc.log` saying Claude Code isn't logged in: `/work/buildbox/rc.sh login`; what happened: `cat /work/buildbox/state/rc.log`; the live windows: `tmux attach -t rc` (Ctrl-b then d to leave).
- After a NAS restart everything comes back by itself (auto-restart and the supervisor).
- A Remote Control that doesn't come up: `/work/buildbox/rc.sh logs <folder>` shows its screen (an expired login, say).
- Re-creating the container: build the project again (or step 3 again), nothing more. The logins are in `/work/home` and the supervisor installs tmux, Claude Code and gh again.
- A change pushed to the buildbox repo reaches the NAS within an hour by itself.
