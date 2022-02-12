# @file		service.mk
#
#		Makefile for systemctl to handle actions for services.
#		Service definition files are filtered into .mk includes,
#		which this file then makes use of.
#
# @author	Wes Garland, wes@kingsds.network
# @date		Feb 2022
#

systemDir ?= $(SHYSTEMD_SCRATCH_DIR)
scratchDir ?= $(SHYSTEMD_SCRATCH_DIR)
ifdef unit
  include $(systemDir)/$(unit).service.mk
  -include $(systemDir)/$(unit).service.deps
endif
include $(SHYSTEMD_ETC_DIR)/system-unit-defaults.mk

# Basic parameters for running daemon
daemon=$(sudoRoot) daemon -n $(unit) -N
ifdef Service_PIDFile
  pidfile = $(Service_PIDFile)
else
  pidfile = $(scratchDir)/$(unit).pid
endif

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
  launch += --stdout=$(JHOURNALD_LOG_DIR)/$(unit).log -l $(JHOURNALD_LOG_DIR)/$(unit).log
endif
ifeq ($(Service_StandardError),syslog)
  launch += --stdout=local7.notice -b local7.error
else ifeq ($(Service_StandardError),journal)
  launch += --stderr=$(JHOURNALD_LOG_DIR)/$(unit).log -b $(JHOURNALD_LOG_DIR)/$(unit).log
endif

# Try to emulate PrivateTmp with extra deps and TMPDIR - not very complete (yet?)
# Future: investigate FireJail for PrivateTmp, PrivateBin, etc
ifdef Service_PrivateTmp
  start-deps += mk-private-tmp
  stop-deps += rm-private-tmp
  launch += -e "TMPDIR=$(shell head -1 $(scratchDir)/$(unit).privateRoot)"
endif

status:
	@printf "%s\t%s\n" "$(unit_basename)" "$(Unit_Description)"

.PHONY: deps
deps:
#	@echo Building deps - $(unit) is needed by $(Install_WantedBy)
	@$(shell $(foreach dep, $(Install_WantedBy), echo start: start-$(unit) >> $(systemDir)/$(dep).deps;))
	@$(shell $(foreach dep, $(Install_WantedBy), echo stop:  stop-$(unit)  >> $(systemDir)/$(dep).deps;))
	@$(shell $(foreach dep, $(Unit_After), echo start: start-$(dep) >> $(systemDir)/$(unit).deps;))
	@$(shell $(foreach dep, $(Unit_After), echo stop:  stop-$(dep)  >> $(systemDir)/$(unit).deps;))
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
	@cat $(systemDir)/$(unit).service.mk
	@echo start deps: $(start-deps)
	@echo Unit_ConditionPathExists=$(Unit_ConditionPathExists)

show-unit-config: debug show-config

# Figure out if a service is running
running:
	$(daemon) --running && echo RUNNING

# Start a unit
ifdef Unit_ConditionPathExists
start: exists not-exists
endif
start: $(start-deps)
	@echo Starting unit $(unit)
	$(launch) -X "$(Service_ExecStart)"
ifeq ($(Service_RemainAfterExit),yes)
	touch $(scratchDir)/$(unit).ran
endif

# Stop a unit
# Note: Requires newer (0.8?) version of daemon to ensure correct kill signal is sent
stop: $(stop-deps)
ifeq ($(Service_Type),forking)
	$(sudoUser) kill -$(Service_KillSignal) $(shell head -1 $(pidfile))
else
	$(daemon) --signal=$(Service_KillSignal) 2>/dev/null || true
	$(daemon) --stop
	rm -f $(scratchDir)/$(unit).ran $(scratchDir)/$(unit).pid
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

# Dependency to block starting if file in Unit_ConditionPathExists is missing
exists: need=$(filter-out !%,$(Unit_ConditionPathExists))
exists: have=$(wildcard $(need))
exists:
	@test "$(need)" = "$(have)"

# Dependency to block starting if !file in Unit_ConditionPathExists exists
not-exists: dontwant=$(patsubst !%,%,$(filter !%,$(Unit_ConditionPathExists)))
not-exists: have=$(wildcard $(dontwant))
not-exists:
	@test -s $(strip $(have)) || echo "Can't start unit $(unit) due to presence of $(dontwant)" >&2
	@test -s $(strip $(have))

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


