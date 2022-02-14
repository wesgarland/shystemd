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
daemon=$(sudoRoot) $(daemonCmd) -n $(unit) -N
ifdef Service_PIDFile
  pidfile = $(Service_PIDFile)
else
  pidfile = $(scratchDir)/$(unit).pid
endif

daemonCmd=daemon
ifneq ($(Service_Type),forking)  # forking => daemon manages own pidfile
  daemon += -F $(pidfile)
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
endif
ifeq ($(Service_Type),oneshot)
  launch += --foreground
endif
ifdef Service_StartLimitBurst
  launch += --limit=$(Service_StartLimitBurst)
endif
ifdef Service_StartLimitIntervalSec
  launch += --delay=$(Service_StartLimitIntervalSec)
endif

# Logging
ifeq ($(Service_StandardOutput),syslog)
  launch += --stdout=local7.debug -l local7.info
else ifeq ($(Service_StandardOutput),journal)
  launch += --stdout=$(JHOURNALD_LOG_DIR)/$(unit_prefix).$(journal_ext) -l $(JHOURNALD_LOG_DIR)/$(unit_prefix).$(journal_ext)
  start-deps += $(JHOURNALD_LOG_DIR)/$(unit_prefix).$(journal_ext) start-journal
  stop-deps += stop-journal
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

status:
	@printf "%s\tloaded\t%s\t%s\t%s\n" "$(unit)" activeOrFailed runningExitedOrFailed "$(Unit_Description)"

.PHONY: deps
deps:
ifdef SHYSTEMD_DEBUG
	@echo Building deps - $(unit) is needed by $(Install_WantedBy)
endif
	$(shell $(foreach dep, $(Install_WantedBy), echo start: start-$(unit_prefix) >> $(systemDir)/$(dep).deps;))
	$(shell $(foreach dep, $(Install_WantedBy), echo stop:  stop-$(unit_prefix)  >> $(systemDir)/$(dep).deps;))
	$(shell $(foreach dep, $(Unit_After), echo start: start-$(dep) >> $(systemDir)/$(unit_prefix).deps;))
	$(shell $(foreach dep, $(Unit_After), echo stop:  stop-$(dep)  >> $(systemDir)/$(unit_prefix).deps;))
	@true

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

# Figure out if a service is running
running:
	$(daemon) --running && echo RUNNING

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

# Start a unit
start: $(start-deps)
	@echo Starting unit $(unit)
	$(launch) -- $(Service_ExecStart)
ifeq ($(Service_RemainAfterExit),yes)
	$(touch) $(scratchDir)/$(unit).ran
endif

# Stop a unit
# Note: Requires newer (0.8?) version of daemon to ensure correct kill signal is sent
stop: $(stop-deps)
	@echo Stopping unit $(unit)
ifeq ($(Service_Type),forking)
	$(sudoUser) kill -$(Service_KillSignal) $(shell head -1 $(pidfile))
else
	$(daemon) --signal=$(Service_KillSignal) 2>/dev/null || true
	$(daemon) --stop || true
	$(rm) -f $(scratchDir)/$(unit).ran $(scratchDir)/$(unit).pid
endif

# Restart a unit
restart:
	$(sudoRoot) $(MAKE) unit="$*" -f "${SHYSTEMD_LIB_DIR}"/service.mk stop
	$(sudoRoot) $(MAKE) unit="$*" -f "${SHYSTEMD_LIB_DIR}"/service.mk start

# Pattern rules start and stop dependencies via submake. Dependencies are listed
# in *.deps files, their target names begin with start- and stop-, and are built
# by daemon-reload.
stop-%:
	$(sudoRoot) $(MAKE) unit="$*" -f "${SHYSTEMD_LIB_DIR}"/service.mk stop
start-%:
	$(sudoRoot) $(MAKE) unit="$*" -f "${SHYSTEMD_LIB_DIR}"/service.mk start

# Set up resources that daemon will need to talk to jhournald or log files
$(JHOURNALD_LOG_DIR):
	mkdir -m1777 "$@"
$(JHOURNALD_LOG_DIR)/$(unit_prefix).log: $(JHOURNALD_LOG_DIR)
	$(sudoUser) $(touch) $@
ifndef DISABLE_JHOURNALD
$(JHOURNALD_LOG_DIR)/$(unit_prefix).pipe: $(JHOURNALD_LOG_DIR)
	test -p $@ || $(sudoUser) $(mkfifo) $@
#XXXXXx fix logs
start-journal: $(JHOURNALD_LOG_DIR)/$(unit_prefix).$(journal_ext)
	$(sudoRoot) daemon -n journal-$(unit_prefix) -NF ${scratchDir}/jhournald-$(unit).pid -r \
	  --stdout=/tmp/stdout --stderr=/tmp/stderr \
	  -- ${SHYSTEMD_BIN_DIR}/jhournald --pidfile=$(pidfile) --name=$(strip $(notdir $(first-word Service_ExecStart))) $(unit)
stop-journal:
	$(sudoRoot) daemon -n journal-$(unit_prefix) -NF ${scratchDir}/jhournald-$(unit).pid --stop || true
else
start-journal: $(JHOURNALD_LOG_DIR)/$(unit_prefix).log: $(JHOURNALD_LOG_DIR)
	@true
stop-journal:
	@true
endif # DISABLE_JHOURNALD

ifndef SHYSTEMD_DRY_RUN
# Beware - private root is incomplete and untested
# Alternate pointer implementation idea: use a symlink and dereference with realpath
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
