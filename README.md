# Shystemd
 
Welcome to Shystemd, a lightweight partial replacement for `systemctl` and `journalctl` written largely in GNU Bash and GNU Make, heavily leveraging the `daemon` program by raf *<raf@raf.org>*.

Copyright (c) 2022 Kings Distributed Systems.
Released under the terms of the MIT License.

## Getting Started, the tldr; version
```bash
git clone https://github.com/wesgarland/shystemd
cd shystemd
sudo ./install.sh
# Add/edit your /etc/systemd/system files
sudo systemctl daemon-reload
sudo systemctl start myservice
```
**Note:** the installer will not make symlinks to overwrite "real" systemd resources. To run shystemd alongside systemd, you will have to use `shystemctl` and `jhournalctl`.

**Warning:** *this is early alpha software and loaded with bugs. It needs root access to your system. It can break things. You have been warned. If you don't understand this warning, please ask your system administrator for help.*

## Rationale
At Kings Distributed Systems, we use systemd to manage many processes on our servers, and our systemd unit files are machine-generated from another set of config files. We wanted to be able to test our platform in a variety production-like environments, and full testing would include start/stop operation via `systemctl`. Our test environments include:
 - Docker containers, especially in GitLab CI
 - directories on the local filesystem where we set an alternate root via environment variables
 - chroot jails on developer machines

## Installing
Clone the repository, and `sudo shystemd/install.sh`. If your environment does not have a copy of systemd installed, symlinks will be made for `systemctl` and `journalctl`.  The installer writes in the usual LSB locations (`/bin`, `/etc`, `/usr/lib/` etc) by default, except on macOS where it installs into `/usr/local`.

The installer will not overwrite an existing systemd configuration. You can specify an alternate root via the SHYSTEMD_PREFIX environment variable.

### Prerequisties
- UNIX-like Operating System
- Bash 3.2 or better
- GNU Make 3.81 or better
- daemon 0.6 or better
	- Ubuntu: `sudo apt-get install daemon`
	- Mac Homebrew: `sudo brew install daemon` 
	- Source Code: https://github.com/raforg/daemon
- typical OS utilities, usually part of default install on macOS, Ubuntu, etc
	- pkill (procps package)
	- grep
	- sed
	- touch
	- date
	- etc

#### Extras for Jhournalctl
- working C compiler

## Status
This product is lightly tested and should not be used for production work, or on any machine which contains critical information. There are semantic differences between `shystemctl` and `systemctl`, however they relatively minimal.

### Supported
- System services  (/etc/systemd/system/*.service)
- Most systemctl commands
- Most journalctl commands and options

### Not Supported
- SVR4-style init.d (coming?)
- User Login services (/etc/systemd/user)
- socket
- dbus messaging

### Major Semantic Differences
- Unit patterns in `systemctl` are resolved against units loaded memory; `shystemctl` patterns are resolved against unit files on the disk.
- `systemctl` uses a graphical authentication frontend to ask for passwords; `shystemctl` uses `sudo`
- `PrivateTmp` support in `shystemd` doesn't really work as expected; it just makes and cleans up an extra `$TMPDIR`.
- `systemctl` can send logs to syslog and the journal; `shystemctl` can only send to one or the other

### shystemctl commands
Command                | Description
|:---------------------|:-------------
daemon-reload          | Parse the unit files so that they can be used by other commands.
stop PATTERN...        | Stop (deactivate) one or more units specified on the command line.
start PATTERN...       | Start (activate) one or more units specified on the command line.
restart PATTERN...     | Stop and then start one or more units specified on the command line. If the units are not running yet, they will be started.
show-config PATTERN... | *extension* - dump configuration information to console

### Unit File Variables and Concepts
- WantedBy and After dependencies are supported and can be resolved in parallel
- pattern (template) units are supported
- %-based specifiers are supported
- [Unit] variables:
	- ConditionPathExists (including `!`)
	- After
	- Description
- [System] variables:
	- User
	- Group
	- Type
	- WorkingDirectory
	- KillSignal (need newer daemon with --signal for full support)
	- StandardError
	- StandardOutput
	- PIDFile
	- Type (forking, oneshot, simple)
	- Restart
	- WorkingDirectory
	- Environment
	- PrivateTmp (not really)
	- StartLimitBurst
	- StartLimitIntervalSec
	- ExecStart

### jhournalctl commands
- None yet

## Environment Variables

Shystemd uses GNU Make variables, which inherit from the environment, to represent variables in unit files. These variables are proceeded by their section labels and an underscore, so for example, the PIDFile variable in the [Service] section becomes `$Service_PIDFile`. Shystemctl is careful to not override any variables from the environment with defaults, so as long as those variables aren't overridden by the unit definition (or template), they will have the same effect as though they were actually part of the file. Similar, variables which can be specified multiple times meaningfully (eg. Environment) will be added to, with the first value coming from the environment.  What this means is that arbitrary extra settings can be injected from the environment without modifying the unit files; this is expected to be useful for CI systems.

| Variable (install.sh)       | Details
|:----------------------------|---------------------------------------
| SHYSTEMD_PREFIX             | Where to install shystemd, default=`/` or `/usr/local` on Darwin

| Variable (general)          | Details
|:----------------------------|---------------------------------------
| make                        | Location of GNU Make 3.81 or higher
| SYSTEMD_CONF_ROOT           | Where systemd units are located, default=`${SHYSTEMD_PREFIX}/etc/system`
| SHYSTEMD_SCRATCH_DIR        | Location to write pid files, semaphores, etc
| SHYSTEMD_NO_PARALLELISM     | Disable start/stopping units parallel
| SHYSTEMD_PARALLELISM        | Limit # of units to start/start in parallel, default=10
| SHYSTEMD_DEBUG              | Enable debug mode, eg show make rules as they are run
| SHYSTEMD_DRY_RUN            | Try (!!) not to do anything with side effects, print those commands instead
| SHYSTEMD_NO_SUDO            | Don't try to sudo when shystemd needs more permissions
| DISABLE_JHOURNALD	      | Don't use jhournald, write stdout/stderr directly to logs w/o timestamps etc
| JHOURNALD_LOG_DIR	      | Directory where logs and/or journals are stored
