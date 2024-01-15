# @file		service.mk
#
#		Makefile for systemctl to handle actions for services.
#		Service definition files are filtered into .mk includes,
#		which this file then makes use of.
#
#               See parse_unit comment and systemd.init man page for unit
#		information re. unit_ nomenclature.
#
# @author	Wes Garland, wes@kingsds.network
# @date		Feb 2022
#

# Load config for this unit
systemDir ?= $(SHYSTEMD_SCRATCH_DIR)
scratchDir ?= $(SHYSTEMD_SCRATCH_DIR)
ifdef unit
  unit_prefix=$(shell echo "$(unit)" | sed 's/@.*//')
  include $(systemDir)/$(unit_prefix).service.mk
  -include $(systemDir)/$(unit_prefix).service.deps
endif
include $(SHYSTEMD_ETC_DIR)/system-unit-defaults.mk

# Function to unescape specifies like %i in unit files, and arguments
# used with these from parse-unit
unescape = $(shell printf -- '$(1)' | sed 's;-;/;g')

# Basic parameters for running daemon
daemon=$(sudoRoot) $(daemonCmd) -n $(unit) -NU
pidfile = $(scratchDir)/$(unit).pid
journal-pidfile = $(scratchDir)/journal-$(unit).pid

daemonCmd=daemon -i
ifneq ($(Service_Type),forking)  # forking => daemon manages own pidfile
  daemon += -F $(pidfile)
endif
DAEMON_VER:=$(shell daemon --version | sed -e 's/daemon-//' -e 's/\./ /g')
DAEMON_MAJ_VER:=$(word 1,$(DAEMON_VER))
DAEMON_MIN_VER:=$(word 2,$(DAEMON_VER))
DAEMON_REV_VER:=$(word 3,$(DAEMON_VER))
ifneq (06,$(DAEMON_MAJ_VER)$(DAEMON_MIN_VER))
  daemonCmd += --ignore-eof
endif

# Permissions for running daemon. If we are not already running as the unit's
# correct user, the variables sudoRoot and sudoUser are defined, otherwise blank.
# sudoUser is the sudo command to become the unit's user. sudoRoot is the sudo
# command to become root, the command using sudoRoot must drop perms itself.
ifdef Service_User
  ifneq ($(Service_User),$(shell whoami)) 
    sudoUser=sudo -E --user=$(Service_User)
    sudoRoot=sudo -E
    daemon += -u$(Service_User):$(Service_Group)
  endif
  ifeq ($(Service_User),root)
    daemon += --idiot
  endif	
endif
ifdef ServiceGroup
  ifndef $(findstring $(ServiceGroup),$(shell groups))
    ifndef sudo
      sudoRoot=sudo -E
      daemon += -u$(Service_User):$(Service_Group)
    endif
    sudoUser += --group=$(Service_Group)
  endif
endif

ifdef SHYSTEMD_NO_SUDO
  ifdef sudoRoot
    $(warning Failed to $(MAKECMDGOALS) $(unit_fullname): Interactive authentication required.)
    $(error See system logs and '$(shystemctl_name) status $(unit_fullname)' for details.)
  endif
endif

# Neuter commands with side effects during --dry-run
ifdef SHYSTEMD_DRY_RUN
  daemon:=@echo \> $(daemon)
  rm=@echo \> rm
  touch=@echo \> touch
  mkfifo=@echo \> mkfifo
else
  rm=rm
  touch=touch
  mkfifo=mkfifo
endif

# Basic Parameters to start / monitor services
launch = $(daemon) -D$(Service_WorkingDirectory)
launch += $(foreach assignment, $(Service_Environment),-e "$(assignment)")
ifeq ($(Service_Restart),always)
  launch += --respawn
  ifdef Service_StartLimitInterval
    Unit_StartLimitIntervalSec=$(Service_StartLimitInterval)
  endif
  ifdef Unit_StartLimitIntervalSec
    launch += --delay=$(Unit_StartLimitIntervalSec)
  else
    launch += --delay=10
  endif
endif
ifeq ($(Service_Restart),on-failure)
  # no support for on-failure, treat like always
  launch += --respawn
endif
ifeq ($(Service_Type),oneshot)
  launch += --foreground
endif
ifdef Service_StartLimitBurst
  launch += --limit=$(Service_StartLimitBurst)
