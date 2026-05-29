# ansible.installer

Small installer for a local Ansible control-node runtime on Rocky, RHEL, AlmaLinux and compatible systems.

It installs Ansible with `uv`, keeps runtimes versioned under `apps/<python>_<ansible>`, and exposes the active runtime through `current`.

## Quick install

Canonical short URL, shared system install:

```bash
sudo -v
curl -L ansible-uv.bitbull.ch | sudo -n sh
```

GitHub URL:

```bash
curl -L https://raw.githubusercontent.com/joe-speedboat/ansible.installer/refs/heads/main/ansible/ansible_setup.sh | sudo -n sh
```

Userspace install for the current login user, without sudo:

```bash
curl -fsSL https://ansible-uv.bitbull.ch | env SCOPE=user ANSIBLE_HOME="$HOME/ansible" sh
```

This is the right command when the target user already owns the target path and
has no sudo rights. It keeps everything below `$HOME/ansible` and does not touch
`/etc`, `/usr/local/bin`, or `/opt`.

Use sudo only when root must create/install for another user:

```bash
sudo -n true
curl -fsSL https://ansible-uv.bitbull.ch \
  | sudo -n env \
      SCOPE=user \
      INSTALL_USER="devel" \
      INSTALL_GROUP="devel" \
      ANSIBLE_HOME="/home/devel/ansible" \
      sh
```

If `sudo -n true` fails, do not start a piped sudo installer. Either run the
userspace command as the target user, or run from an already-root automation
context such as kickstart `%post`.

Activate that install as the target user:

```bash
source "$HOME/ansible/apps/profile.d/ansible.sh"
ansible --version
```

If you are already the target user, userspace install also works without sudo:

```bash
curl -fsSL https://ansible-uv.bitbull.ch | env SCOPE=user ANSIBLE_HOME="$HOME/ansible" sh
```

## Scopes

### `SCOPE=system`

This is the traditional shared layout. It is the default when the installer runs as root.

Installed shape:

- `/opt/ansible`: shared Ansible workspace, owned by the selected install user/group, mode `0750`
- `/opt/ansible/apps/<python>_<ansible>`: one uv-managed runtime per version pair
- `/opt/ansible/current`: symlink to the active runtime
- `/etc/profile.d/ansible.sh`: shell integration and runtime switch function
- `/usr/local/bin/ansible-local-switch`: persistent runtime switch helper
- `/usr/local/bin/adoc`: `ansible-doc` convenience helper
- `/etc/bash_completion.d/ansible`: argcomplete hook
- `/etc/ansible -> /opt/ansible`: compatibility symlink when `/etc/ansible` does not exist

### `SCOPE=user`

This keeps the Ansible workspace normal-looking and moves installer-specific files under `apps/`. It is the default when the installer runs as a normal user.

Example with `ANSIBLE_HOME=/home/devel/ansible`:

```text
/home/devel/ansible/
├── ansible.cfg
├── inventory/
├── logs/
├── playbooks/
├── projects/
├── roles/
├── tmp/
├── apps/
│   ├── 3.12_13.4.0/
│   ├── bin/
│   │   ├── ansible-local-switch
│   │   ├── adoc
│   │   └── uv
│   ├── profile.d/
│   │   └── ansible.sh
│   └── .ansible-uv-installer
└── current -> apps/3.12_13.4.0
```

Userspace activation:

```bash
source /home/devel/ansible/apps/profile.d/ansible.sh
```

By default, `SCOPE=user` does not create or modify:

- `/etc/profile.d/ansible.sh`
- `/etc/ansible`
- `/etc/bash_completion.d/ansible`
- `/usr/local/bin/ansible-local-switch`
- `/usr/local/bin/adoc`
- `/opt/ansible`

`SCOPE=user` intentionally refuses `ANSIBLE_LINK_ETC=1`. Use `SCOPE=system` if
you want `/etc/profile.d`, `/etc/ansible`, or system-wide completion files.

## Defaults

