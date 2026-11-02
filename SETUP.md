# Setting it all up, step by step

From a phone or computer, in a browser. About 30–45 minutes, most of it waiting. Away from home, turn on the VPN to the home network first.

## 1. The NAS itself (skip what's already done)

1. **Find it.** Plugged in to the router and switched on, it gets an address on the home network. Find it in the router's list of devices (named like `DiskStation` or `Synology`), or open **find.synology.com** at home. Open `http://<its address>:5000`.
2. **Install DSM** (a new NAS shows *Install*): Install now → let it download the latest DSM → it wipes the drives and restarts (about 10 min).
3. **Create the admin account:** a device name (e.g. `nas`), your user name and a strong password. Skip QuickConnect if you only reach it through the VPN.
4. **Updates:** pick *Notify me and let me decide*, or automatic installs of important ones.
5. **Storage:** DSM opens Storage Manager (or open it: Main menu → Storage Manager) → **Create** storage pool → SHR (one or more drives) → choose the drives → Create volume → **Btrfs** → maximum size. Wait until the volume shows *Healthy* (checking the drives can run on in the background).
6. **Check it can run containers:** Main menu → **Package Center** → search **Container Manager**. If it isn't there, this model can't run containers and the rest won't work.

## 2. A GitHub token (so the NAS can download the private repos)

1. github.com → your picture → **Settings** → **Developer settings** → Personal access tokens → **Fine-grained tokens** → **Generate new token**.
2. Name `buildbox`, an expiry you like. Repository access: **Only select repositories** → `buildbox` and `widgetkeeper` (and any others it should work on).
3. Permissions → Repository permissions → **Contents: Read and write**.
4. **Generate token** and copy it somewhere safe; GitHub shows it once.

## 3. Container Manager

1. Package Center → **Container Manager** → **Install** (it creates the shared folder `docker`).
2. **File Station** → open `docker` → Create → **Create folder** → `buildbox`.

## 4. The image

1. Container Manager → **Registry** → search `node` → pick **node** (the official one) → **Download** → tag **`22-bookworm`** → Apply.
2. Wait until it shows under **Image**.

## 5. The container

1. Image → `node:22-bookworm` → **Run**.
2. Container name **`buildbox`**, tick **Enable auto-restart** → Next.
3. **Volume settings** → Add folder → `docker/buildbox` → mount path **`/work`**.
4. **Execution command:** `sleep infinity`.
5. **Environment** → add `HOME` with the value `/work/home` (the logins then live on the volume).
6. Leave the rest as it is → Next → **Done**; it starts.

## 6. Inside the container

1. Container → `buildbox` → **Action** → **Open terminal** → **Create** → type `bash` and press Enter.
2. Paste one line at a time and wait for each:
   ```
   apt-get update && apt-get install -y tmux
   npm install -g @anthropic-ai/claude-code
   git config --global credential.helper store
   git clone https://github.com/thomassidor/buildbox.git /work/buildbox
   ```
   `git clone` asks for a **Username** (your GitHub user) and a **Password**: paste the token from step 2.
3. Type `claude`, open the link it shows, log in, paste the code back, then type `/exit`.

## 7. The supervisor

1. Container → `buildbox` → **Stop**.
2. **Action** → **Edit** → Execution command: `bash /work/buildbox/rc.sh supervise` → **Save**.
3. **Start**.

## 8. The repos

1. Open the terminal again (step 6.1) and run:
   ```
   /work/buildbox/rc.sh clone https://github.com/thomassidor/widgetkeeper.git
   /work/buildbox/rc.sh list
   ```
2. `list` shows `running  /work/buildbox` and `running  /work/widgetkeeper`.

## 9. Use it

In the Claude app, a session can now ask to connect to `/work/widgetkeeper` (or `/work/buildbox`); approve it once. For Widgetkeeper the session then logs the Homey CLI in (a link to open, a code to paste back) and can install, read diagnostics and build test dashboards.

## If something goes wrong

- A command fails: copy what the terminal says.
- Nothing running: `/work/buildbox/rc.sh list`; what happened: `cat /work/buildbox/state/rc.log`; the live windows: `tmux attach -t rc` (Ctrl-b then d to leave).
- After a NAS restart everything comes back by itself (auto-restart and the supervisor).
- A Remote Control that doesn't come up: `/work/buildbox/rc.sh logs <folder>` shows its screen (an expired login, say).
- Deleting and re-creating the container: do step 5 again with the execution command `bash /work/buildbox/rc.sh supervise`, nothing more. The logins are in `/work/home` and the supervisor installs tmux and Claude Code again.
- A change pushed to the buildbox repo reaches the NAS within an hour by itself.
