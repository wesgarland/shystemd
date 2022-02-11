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

Service_User  ?= nobody
Service_Group ?= nogroup
Service_WorkingDirectory ?= /tmp

pidfile=$(SYSTEMD_CONF_ROOT)/shystemd-db/system/$(unit).pid
daemon=daemon -n $(unit) -N -F $(pidfile)
launch=$(daemon) -u$(Service_User):$(Service_Group) -D$(Service_WorkingDirectory)

ifeq ($(Service_Restart),always)
  launch += -r
endif
ifdef Service_StartLimitBurst
  launch += --limit=$(Service_StartLimitBurst)
endif
ifdef Service_StartLimitIntervalSec
  launch += --delay=$(Service_StartLimitIntervalSec)
endif

#-l logfile or syslog level
#-b debug log
#--running - check is running
#--stop - kill it
#--list
#--signal - send signal

# simple - blind launch
# oneshot - not successful unless process has exit=0
#ifeq ($(Service_Type),oneshot)  simple
#endif

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

# Make this target a dependency to dump info before other target
debug:
	@echo "unit=$(unit)"
	@echo "systemDir=$(systemDir)"
	@cat $(systemDir)/$(unit).service.mk

show-unit-config: debug show-config

start:  
	@echo Starting unit $(unit)
	$(launch) -n $(unit) $(Service_ExecStart)

start-%:
	$(MAKE) unit="$*" -f "${SHYSTEMD_LIB_DIR}"/service.mk start

stop:
	$(daemon) --stop

stop-%:
	$(MAKE) unit="$*" -f "${SHYSTEMD_LIB_DIR}"/service.mk stop

running:
	$(daemon) --running && echo RUNNING