- `SCOPE=system` when run as root; `SCOPE=user` when run as a normal user
- `INSTALL_USER=${SUDO_USER}` when available, otherwise the current user
- `INSTALL_GROUP=ansible` for `SCOPE=system`
- `INSTALL_GROUP=${INSTALL_USER}` for `SCOPE=user`
- `PYTHON_VERSION=3.12`
- `ANSIBLE_VERSION=13.4.0`
- `ANSIBLE_CORE_VERSION=` legacy alias input for `ANSIBLE_VERSION`
- `ANSIBLE_HOME=/opt/ansible` for `SCOPE=system`
- `ANSIBLE_HOME=/home/devel/ansible` as a typical userspace example
- `ANSIBLE_RUNTIME=${PYTHON_VERSION}_${ANSIBLE_VERSION}`; example `ANSIBLE_RUNTIME=3.12_13.4.0`
- `ANSIBLE_VENV_PATH=${ANSIBLE_HOME}/apps/${ANSIBLE_RUNTIME}`; example `ANSIBLE_VENV_PATH=/opt/ansible/apps/3.12_13.4.0`
- `ANSIBLE_LOCAL_TEMP=$HOME/.ansible/tmp`
- `ANSIBLE_LOG_PATH=$HOME/.ansible/ansible.log`
- `ANSIBLE_LINK_ETC=1` for `SCOPE=system`
- `ANSIBLE_LINK_ETC=0` for `SCOPE=user`
- `RAW_BASE=https://raw.githubusercontent.com/joe-speedboat/ansible.installer/refs/heads/main`
- `UV_BIN=/usr/local/bin/uv` in the default system layout; userspace installs auto-place `uv` under `${ANSIBLE_HOME}/apps/bin/uv` when missing

`ANSIBLE_CORE_VERSION` is still accepted as a legacy input alias. The installer still installs the Ansible community package (`ansible==${ANSIBLE_VERSION}`), not an `ansible-core==13.x` package. Yes, naming is a trap. We step around it.

## Variable examples

Install a specific Python and Ansible version:

```bash
curl -L ansible-uv.bitbull.ch | sudo -n env PYTHON_VERSION=3.12 ANSIBLE_VERSION=11.3.0 sh
```

Use an explicit runtime name:

```bash
curl -L ansible-uv.bitbull.ch | sudo -n env ANSIBLE_RUNTIME=3.12_13.4.0 sh
```

Use a non-default system home path:

```bash
curl -L ansible-uv.bitbull.ch | sudo -n env SCOPE=system ANSIBLE_HOME=/srv/ansible sh
```

Use a named userspace target user and group:

```bash
sudo -v
curl -fsSL https://ansible-uv.bitbull.ch \
  | sudo -n env SCOPE=user INSTALL_USER=devel INSTALL_GROUP=devel ANSIBLE_HOME=/home/devel/ansible sh
```

Install for root only, without touching `/etc`:

```bash
sudo -v
curl -fsSL https://ansible-uv.bitbull.ch \
  | sudo -H -n env SCOPE=user INSTALL_USER=root INSTALL_GROUP=root ANSIBLE_HOME=/root/ansible sh
```

Do not use `ANSIBLE_LINK_ETC=1` with `SCOPE=user`; the installer rejects that
combination to keep user installs independent from system integration.

Use specific per-user temp and log paths for Ansible:

```bash
export ANSIBLE_LOCAL_TEMP=$HOME/.ansible/tmp
export ANSIBLE_LOG_PATH=$HOME/.ansible/ansible.log
source /etc/profile.d/ansible.sh
```

For userspace installs, source the userspace profile instead:

```bash
source /home/devel/ansible/apps/profile.d/ansible.sh
```

Test local payload files while developing:

```bash
sudo RAW_BASE=file:///tmp/ansible.installer sh /tmp/ansible.installer/ansible/ansible_setup.sh
```

Use an existing `uv` binary:

```bash
curl -L ansible-uv.bitbull.ch | sudo -n env UV_BIN=/usr/local/bin/uv sh
```

### Real-world userspace patterns