endif

# Logging
ifeq ($(Service_StandardOutput),syslog)
  launch += --stdout=local7.debug -l local7.info
else ifeq ($(Service_StandardOutput),journal)
  launch += --stdout=$(JHOURNALD_LOG_DIR)/$(unit_prefix).$(journal_ext) -l $(JHOURNALD_LOG_DIR)/$(unit_prefix).$(journal_ext)
  start-deps += $(JHOURNALD_LOG_DIR)/$(unit_prefix).$(journal_ext) start-journal
endif
ifeq ($(Service_StandardError),syslog)
  launch += --stdout=local7.notice -b local7.error
else ifeq ($(Service_StandardError),journal)
  launch += --stderr=$(JHOURNALD_LOG_DIR)/$(unit_prefix).$(journal_ext) -b $(JHOURNALD_LOG_DIR)/$(unit_prefix).$(journal_ext)
endif
ifdef DISABLE_JHOURNALD
  journal_ext=log
else
  journal_ext=pipe
endif

# Try to emulate PrivateTmp with extra deps and TMPDIR - not very complete (yet?)
# Future: investigate FireJail for PrivateTmp, PrivateBin, etc
ifdef Service_PrivateTmp
  start-deps += mk-private-tmp
  stop-deps += rm-private-tmp
  launch += -e "TMPDIR=$(shell head -1 $(scratchDir)/$(unit).privateRoot)"
endif

###############################################################################
# Display unit status
status:
	@printf "%s\tloaded\t%s\t%s\t%s\n" "$(unit)" activeOrFailed runningExitedOrFailed "$(Unit_Description)"

###############################################################################
# Figure out if a unit is running
running:
	$(daemon) --running && echo RUNNING

###############################################################################
# Generate unit dependencies - used by daemon-reload - similar to makedepend
.PHONY: deps
deps: $(JHOURNALD_LOG_DIR)/$(unit_prefix).journal
ifdef SHYSTEMD_DEBUG
	@echo Building deps - $(unit) is needed by $(Install_WantedBy)
endif
	$(shell $(foreach dep, $(Install_WantedBy), echo start: start-$(unit_prefix) >> $(systemDir)/$(dep).deps;))
	$(shell $(foreach dep, $(Install_WantedBy), echo stop:  stop-$(unit_prefix)  >> $(systemDir)/$(dep).deps;))
	$(shell $(foreach dep, $(Unit_After), echo start: start-$(dep) >> $(systemDir)/$(unit_prefix).deps;))
	$(shell $(foreach dep, $(Unit_After), echo stop:  stop-$(dep)  >> $(systemDir)/$(unit_prefix).deps;))
	@true

###############################################################################
# Troubleshooting targets
show-config:
	@echo pwd=$(shell pwd)	
	@echo launch="$(launch)"
	@echo "Service_User=$(Service_User)"
	@echo "sudoUser=$(sudoUser)"

# Make this target a dependency to dump info before other target
debug:
	@echo "unit=$(unit)"
	@echo "pidfile=$(pidfile)"
	@echo "systemDir=$(systemDir)"
	@echo "whoami=$(shell whoami)"
	@cat $(systemDir)/$(unit_prefix).service.mk
	@echo start deps: $(start-deps)
	@echo Unit_ConditionPathExists=$(Unit_ConditionPathExists)

show-unit-config: debug show-config

###############################################################################
# Add extra deps to start for ConditionPathExists
ifdef Unit_ConditionPathExists
start: exists not-exists
# Dependency to block starting if file in Unit_ConditionPathExists is missing
exists: need=$(filter-out !%,$(Unit_ConditionPathExists))
exists: have=$(wildcard $(need))
exists:
	test "$(need)" = "$(have)"

# Dependency to block starting if !file in Unit_ConditionPathExists exists
not-exists: dontwant=$(patsubst !%,%,$(filter !%,$(Unit_ConditionPathExists)))
not-exists: have=$(wildcard $(dontwant))
not-exists:
	test -s $(strip $(have)) || echo "Can't start unit $(unit) due to presence of $(dontwant)" >&2
	test -s $(strip $(have))
endif #Unit_ConditionPathExists

