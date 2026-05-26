# ansible.installer

Small installer for a local Ansible control-node runtime on Rocky, RHEL, AlmaLinux and compatible systems.

It installs Ansible into `/opt/ansible` using `uv`, keeps runtimes versioned under `/opt/ansible/apps`, and exposes the active runtime through `/opt/ansible/current`.

## Quick install

Canonical short URL:

```bash
curl -L ansible-uv.bitbull.ch | sudo sh
```

GitHub URL:

```bash
curl -L https://raw.githubusercontent.com/joe-speedboat/ansible.installer/refs/heads/main/ansible/ansible_setup.sh | sudo sh
```

If you are already root:

```bash
curl -L ansible-uv.bitbull.ch | sh
```

## What it installs

- `/opt/ansible`: shared Ansible workspace, owned `root:ansible`, mode `0750`
- `/opt/ansible/apps/<python>_<ansible>`: one uv-managed runtime per version pair
- `/opt/ansible/current`: symlink to the active runtime
- `/opt/ansible/ansible.cfg`: minimal config, created only when missing
- `/opt/ansible/inventory/localhost`: localhost seed inventory, created only when missing
- `/etc/profile.d/ansible.sh`: shell integration and runtime switch function, `root:ansible`, mode `0750`
- `/usr/local/bin/ansible-local-switch`: persistent runtime switch helper, `root:ansible`, mode `0750`
- `/usr/local/bin/adoc`: `ansible-doc` convenience helper, `root:ansible`, mode `0750`
- `/etc/bash_completion.d/ansible`: argcomplete hook, `root:ansible`, mode `0640`
- `/etc/ansible -> /opt/ansible`: compatibility symlink when `/etc/ansible` does not exist; symlink owner/group is set to `root:ansible`

Payload files are stored in this repository under `ansible/files/` using their target path, for example `ansible/files/usr/local/bin/adoc`.

## Defaults

- `PYTHON_VERSION=3.12`
- `ANSIBLE_VERSION=13.4.0`
- `ANSIBLE_HOME=/opt/ansible`
- `ANSIBLE_RUNTIME=${PYTHON_VERSION}_${ANSIBLE_VERSION}`
- `ANSIBLE_VENV_PATH=${ANSIBLE_HOME}/apps/${ANSIBLE_RUNTIME}`
- `ANSIBLE_LOCAL_TEMP=${HOME}/.ansible/tmp`
- `ANSIBLE_LOG_PATH=${HOME}/.ansible/ansible.log`
- `RAW_BASE=https://raw.githubusercontent.com/joe-speedboat/ansible.installer/refs/heads/main`
- `UV_BIN`: auto-detected from `/usr/local/bin/uv`, `/usr/bin/uv`, or `$HOME/.local/bin/uv`; installed to `/usr/local/bin/uv` when missing

`ANSIBLE_CORE_VERSION` is still accepted as a legacy input alias. The installer still installs the Ansible community package (`ansible==${ANSIBLE_VERSION}`), not an `ansible-core==13.x` package. Yes, naming is a trap. We step around it.

## Variable examples

Install a specific Python and Ansible version:

```bash
curl -L ansible-uv.bitbull.ch | sudo env PYTHON_VERSION=3.12 ANSIBLE_VERSION=11.3.0 sh
```

Use an explicit runtime name:

```bash
curl -L ansible-uv.bitbull.ch | sudo env ANSIBLE_RUNTIME=3.12_13.4.0 sh
```

Use a non-default home path:

```bash
curl -L ansible-uv.bitbull.ch | sudo env ANSIBLE_HOME=/srv/ansible sh
```

Use specific per-user temp and log paths for Ansible:

```bash
export ANSIBLE_LOCAL_TEMP=$HOME/.ansible/tmp
export ANSIBLE_LOG_PATH=$HOME/.ansible/ansible.log
source /etc/profile.d/ansible.sh
```

Test local payload files while developing:

```bash
sudo RAW_BASE=file:///tmp/ansible.installer sh /tmp/ansible.installer/ansible/ansible_setup.sh
```

Use an existing `uv` binary:

```bash
curl -L ansible-uv.bitbull.ch | sudo env UV_BIN=/usr/local/bin/uv sh
```

## Existing Ansible installs

The installer stops before changing the host when it detects another Ansible installation method. Mixing RPM, pip, old `ansible.bitbull.ch` installs and this uv layout makes `PATH`, Python packages and config files annoying fast. So the installer refuses and tells you what it found.

Detected foreign installs:

- RPM packages: `ansible`, `ansible-core`
- pip packages: `ansible`, `ansible-core`
- an `ansible` command outside `/opt/ansible`
- `/etc/profile.d/ansible.sh` without the ansible-uv marker
- a non-symlink `/etc/ansible` directory when the host is not marked as ansible-uv managed

Rerunning this installer on an ansible-uv managed host is supported. It reuses the runtime when present and runs an upgrade install for the requested Ansible version and `argcomplete`.

## Runtime switching

Load the shell integration first:

```bash
source /etc/profile.d/ansible.sh
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

The session-only switch is a shell function from `/etc/profile.d/ansible.sh`. The permanent switch is handled by `/usr/local/bin/ansible-local-switch` and updates `/opt/ansible/current` plus the profile defaults.

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

After install:

```bash
source /etc/profile.d/ansible.sh
ansible --version
ansible localhost -m ping
ansible-local-switch --list
adoc copy | sed -n '1,12p'
```

Check ownership and modes:

```bash
stat -c '%U:%G %a %n' /usr/local/bin/ansible-local-switch /usr/local/bin/adoc /etc/profile.d/ansible.sh /etc/bash_completion.d/ansible /opt/ansible /opt/ansible/apps
find /opt/ansible -xdev ! -type l \( -not -group ansible -o -perm /007 \) -print
```

Expected shape:

```text
root:ansible 750 /usr/local/bin/ansible-local-switch
root:ansible 750 /usr/local/bin/adoc
root:ansible 750 /etc/profile.d/ansible.sh
root:ansible 640 /etc/bash_completion.d/ansible
root:ansible 750 /opt/ansible
root:ansible 750 /opt/ansible/apps
# find command prints nothing for real files/directories; symlink mode bits are ignored by Linux permission checks
```

## Repository layout

- `ansible/ansible_setup.sh`: installer entrypoint
- `ansible/files/etc/profile.d/ansible.sh`: profile script installed to `/etc/profile.d/ansible.sh`
- `ansible/files/usr/local/bin/ansible-local-switch`: persistent runtime switch helper
- `ansible/files/usr/local/bin/adoc`: `ansible-doc` helper
- `tests/test_installer_static.py`: static checks for paths, markers, ownership intent and documentation

## Development checks

```bash
pytest tests/test_installer_static.py -q
sh -n ansible/ansible_setup.sh
bash -n ansible/files/etc/profile.d/ansible.sh
bash -n ansible/files/usr/local/bin/ansible-local-switch
bash -n ansible/files/usr/local/bin/adoc
git diff --check
```
