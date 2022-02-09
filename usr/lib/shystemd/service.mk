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

status:
	@printf "%s\t%s\n" "$(unit_basename)" "$(Unit_Description)"

.PHONY: deps
deps:
#	@echo Building deps - $(unit) is needed by $(Install_WantedBy)
	@$(shell $(foreach dep, $(Install_WantedBy), echo start: $(unit) >> $(systemDir)/$(dep).deps;))
	@true
