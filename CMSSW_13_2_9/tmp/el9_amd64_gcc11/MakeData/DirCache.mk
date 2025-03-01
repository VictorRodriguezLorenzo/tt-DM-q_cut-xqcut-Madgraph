ALL_SUBSYSTEMS+=Configuration
subdirs_src_Configuration = src_Configuration_GenProduction
subdirs_src += src_Configuration
ALL_PACKAGES += Configuration/GenProduction
subdirs_src_Configuration_GenProduction := src_Configuration_GenProduction_python
ifeq ($(strip $(PyConfigurationGenProduction)),)
PyConfigurationGenProduction := self/src/Configuration/GenProduction/python
src_Configuration_GenProduction_python_parent := src/Configuration/GenProduction
ALL_PYTHON_DIRS += $(patsubst src/%,%,src/Configuration/GenProduction/python)
PyConfigurationGenProduction_files := $(patsubst src/Configuration/GenProduction/python/%,%,$(wildcard $(foreach dir,src/Configuration/GenProduction/python ,$(foreach ext,$(SRC_FILES_SUFFIXES),$(dir)/*.$(ext)))))
PyConfigurationGenProduction_LOC_USE := self   
PyConfigurationGenProduction_PACKAGE := self/src/Configuration/GenProduction/python
ALL_PRODS += PyConfigurationGenProduction
PyConfigurationGenProduction_INIT_FUNC        += $$(eval $$(call PythonProduct,PyConfigurationGenProduction,src/Configuration/GenProduction/python,src_Configuration_GenProduction_python))
else
$(eval $(call MultipleWarningMsg,PyConfigurationGenProduction,src/Configuration/GenProduction/python))
endif
ALL_COMMONRULES += src_Configuration_GenProduction_python
src_Configuration_GenProduction_python_INIT_FUNC += $$(eval $$(call CommonProductRules,src_Configuration_GenProduction_python,src/Configuration/GenProduction/python,PYTHON))
ALL_SUBSYSTEMS+=logs
subdirs_src_logs = src_logs_ttbarDM__dilepton__DMsimp_LO_ps_spin0__mchi_1_mphi_100_gSM_1_gDM_1_6800GeV_xqcut_10
subdirs_src += src_logs
ALL_PACKAGES += logs/ttbarDM__dilepton__DMsimp_LO_ps_spin0__mchi_1_mphi_100_gSM_1_gDM_1_6800GeV_xqcut_10
subdirs_src_logs_ttbarDM__dilepton__DMsimp_LO_ps_spin0__mchi_1_mphi_100_gSM_1_gDM_1_6800GeV_xqcut_10 := 
