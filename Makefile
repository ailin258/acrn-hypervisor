# acrn-hypervisor/Makefile

# global helper variables
T := $(CURDIR)

# $(TARGET_DIR) must be relative path under $(T)
TARGET_DIR ?=

# BOARD/SCENARIO/BOARD_FILE/SCENARIO_FILE/KCONFIG_FILE parameters sanity check:
#
# Only below usages are VALID: (target = all | hypervisor)
# 1. make <target>
# 2. make <target> KCONFIG_FILE=xxx [TARGET_DIR=xxx]
# 3. make <target> BOARD=xxx SCENARIO=xxx [TARGET_DIR=xxx]
# 4. make <target> BOARD_FILE=xxx SCENARIO_FILE=xxx [TARGET_DIR=xxx]
#
# Especially for case 1 that no any parameters are specified:
#    a. If hypervisor/build/.config file which generated by "make menuconfig" exist,
#       the .config file will be loaded as KCONFIG_FILE:
#       i.e. equal: make <target> KCONFIG_FILE=hypervisor/build/.config
#
#    b. If hypervisor/build/.config file does not exist,
#       the default BOARD/SCENARIO will be loaded:
#       i.e. equal: make <target> BOARD=$(BOARD) SCENARIO=$(SCENARIO)
#
# For case 2/3, configurations are imported from TARGET_DIR when TARGET_DIR is specified;
# For case 4, configurations are from XML files and saved to TARGET_DIR if it is specified;
#
# The grep process did not handle corner case when '#' is manually put right after config value as comments,
# i.e. it will be failed in the case of "CONFIG_XXX=y # some comments here "

ifneq ($(KCONFIG_FILE),)
  ifneq ($(KCONFIG_FILE), $(wildcard $(KCONFIG_FILE)))
    $(error KCONFIG_FILE: $(KCONFIG_FILE) does not exist)
  endif
  override KCONFIG_FILE := $(realpath $(KCONFIG_FILE))
else
  override KCONFIG_FILE := $(T)/hypervisor/build/.config
endif

ifneq ($(BOARD)$(SCENARIO),)
  ifneq ($(BOARD_FILE)$(SCENARIO_FILE),)
    $(error BOARD/SCENARIO parameter could not coexist with BOARD_FILE/SCENARIO_FILE)
  endif
endif

ifeq ($(BOARD_FILE)$(SCENARIO_FILE),)
  ifneq ($(TARGET_DIR),)
    ifneq ($(TARGET_DIR), $(wildcard $(TARGET_DIR)))
      $(error TARGET_DIR $(TARGET_DIR) does not exist)
    endif
  endif
endif

ifneq ($(BOARD_FILE)$(SCENARIO_FILE),)
  ifneq ($(BOARD_FILE), $(wildcard $(BOARD_FILE)))
    $(error BOARD_FILE: $(BOARD_FILE) does not exist)
  endif
  ifneq ($(SCENARIO_FILE), $(wildcard $(SCENARIO_FILE)))
    $(error SCENARIO_FILE: $(SCENARIO_FILE) does not exist)
  endif

  override BOARD_FILE := $(realpath $(BOARD_FILE))
  override SCENARIO_FILE := $(realpath $(SCENARIO_FILE))
endif

ifeq ($(KCONFIG_FILE), $(wildcard $(KCONFIG_FILE)))
  ifneq ($(BOARD)$(SCENARIO),)
    $(error BOARD/SCENARIO parameter could not coexist with Kconfig file: $(KCONFIG_FILE))
  endif

  ifneq ($(BOARD_FILE)$(SCENARIO_FILE),)
    $(error BOARD_FILE/SCENARIO_FILE parameter could not coexist with Kconfig file: $(KCONFIG_FILE))
  endif

  BOARD_IN_KCONFIG := $(shell grep CONFIG_BOARD= $(KCONFIG_FILE) | grep -v '\#' | awk -F '"' '{print $$2}')
  ifeq ($(BOARD_IN_KCONFIG),)
    $(error no BOARD info in KCONFIG_FILE: $(KCONFIG_FILE))
  endif

  SCENARIO_IN_KCONFIG := $(shell grep CONFIG_SCENARIO= $(KCONFIG_FILE) | grep -v '\#' | awk -F '"' '{print $$2}')
  ifeq ($(SCENARIO_IN_KCONFIG),)
    $(error no SCENARIO info in KCONFIG_FILE: $(KCONFIG_FILE))
  endif

  override BOARD := $(BOARD_IN_KCONFIG)
  override SCENARIO := $(SCENARIO_IN_KCONFIG)

  RELEASE := $(shell grep CONFIG_RELEASE=y $(KCONFIG_FILE) | grep -v '\#')
  ifneq ($(RELEASE),)
    override RELEASE := 1
  endif

