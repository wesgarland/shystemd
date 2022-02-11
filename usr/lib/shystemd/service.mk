# @file		service.mk
#
#		Makefile for systemctl to handle actions for services.
#		Service definition files are filtered into .mk includes,
#		which this file then makes use of.
#
# @author	Wes Garland, wes@kingsds.network
# @date		Feb 2022
#

systemDir=$(SYSTEMD_CONF_ROOT)/shystemd-db/system
ifdef unit
  include $(systemDir)/$(unit).service.mk
  -include $(systemDir)/$(unit).service.deps
endif
include $(SHYSTEMD_ETC_DIR)/system-unit-defaults.mk

# Figure out basic parameters for running daemon
daemon=$(sudo) daemon -n $(unit) -N
ifdef Service_PIDFile
  pidfile = $(Service_PIDFile)
else
  pidfile = $(SYSTEMD_CONF_ROOT)/shystemd-db/system/$(unit).pid
endif
ifneq ($(Service_Type),forking)  # forking => daemon manages own pidfile
  daemon += -F $(pidfile)
endif
ifdef Service_User
  ifneq ($(Service_User),$(shell whoami))
    sudo=sudo -E --user=$(Service_User)
    daemon += -u$(Service_User):$(Service_Group)
endif
endif
ifdef ServiceGroup
  ifndef $(findstring $(ServiceGroup),$(shell groups))
    ifndef sudo
      sudo=sudo -E
      daemon += -u$(Service_User):$(Service_Group)
    endif
    sudo += --group=$(Service_Group)
  endif
endif

# Figure out daemon parameters to start services
launch = $(daemon) -D$(Service_WorkingDirectory)
launch += $(foreach assignment, $(Service_Environment),-e "$(assignment)")
ifeq ($(Service_Restart),always)
  launch += -r
endif
ifdef Service_StartLimitBurst
  launch += --limit=$(Service_StartLimitBurst)
endif
ifdef Service_StartLimitIntervalSec
  launch += --delay=$(Service_StartLimitIntervalSec)
endif
ifeq ($(Service_Type),oneshot)
  launch += '--foreground'
endif

# Try to emulate PrivateTmp with extra deps and TMPDIR - not very complete (yet?)
# Future: investigate FireJail for PrivateTmp, PrivateBin, etc
ifdef Service_PrivateTmp
  start-deps += mk-private-tmp
  stop-deps += rm-private-tmp
  launch += -e "TMPDIR=$(shell head -1 $(patsubst %.pid,%.tmpdir,$(pidfile)))"
endif

#-l logfile or syslog level
#-b debug log
#--running - check is running
#--list
#--signal - send signal

# simple - blind launch
# oneshot - not successful unless process has exit=0

status:
	@printf "%s\t%s\n" "$(unit_basename)" "$(Unit_Description)"

.PHONY: deps
deps:
#	@echo Building deps - $(unit) is needed by $(Install_WantedBy)
	@$(shell $(foreach dep, $(Install_WantedBy), echo start: start-$(unit) >> $(systemDir)/$(dep).deps;))
	@$(shell $(foreach dep, $(Install_WantedBy), echo stop: stop-$(unit) >> $(systemDir)/$(dep).deps;))
	@true

show-config:
	@echo launch="$(launch)"
	@echo "Service_User=$(Service_User)"
	@echo "sudo=$(sudo)"

# Make this target a dependency to dump info before other target
debug:
	@echo "unit=$(unit)"
	@echo "pidfile=$(pidfile)"
	@echo "systemDir=$(systemDir)"
	@cat $(systemDir)/$(unit).service.mk

show-unit-config: debug show-config

# Figure out if a service is running
running:
	$(daemon) --running && echo RUNNING

start-deps: $(start-deps)
# Start a unit
start: $(start-deps)
	@echo Starting unit $(unit)
	$(launch) $(Service_ExecStart)
ifeq ($(Service_RemainAfterExit),yes)
	touch $(patsubst %.pid,%.ran,$(pidfile))
endif
ifdef sudo
	sudo -k
endif

# Stop a unit
# Note: Requires newer (0.8?) version of daemon to ensure correct kill signal is sent
stop: $(stop-deps)
ifeq ($(Service_Type),forking)
	$(sudo) kill -$(Service_KillSignal) $(shell head -1 $(pidfile))
else
	$(daemon) --signal=$(Service_KillSignal) 2>/dev/null || true
	rm -f $(patsubst %.pid,%.ran,$(pidfile))
	$(daemon) --stop
endif
ifdef sudo
	sudo -k
endif

# Restart a unit
restart:
	$(sudo) $(MAKE) unit="$*" -f "${SHYSTEMD_LIB_DIR}"/service.mk stop
	$(sudo) $(MAKE) unit="$*" -f "${SHYSTEMD_LIB_DIR}"/service.mk start

# Pattern rules start and stop dependencies via submake. Dependencies are listed
# in *.deps files, their target names begin with start- and stop-, and are built
# by daemon-reload.
stop-%:
	$(sudo) $(MAKE) unit="$*" -f "${SHYSTEMD_LIB_DIR}"/service.mk stop
start-%:
	$(sudo) $(MAKE) unit="$*" -f "${SHYSTEMD_LIB_DIR}"/service.mk start

mk-private-tmp rm-private-tmp: ptmpdirLoc=$(patsubst %.pid,%.tmpdir,$(pidfile))
mk-private-tmp:
	$(sudo) mktemp -d $(SHYSTEMD_PRIVATE_TMP_ROOT).$(unit).XXXXXX > $(tmpdirLoc)
	$(sudo) mkdir $(shell head -1 $(patsubst %.pid,%.tmpdir,$(pidfile)))/tmp

rm-private-tmp: ptmpdir=$(shell head -1 $(patsubst %.pid,%.tmpdir,$(pidfile)))
rm-private-tmp:
	@test -s $(patsubst %.pid,%.tmpdir,$(pidfile)) || echo "Cannot rm-private-tmp for unit $(unit) - missing file" >&2 && exit 1
	@test X$(find $(SHYSTEMD_PRIVATE_TMP_ROOT),$(ptmpdir)) != X
	@test -d $(shell head -1 $(patsubst %.pid,%.tmpdir,$(pidfile))) 
	$(sudo) rm -rf $(tmpdir)