No sudo privileges available, current user only:

```bash
curl -fsSL https://ansible-uv.bitbull.ch | env SCOPE=user ANSIBLE_HOME="$HOME/ansible" sh
source "$HOME/ansible/apps/profile.d/ansible.sh"
ansible --version
```

Current user with sudo available is usually still better installed without sudo.
Only use the sudo-assisted form if an admin wants to create the target tree as
root and then hand ownership to the target user:

```bash
sudo -n true
curl -fsSL https://ansible-uv.bitbull.ch \
  | sudo -n env SCOPE=user INSTALL_USER="$USER" INSTALL_GROUP="$(id -gn)" ANSIBLE_HOME="$HOME/ansible" sh
echo 'source "$HOME/ansible/apps/profile.d/ansible.sh"' >> "$HOME/.bashrc"
```

Dedicated automation user with its own Ansible tree:

```bash
sudo useradd -m -U ansible-runner
sudo -v
curl -fsSL https://ansible-uv.bitbull.ch \
  | sudo -n env SCOPE=user INSTALL_USER=ansible-runner INSTALL_GROUP=ansible-runner ANSIBLE_HOME=/home/ansible-runner/ansible sh
sudo -iu ansible-runner bash -lc 'source ~/ansible/apps/profile.d/ansible.sh && ansible --version'
```

Shared system runtime plus isolated user runtimes:

```bash
# first, optional system install; provides /usr/local/bin/uv and shared /opt/ansible
sudo -v
curl -fsSL https://ansible-uv.bitbull.ch | sudo -n sh

# later, users can install isolated workspaces and reuse executable system uv
curl -fsSL https://ansible-uv.bitbull.ch | env SCOPE=user ANSIBLE_HOME="$HOME/ansible" sh
```

Why `sudo -n` in piped sudo examples? In `curl | sudo sh`, both commands start
at the same time. If sudo needs a password, the download can finish before sudo
asks for it, which looks like a hung installer and ends with `curl: (23)` once
sudo exits. `sudo -n` makes sudo non-interactive: it either runs with existing
root/sudo rights or fails immediately. For unattended sudo, preflight with
`sudo -n true` before starting the pipe. For current-user userspace installs,
do not use sudo at all.

Unattended script/CI/kickstart style with sudo available and already permitted:

```bash
sudo -n true
curl -fsSL https://ansible-uv.bitbull.ch \
  | sudo -n env SCOPE=user INSTALL_USER=devel INSTALL_GROUP=devel ANSIBLE_HOME=/home/devel/ansible sh
```

Kickstart `%post` normally runs as root; do not use sudo there:

```bash
curl -fsSL https://ansible-uv.bitbull.ch \
  | env SCOPE=user INSTALL_USER=devel INSTALL_GROUP=devel ANSIBLE_HOME=/home/devel/ansible sh
```

In user scope the installer looks for executable `uv` in `/usr/local/bin/uv` and
`/usr/bin/uv` first. If neither is usable by the target user, it places a private
copy in `${ANSIBLE_HOME}/apps/bin/uv`.

### Security model

- The default `SCOPE=user` layout never writes `/etc/profile.d`, `/etc/ansible`,
  `/etc/bash_completion.d`, or `/usr/local/bin`.
- `SCOPE=user` validates that all selected target paths are writable by the
  target install user before installing.
- System integration files are owned by `root` and the selected Ansible group;
  the Ansible workspace remains owned by the selected install user/group.
- Ansible tree directories are mode `0750`; regular data/config files are mode
  `0640`; executable payloads and virtualenv commands are mode `0750`.
- The generated default `ansible.cfg` keeps SSH host key checking enabled. For
  disposable labs you can explicitly disable it in `${ANSIBLE_HOME}/ansible.cfg`.
- Downloads still come from HTTPS endpoints at install time (`ansible-uv.bitbull.ch`,
  GitHub raw files, and upstream `uv`). Pin and mirror those inputs internally if
  your environment requires fully reproducible or offline installs.

## Existing Ansible installs