endif

BOARD ?= kbl-nuc-i7

ifneq (,$(filter $(BOARD),apl-mrb))
	FIRMWARE ?= sbl
else
	FIRMWARE ?= uefi
endif

SCENARIO ?= sdc

O ?= build
ROOT_OUT := $(shell mkdir -p $(O);cd $(O);pwd)
HV_OUT := $(ROOT_OUT)/hypervisor
EFI_OUT := misc/efi-stub
DM_OUT := $(ROOT_OUT)/devicemodel
TOOLS_OUT := $(ROOT_OUT)/misc/tools
DOC_OUT := $(ROOT_OUT)/doc
BUILD_VERSION ?=
BUILD_TAG ?=
GENED_ACPI_INFO_HEADER = $(T)/hypervisor/arch/x86/configs/$(BOARD)/$(BOARD)_acpi_info.h
HV_CFG_LOG = $(HV_OUT)/cfg.log
DEFAULT_DEFCONFIG_DIR = $(T)/hypervisor/arch/x86/configs

export TOOLS_OUT BOARD SCENARIO FIRMWARE RELEASE

.PHONY: all hypervisor devicemodel tools doc
all: hypervisor devicemodel tools
	@cat $(HV_CFG_LOG)

ifeq ($(BOARD), apl-nuc)
  override BOARD := nuc6cayh
else ifeq ($(BOARD), kbl-nuc-i7)
  override BOARD := nuc7i7dnb
endif

include $(T)/hypervisor/scripts/makefile/cfg_update.mk

#help functions to build acrn and install acrn/acrn symbols
define build_acrn
	$(MAKE) -C $(T)/hypervisor HV_OBJDIR=$(HV_OUT)-$(1)/$(2) BOARD=$(2) FIRMWARE=$(1) SCENARIO=$(3) RELEASE=$(RELEASE) clean
	$(MAKE) -C $(T)/hypervisor HV_OBJDIR=$(HV_OUT)-$(1)/$(2) BOARD=$(2) FIRMWARE=$(1) SCENARIO=$(3) RELEASE=$(RELEASE) defconfig
	$(MAKE) -C $(T)/hypervisor HV_OBJDIR=$(HV_OUT)-$(1)/$(2) BOARD=$(2) FIRMWARE=$(1) SCENARIO=$(3) RELEASE=$(RELEASE) oldconfig
	$(MAKE) -C $(T)/hypervisor HV_OBJDIR=$(HV_OUT)-$(1)/$(2) BOARD=$(2) FIRMWARE=$(1) SCENARIO=$(3) RELEASE=$(RELEASE)
	echo "building hypervisor as EFI executable..."
	@if [ "$(1)" = "uefi" ]; then \
	$(MAKE) -C $(T)/misc/efi-stub HV_OBJDIR=$(HV_OUT)-$(1)/$(2) SCENARIO=$(3) EFI_OBJDIR=$(HV_OUT)-$(1)/$(2)/$(EFI_OUT); \
	fi
endef

define install_acrn
	$(MAKE) -C $(T)/hypervisor HV_OBJDIR=$(HV_OUT)-$(1)/$(2) BOARD=$(2) FIRMWARE=$(1) SCENARIO=$(3) RELEASE=$(RELEASE) install
	@if [ "$(1)" = "uefi" ]; then \
	$(MAKE) -C $(T)/misc/efi-stub HV_OBJDIR=$(HV_OUT)-$(1)/$(2) BOARD=$(2) FIRMWARE=$(1) SCENARIO=$(3) RELEASE=$(RELEASE) EFI_OBJDIR=$(HV_OUT)-$(1)/$(2)/$(EFI_OUT) install; \
	fi
endef

define install_acrn_debug
	$(MAKE) -C $(T)/hypervisor HV_OBJDIR=$(HV_OUT)-$(1)/$(2) BOARD=$(2) FIRMWARE=$(1) SCENARIO=$(3) RELEASE=$(RELEASE) install-debug
	@if [ "$(1)" = "uefi" ]; then \
	$(MAKE) -C $(T)/misc/efi-stub HV_OBJDIR=$(HV_OUT)-$(1)/$(2) BOARD=$(2) FIRMWARE=$(1) SCENARIO=$(3) RELEASE=$(RELEASE) EFI_OBJDIR=$(HV_OUT)-$(1)/$(2)/$(EFI_OUT) install-debug; \
	fi
endef

