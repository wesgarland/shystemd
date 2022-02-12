# Shystemd
 
Welcome to Shystemd, a lightweight partial replacement for `systemctl` and `journalctl` written largely in GNU Bash and GNU Make.

Copyright (c) 2022 Kings Distributed Systems.
Licensed under the terms of the MIT License.

## Rationale
At Kings Distributed Systems, we use systemd to manage many processes on our servers, and our systemd unit files are machine-generated from another set of config files. We wanted to be able to test our platform in a variety production-like environments, and full testing would include start/stop operation via `systemctl`. Our test environments include:
 - Docker images, especially in GitLab CI
 - directories on the local filesystem where we set an alternate root via environment variables
 - chroot jails on developer machines

## Installing
Clone the repository, and run the `./install.sh` script as root. If your environment does not have a copy of systemd installed, symlinks will be made for `systemctl` and `journalctl`.  The installer writes in the usual LSB locations (`/bin`, `/etc`, `/usr/lib/` etc) by default, except on Darwin where it installs into `/usr/local`.

The installer will not overwrite an existing systemd configuration. You can specify an alternate root via the SHYSTEMD_PREFIX environment variable.

### Prerequisties
- UNIX-like Operating System
- Bash 3.2 or better
- GNU Make 3.81 or better
- daemon 0.6 or better
	- Ubuntu: `sudo apt-get install daemon`
	- Mac Homebrew: `sudo brew install daemon` 

## Status
This product is lightly tested and should not be used for production work, or on any machine which contains critical information. There are semantic differences between `shystemctl` and `systemctl`, however they relatively minimal.

### Semantic Differences
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
- pattern units are supported
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

