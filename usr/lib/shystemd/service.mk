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

include $(systemDir)/$(unit).service.mk
-include $(systemDir)/$(unit).service.deps

pidfile=$(SYSTEMD_CONF_ROOT)/shystemd-db/system/$(unit).pid
daemon=daemon -N -F $(pidfile)

#-u user:group
#-D directory
#-r is respawn
#-l logfile or syslog level
#--running - check is running
#--stop - kill it
#--list
#--signal - send signal

ifeq ($(Service_Type),oneshot)
  launch=$(daemon)
else
  launch=$(daemon) -r
endif

status:
	@printf "%s\t%s\n" "$(unit_basename)" "$(Unit_Description)"

.PHONY: deps
deps:
#	@echo Building deps - $(unit) is needed by $(Install_WantedBy)
	@$(shell $(foreach dep, $(Install_WantedBy), echo start: start-$(unit) >> $(systemDir)/$(dep).deps;))
	@$(shell $(foreach dep, $(Install_WantedBy), echo stop: stop-$(unit) >> $(systemDir)/$(dep).deps;))
	@true

# Make this target a dependency to dump info before other target
debug:
	@echo "unit=$(unit)"
	@echo "systemDir=$(systemDir)"
	@cat $(systemDir)/$(unit).service.mk

start:  
	@echo Starting unit $(unit)
	$(launch) -n $(unit) $(Service_ExecStart)

start-%:
	$(MAKE) unit="$*" -f "${SHYSTEMD_LIB_DIR}"/service.mk start