hypervisor:
	@if [ "$(BOARD_FILE)" != "" ] && [ -f $(BOARD_FILE) ] && [ "$(SCENARIO_FILE)" != "" ] && [ -f $(SCENARIO_FILE) ] && [ "$(TARGET_DIR)" = "" ]; then \
		echo "No TARGET_DIR parameter is specified, the original configuration source is overwritten!";\
	fi
	$(MAKE) -C $(T)/hypervisor HV_OBJDIR=$(HV_OUT) BOARD_FILE=$(BOARD_FILE) SCENARIO_FILE=$(SCENARIO_FILE) clean;
	$(MAKE) -C $(T)/hypervisor HV_OBJDIR=$(HV_OUT) BOARD_FILE=$(BOARD_FILE) SCENARIO_FILE=$(SCENARIO_FILE) TARGET_DIR=$(abspath $(TARGET_DIR)) defconfig;
	$(MAKE) -C $(T)/hypervisor HV_OBJDIR=$(HV_OUT) BOARD_FILE=$(BOARD_FILE) SCENARIO_FILE=$(SCENARIO_FILE) TARGET_DIR=$(abspath $(TARGET_DIR)) oldconfig;
	$(MAKE) -C $(T)/hypervisor HV_OBJDIR=$(HV_OUT) BOARD_FILE=$(BOARD_FILE) SCENARIO_FILE=$(SCENARIO_FILE) TARGET_DIR=$(abspath $(TARGET_DIR))
#ifeq ($(FIRMWARE),uefi)
	@if [ "$(SCENARIO)" != "logical_partition" ] && [ "$(SCENARIO)" != "hybrid" ]; then \
		echo "building hypervisor as EFI executable..."; \
		$(MAKE) -C $(T)/misc/efi-stub HV_OBJDIR=$(HV_OUT) EFI_OBJDIR=$(HV_OUT)/$(EFI_OUT); \
	fi
#endif
	@echo -e "\n\033[47;30mACRN Configuration Summary:\033[0m \nBOARD = $(BOARD)\t SCENARIO = $(SCENARIO)" > $(HV_CFG_LOG); \
	echo -e "BUILD type = \c" >> $(HV_CFG_LOG); \
	if [ "$(RELEASE)" = "0" ]; then echo -e "DEBUG" >> $(HV_CFG_LOG); else echo -e "RELEASE" >> $(HV_CFG_LOG); fi; \
	if [ -f $(KCONFIG_FILE) ]; then \
		echo -e "Hypervisor configuration is based on:\n\tKconfig file:\t$(KCONFIG_FILE);" >> $(HV_CFG_LOG); \
	fi; \
	if [ "$(TARGET_DIR)" = "" ]; then \
		if [ ! -f $(KCONFIG_FILE) ]; then \
			echo -e "Hypervisor configuration is based on:\n\t$(BOARD) " \
				"defconfig file:\t$(DEFAULT_DEFCONFIG_DIR)/$(BOARD).config;" >> $(HV_CFG_LOG); \
		fi; \
	elif [ ! -f $(KCONFIG_FILE) ]; then \
		echo -e "Hypervisor configuration is based on:\n\t$(BOARD) " \
			"defconfig file:\t$(abspath $(TARGET_DIR))/$(BOARD).config;" >> $(HV_CFG_LOG); \
	fi; \
	echo -e "\tOthers are set by default in:\t$(T)/hypervisor/arch/x86/Kconfig;" >> $(HV_CFG_LOG); \
	if [ "$(CONFIG_XML_ENABLED)" = "true" ]; then \
		echo -e "VM configuration is based on:\n\tBOARD File:\t$(BOARD_FILE);" \
			"\n\tSCENARIO File:\t$(SCENARIO_FILE);" >> $(HV_CFG_LOG); \
	else \
		echo "VM configuration is based on current code base;" >> $(HV_CFG_LOG); \
	fi; \
	if [ -f $(GENED_ACPI_INFO_HEADER) ] && [ "$(CONFIG_XML_ENABLED)" != "true" ] && [ "TARGET_DIR" = "" ]; then \
		echo -e "\033[33mWarning: The platform ACPI info is based on acrn-config generated $(GENED_ACPI_INFO_HEADER), please make sure its validity.\033[0m" >> $(HV_CFG_LOG); \
	fi
	@cat $(HV_CFG_LOG)

devicemodel: tools
	$(MAKE) -C $(T)/devicemodel DM_OBJDIR=$(DM_OUT) RELEASE=$(RELEASE) clean
	$(MAKE) -C $(T)/devicemodel DM_OBJDIR=$(DM_OUT) DM_BUILD_VERSION=$(BUILD_VERSION) DM_BUILD_TAG=$(BUILD_TAG) DM_ASL_COMPILER=$(ASL_COMPILER) RELEASE=$(RELEASE)

