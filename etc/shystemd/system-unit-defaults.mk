SHYSTEMD_PRIVATE_TMP_ROOT =  $(TMPDIR)
SHYSTEMD_PRIVATE_TMP_ROOT ?= $(TMP)
SHYSTEMD_PRIVATE_TMP_ROOT ?= /tmp

# Systemctl defaults
Service_User  			?= nobody
Service_Group 			?= nogroup
Service_Type 			?= $(if $(Service_ExecStart),simple,oneshot)
Service_WorkingDirectory 	?= $(SHYSTEMD_PRIVATE_TMP_ROOT)
Service_KillSignal 		?= TERM
Service_RuntimeDirectoryMode 	?= 0750
Service_RuntimeDirectory     	?= nobody