The installer stops before changing the host when it detects another Ansible installation method. Mixing RPM, pip, old `ansible.bitbull.ch` installs and this uv layout makes `PATH`, Python packages and config files annoying fast. So the installer refuses and tells you what it found.

Detected foreign installs in system mode:

- RPM packages: `ansible`, `ansible-core`
- pip packages: `ansible`, `ansible-core`
- an `ansible` command outside the selected ansible-uv tree
- `/etc/profile.d/ansible.sh` without the ansible-uv marker when `/etc` integration is enabled
- a non-symlink `/etc/ansible` directory when the host is not marked as ansible-uv managed and `/etc` integration is enabled

Rerunning this installer on an ansible-uv managed host is supported. It reuses the runtime when present and runs an upgrade install for the requested Ansible version and `argcomplete`.

## Runtime switching

Load the shell integration first.

System install:

```bash
source /etc/profile.d/ansible.sh
```

Userspace install:

```bash
source /home/devel/ansible/apps/profile.d/ansible.sh
```

List installed runtimes:

```bash
ansible-local-switch --list
```

Switch only the current shell:

```bash
ansible-local-switch 3.12_11.3.0
```

Switch the permanent default:

```bash
ansible-local-switch --permanent 3.12_13.4.0
```

The session-only switch is a shell function from the installed profile script. The permanent switch is handled by `ansible-local-switch` and updates `${ANSIBLE_HOME}/current` plus the profile defaults.

## User overrides

Users may place overrides in:

```text
$HOME/.ansible.sh
```

Typical example:

```bash
export ANSIBLE_HOME=/opt/ansible
export PYTHON_VERSION=3.12
export ANSIBLE_VERSION=13.4.0
```

If `$HOME/.ansible.sh` sets `ANSIBLE_VENV_PATH`, the profile script keeps that explicit path. Otherwise it derives the path from `ANSIBLE_HOME`, `PYTHON_VERSION` and `ANSIBLE_VERSION`.

## Validation

After system install:

```bash
source /etc/profile.d/ansible.sh
ansible --version
ansible localhost -m ping
ansible-local-switch --list
adoc copy | sed -n '1,12p'
```

After userspace install:

```bash
sudo -iu devel bash -lc 'source /home/devel/ansible/apps/profile.d/ansible.sh && ansible --version && ansible localhost -m ping && ansible-local-switch --list && adoc copy | sed -n "1,12p"'
```

Check ownership and modes:

```bash
stat -c '%U:%G %a %n' /usr/local/bin/ansible-local-switch /usr/local/bin/adoc /etc/profile.d/ansible.sh /etc/bash_completion.d/ansible /opt/ansible /opt/ansible/apps
find /opt/ansible -xdev ! -type l \( -not -group ansible -o -perm /007 \) -print
```

Userspace check:

```bash
sudo -iu devel bash -lc 'stat -c "%U:%G %a %n" ~/ansible ~/ansible/apps ~/ansible/apps/profile.d/ansible.sh ~/ansible/apps/bin/ansible-local-switch ~/ansible/apps/bin/adoc'
```

## Repository layout

- `ansible/ansible_setup.sh`: installer entrypoint
- `ansible/files/etc/profile.d/ansible.sh`: profile script template
- `ansible/files/usr/local/bin/ansible-local-switch`: persistent runtime switch helper template
- `ansible/files/usr/local/bin/adoc`: `ansible-doc` helper
- `tests/test_installer_static.py`: static checks for paths, markers, ownership intent and documentation

Payload files are stored in this repository under `ansible/files/` using their traditional system target path, for example `ansible/files/usr/local/bin/adoc`. Userspace mode installs the same payloads below `${ANSIBLE_HOME}/apps/`.

## Development checks

```bash
pytest tests/test_installer_static.py -q
sh -n ansible/ansible_setup.sh
bash -n ansible/files/etc/profile.d/ansible.sh
bash -n ansible/files/usr/local/bin/ansible-local-switch
bash -n ansible/files/usr/local/bin/adoc
git diff --check
```