###############################################################################
# Start a unit
#
# Launches an instance of daemon to monitor the process, and (by means of $(start-deps)),
# and instance which monitors jhournald if this service is configured ot used the journal.
#
start: $(start-deps)
	@[ ! "$(SHYSTEMD_VERBOSE)" ] || echo Starting unit $(unit)
	$(launch) -- $(Service_ExecStart)
ifeq ($(Service_RemainAfterExit),yes)
	$(touch) $(scratchDir)/$(unit).ran
endif

stop: daemon-pid=$(shell head -1 $(pidfile) 2>/dev/null)
###############################################################################
# Stop a unit
#
# - Type=Forking services should have PIDFile set, so that we kill the service daemon, 
#   rather than the pid that $(daemon) was launched as
stop: daemon-pid=$(shell head -1 $(pidfile) 2>/dev/null)
stop: $(stop-deps)
	@[ ! "$(SHYSTEMD_VERBOSE)" ] || echo Stopping unit $(unit)
	$(rm) -f $(scratchDir)/$(unit).ran
ifeq ($(Service_Type),forking) 
        # service-managed pid file, daemon has already exited
	[ -f $(Service_PIDFILE) ] && $(sudoUser) kill -$(Service_KillSignal) $(Service_PIDFile) || true
	[ -f $(Service_PIDFile) ] && $(sudoUser) pkill -0 -F $(Service_PIDFile) && sleep 1 && $(sudoUser) pkill -TERM -F $(Service_PIDFile) || true
	[ -f $(Service_PIDFile) ] && $(sudoUser) pkill -0 -F $(Service_PIDFile) && sleep 1 && $(sudoUser) pkill -TERM -F $(Service_PIDFile) || true
	[ -f $(Service_PIDFile) ] && $(sudoUser) pkill -0 -F $(Service_PIDFile) && sleep 1 && $(sudoUser) pkill -9    -F $(Service_PIDFile) || true
	rm -f $(Service_PIDFile)
else
	[ -f $(pidfile) -a "$(daemon-pid)" ] && $(sudoUser) pkill -$(Service_KillSignal) -P $(daemon-pid) . || true
	[ -f $(pidfile) ] && $(daemon) --stop && sleep 0.1 || true
	[ -f $(pidfile) -a "$(daemon-pid)" ] && $(sudoUser) pkill -0 -P $(daemon-pid) . && sleep 1 && $(sudoUser) pkill -TERM -P $(daemon-pid) . || true
	[ -f $(pidfile) -a "$(daemon-pid)" ] && $(sudoUser) pkill -0 -P $(daemon-pid) . && sleep 1 && $(sudoUser) pkill -TERM -P $(daemon-pid) . || true
	[ -f $(pidfile) -a "$(daemon-pid)" ] && $(sudoUser) pkill -0 -P $(daemon-pid) . && sleep 1 && $(sudoUser) pkill -TERM -P $(daemon-pid) . || true
	[ -f $(pidfile) -a "$(daemon-pid)" ] && $(sudoUser) pkill -0 -P $(daemon-pid) . && sleep 1 && $(sudoUser) pkill -9    -P $(daemon-pid) . || true
	[ -f $(pidfile) ] && $(sudoUser) pkill -9 -F $(pidfile) || true
endif 
        # Tell jhournald to stop, then make it stop.
	[ -f $(journal-pidfile) ] && $(sudoRoot) daemon -n jhournald-$(unit_prefix) -NUF $(journal-pidfile) --stop && sleep 0.1 || true
	[ -f $(journal-pidfile) ] && sleep 1 && $(sudoUser) pkill -TERM -F $(journal-pidfile) 2>/dev/null	|| true
	[ -f $(journal-pidfile) ] && sleep 1 && $(sudoUser) pkill -TERM -F $(journal-pidfile) 2>/dev/null	|| true
	[ -f $(journal-pidfile) ] && sleep 1 && $(sudoUser) pkill -TERM -F $(journal-pidfile) 2>/dev/null	|| true
	[ -f $(journal-pidfile) ] && sleep 1 && $(sudoUser) pkill -9    -F $(journal-pidfile)			|| true
        # remove the journald pidfile only if the process is not running
	[ ! -f $(journal-pidfile) ] || ! $(sudoUser) pkill -0 -F $(journal-pidfile)
	rm -f $(journal-pidfile)