tools:
	mkdir -p $(TOOLS_OUT)
	$(MAKE) -C $(T)/misc OUT_DIR=$(TOOLS_OUT) RELEASE=$(RELEASE)

doc:
	$(MAKE) -C $(T)/doc html BUILDDIR=$(DOC_OUT)

.PHONY: clean
clean:
	$(MAKE) -C $(T)/misc OUT_DIR=$(TOOLS_OUT) clean
	$(MAKE) -C $(T)/doc BUILDDIR=$(DOC_OUT) clean
	rm -rf $(ROOT_OUT)
	rm -rf $(TARGET_DIR)

.PHONY: install
install: hypervisor-install devicemodel-install tools-install

hypervisor-install:
	$(MAKE) -C $(T)/hypervisor HV_OBJDIR=$(HV_OUT) BOARD=$(BOARD) FIRMWARE=$(FIRMWARE) SCENARIO=$(SCENARIO) RELEASE=$(RELEASE) install
ifeq ($(FIRMWARE),uefi)
	$(MAKE) -C $(T)/misc/efi-stub HV_OBJDIR=$(HV_OUT) BOARD=$(BOARD) FIRMWARE=$(FIRMWARE) SCENARIO=$(SCENARIO) EFI_OBJDIR=$(HV_OUT)/$(EFI_OUT) all install
endif

hypervisor-install-debug:
	$(MAKE) -C $(T)/hypervisor HV_OBJDIR=$(HV_OUT) BOARD=$(BOARD) FIRMWARE=$(FIRMWARE) SCENARIO=$(SCENARIO) RELEASE=$(RELEASE) install-debug
ifeq ($(FIRMWARE),uefi)
	$(MAKE) -C $(T)/misc/efi-stub HV_OBJDIR=$(HV_OUT) BOARD=$(BOARD) FIRMWARE=$(FIRMWARE) SCENARIO=$(SCENARIO) EFI_OBJDIR=$(HV_OUT)/$(EFI_OUT) all install-debug
endif

apl-mrb-sbl-sdc:
	$(call build_acrn,sbl,apl-mrb,sdc)
apl-up2-sbl-sdc:
	$(call build_acrn,sbl,apl-up2,sdc)
kbl-nuc-i7-uefi-industry:
	$(call build_acrn,uefi,nuc7i7dnb,industry)
apl-up2-uefi-hybrid:
	$(call build_acrn,uefi,apl-up2,hybrid)

sbl-hypervisor: apl-mrb-sbl-sdc \
                apl-up2-sbl-sdc \
                kbl-nuc-i7-uefi-industry \
                apl-up2-uefi-hybrid

apl-mrb-sbl-sdc-install:
	$(call install_acrn,sbl,apl-mrb,sdc)
apl-up2-sbl-sdc-install:
	$(call install_acrn,sbl,apl-up2,sdc)
kbl-nuc-i7-uefi-industry-install:
	$(call install_acrn,uefi,nuc7i7dnb,industry)
apl-up2-uefi-hybrid-install:
	$(call install_acrn,uefi,apl-up2,hybrid)

sbl-hypervisor-install: apl-mrb-sbl-sdc-install \
                        apl-up2-sbl-sdc-install \
                        kbl-nuc-i7-uefi-industry-install \
                        apl-up2-uefi-hybrid-install

apl-mrb-sbl-sdc-install-debug:
	$(call install_acrn_debug,sbl,apl-mrb,sdc)
apl-up2-sbl-sdc-install-debug:
	$(call install_acrn_debug,sbl,apl-up2,sdc)
kbl-nuc-i7-uefi-industry-install-debug:
	$(call install_acrn_debug,uefi,nuc7i7dnb,industry)
apl-up2-uefi-hybrid-install-debug:
	$(call install_acrn_debug,uefi,apl-up2,hybrid)

sbl-hypervisor-install-debug: apl-mrb-sbl-sdc-install-debug \
			      apl-up2-sbl-sdc-install-debug \
			      kbl-nuc-i7-uefi-industry-install-debug \
			      apl-up2-uefi-hybrid-install-debug

devicemodel-install:
	$(MAKE) -C $(T)/devicemodel DM_OBJDIR=$(DM_OUT) install

tools-install:
	$(MAKE) -C $(T)/misc OUT_DIR=$(TOOLS_OUT) RELEASE=$(RELEASE) install