###############################################################################
# Restart a unit
restart:
	[ -f "$(Service_PIDFILE)" ] && $(daemon) --restart || $(MAKE) unit="$*" -f "${SHYSTEMD_LIB_DIR}"/service.mk stop
	[ ! -f "$(Service_PIDFILE)" ] && $(MAKE) unit="$*" -f "${SHYSTEMD_LIB_DIR}"/service.mk start

###############################################################################
# Pattern rules start and stop dependencies via submake. Dependencies are listed
# in *.deps files, their target names begin with start- and stop-, and are built
# by daemon-reload.
stop-%:
	$(MAKE) unit="$*" -f "${SHYSTEMD_LIB_DIR}"/service.mk stop
start-%:
	$(MAKE) unit="$*" -f "${SHYSTEMD_LIB_DIR}"/service.mk start

###############################################################################
# Set up resources that daemon will need to talk to jhournald or log files
$(JHOURNALD_LOG_DIR):
	mkdir -m1777 "$@"
$(JHOURNALD_LOG_DIR)/$(unit_prefix).journal: $(JHOURNALD_LOG_DIR)
	$(sudoUser) $(touch) $@
	sudo chgrp ${SHYSTEMD_ADM_GROUP} $@ || true
	sudo chmod 640 $@ || true

ifndef DISABLE_JHOURNALD
$(JHOURNALD_LOG_DIR)/$(unit_prefix).pipe: $(JHOURNALD_LOG_DIR)
	test -p $@ || $(sudoUser) $(mkfifo) $@
ifeq ($(Service_Restart),always)
start-journal: daemon-opts+=--respawn
endif

###############################################################################
# Start the journal if it is not running - jhournald reads the output pipe, adds
# a synthetic timestamp and pid, and writes to the .journal file.
start-journal: $(JHOURNALD_LOG_DIR)/$(unit_prefix).$(journal_ext)
	$(sudoUser) $(daemonCmd) -n jhournald-$(unit_prefix) -NUF $(journal-pidfile) --running || \
	$(sudoUser) $(daemonCmd) -n jhournald-$(unit_prefix) -NUF $(journal-pidfile) $(daemon-opts) \
	  --stdout=$(JHOURNALD_LOG_DIR)/jhournald-$(unit_prefix).stdout \
	  --stderr=$(JHOURNALD_LOG_DIR)/jhournald-$(unit_prefix).stderr \
	  -- ${SHYSTEMD_BIN_DIR}/jhournald --daemon-pidfile=$(pidfile) $(addprefix --name=,$(notdir $(first-word Service_ExecStart))) $(unit)
else
###############################################################################
# Make sure we can make a log since the journals are turned off
start-journal: $(JHOURNALD_LOG_DIR)/$(unit_prefix).log $(JHOURNALD_LOG_DIR)
	@true
$(JHOURNALD_LOG_DIR)/$(unit_prefix).log: $(JHOURNALD_LOG_DIR)
	@date >> $@
endif # DISABLE_JHOURNALD

###############################################################################
# Beware - private root support is incomplete and untested
# Alternate pointer implementation idea: use a symlink and dereference with realpath
ifndef SHYSTEMD_DRY_RUN
privateRootPtr=$(scratchDir)/$(unit).privateRoot
mk-private-root:
	$(sudoRoot) mktemp -d $(SHYSTEMD_PRIVATE_TMP_ROOT).$(unit).XXXXXX > $(privateRootPtr)
	$(sudoRoot) chown $(Service_User):$(Service_Group) $(shell head -1 $(privateRootPtr))
mk-private-tmp: privateRoot=$(shell head -1 $(privateRootPtr))
mk-private-tmp: mk-private-root
	$(sudoRoot) mkdir -m1777 $(shell head -1 $(privateRootPtr))/tmp
	$(sudoRoot) chown $(Service_User):$(Service_Group) $(shell head -1 $(privateRootPtr))/tmp
rm-private-tmp: privateRoot=$(shell head -1 $(privateRootPtr))
rm-private-tmp:
	@!test -z $(strip $(privateRoot))
	@test $(privateRoot) != /
	$(sudoUser) rm -rf $(privateRoot)/tmp
rm-private-root: privateRoot=$(shell head -1 $(privateRootPtr))
rm-private-root: rm-private-tmp
	$(sudoRoot) rmdir $(privateRoot)
	$(sudoRoot) rm $(privateRootPtr)
endif #SHYSTEMD_DRY_RUN
