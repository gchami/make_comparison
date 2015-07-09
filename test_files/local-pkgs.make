#-------------------------------------------------------------------------------
#
# Copyright 2012 Cumulus Networks LLC, all rights reserved
#
#-------------------------------------------------------------------------------
#
# This is a makefile fragment that defines the build of various debian
# packages that have been modified.
#


#===============================================================================
#
# user-defined functions common to most packages
#

# Define the variable BLDSRCPKGS to enable building of source pkgs
#
# $ make BLDSRCPKGS=1 all
#
# Building src pkgs prevents one from modifying an existing patch.  So
# only build src pkgs when explicitly requested (such as by CI
# builds).
#
ifeq ($(BLDSRCPKGS),1)
$(info Building source packages too ...)
DPKG_BUILDPKG_CMD=-sa
PATCH_QUILT=--quilt
copytar= cp -a $(PACKAGESDIR_COMMON)/$(1)_$(2).orig.tar.* $(PACKAGESDIR)
else
DPKG_BUILDPKG_CMD=-b
PATCH_QUILT=
copytar=
endif

# getsrc function
# Args: <pkg-name>,<pkg-version>
#

getsrc_fnc = echo "==== getsrc start for $(1)" ;  \
		cd $(PACKAGESDIR_COMMON) && $(SCRIPTDIR)/aptsnap getsource \
		 $(SNAPBUILDDIR_COMMON) $(1)=$(2) && \
		echo "==== getsrc end for $(1) ===="

# patch function
# Args: <pkg-name>,<pkg-dir>,<pkg-vers>
#
patch_fnc = echo "==== patch_fnc start for $(1) ====" && \
		$(SCRIPTDIR)/apply-patch-series $(PATCHDIR)/$(1)/series \
		$(2) $(STGIT) $(PATCH_QUILT) && \
		(cd $(2) && debchange -v $(3) -D $(DISTRO_NAME) \
		    --force-distribution "Cumulus Networks patches") &&\
		echo "==== patch_fnc end for $(1) ===="

# build_fnc:
# Args: <dir>,<build command>
# deb_build_fnc:
# Args: <pkg-dir>,<ENV>
#


ifeq ($(CARCH),$(filter $(CARCH),powerpc arm))
build_fnc = echo "==== build_fnc start in $(1) ====" ; \
	cd $(1) && sb2 -M $(SB2MAPPING) -t $(SB2_TARGET) $(2) &&\
	echo "==== build_fnc end in $(1) ===="
else ifeq ($(CARCH), amd64)
build_fnc = cd $(1) && \
	sb2 -M $(SB2MAPPING) -t $(SB2_TARGET) \
	C_INCLUDE_PATH=$(SYSROOTDIR)/usr/include \
	LIBRARY_PATH=$(SYSROOTDIR)/usr/lib:$(SYSROOTDIR)/lib \
	PKG_CONFIG_PATH=$(SYSROOTDIR)/usr/lib/pkgconfig $(2) && \
	 echo "==== build_fnc end in $(1) ===="

else
  $(error Unsupported CARCH: $(CARCH))
endif

deb_build_fnc = $(call build_fnc, $(1), \
		$(2) MAKEFLAGS= dpkg-buildpackage -d $(DPKG_BUILDPKG_CMD) \
		-uc -us) &&\
	 echo "==== deb_build_fnc end in $(1) ===="

# build function with no source pkg
# TEMPORARY until all pkgs ready to be a source pkg
# Args: <pkg-dir>,<ENV>
#
ifeq ($(CARCH), powerpc)
deb_build_fnc_nosource = cd $(1) && sb2 -M $(SB2MAPPING) -t $(SB2_TARGET) \
		$(2) MAKEFLAGS= dpkg-buildpackage -d -b -uc -us

else ifeq ($(CARCH), amd64)
deb_build_fnc_nosource = cd $(1) && \
	C_INCLUDE_PATH=$(SYSROOTDIR)/usr/include \
	LIBRARY_PATH=$(SYSROOTDIR)/usr/lib:$(SYSROOTDIR)/lib \
	PKG_CONFIG_PATH=$(SYSROOTDIR)/usr/lib/pkgconfig \
	MAKEFLAGS=  $(2) \
	dpkg-buildpackage -d -b -uc -us
else
  $(error Unsupported CARCH: $(CARCH))
endif

# patch function without quilting Cumulus patches
# Also TEMPORARY
# Args: <pkg-name>,<pkg-dir>,<pkg-vers>
#
patch_fnc_noquilt = (cd $(2) && debchange -v $(3) -D $(DISTRO_NAME) \
	--force-distribution "Cumulus Networks patches") && \
	$(SCRIPTDIR)/apply-patch-series $(PATCHDIR)/$(1)/series \
		$(2) $(STGIT)

# exclude hidden directories (e.g. .git) from copying. If any
# hidden files are needed for building, they must be included
# explicitly.
copybuilddir = rm -rf $(2); mkdir -p $(2); \
	       cp -a $(PACKAGESDIR_COMMON)/$(1)-$(3)/* $(2);

#------------------------------------------------------------------------------
#
# scratchbox2 configuration
#
ifeq ($(CARCH),$(filter $(CARCH),powerpc amd64))
SB2_TARGET = $(shell echo $(BUILDDIR) | md5sum | cut -c1-16)
SB2DIR     = $(abspath ${HOME}/.scratchbox2/$(SB2_TARGET))
SB2MAPPING = $(abspath ./conf/sb2_build.lua)
else
  $(error Unsupported CARCH: $(CARCH))
endif

SB2_STAMP  = $(STAMPDIR)/sb2-install

PHONY      += sb2 sb2-clean

#---

sb2: $(SB2_STAMP)
$(SB2_STAMP): $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Initializing scratchbox2 for $(SYSROOTDIR) ===="
ifeq ($(CARCH), powerpc)
	@ cd $(SYSROOTDIR) && \
		sb2-init -n -A ppc -c /usr/bin/qemu-ppc \
			$(SB2_TARGET) $(CROSSBIN)/powerpc-gcc
	#
	# Some versions of wheezy /usr/share/scratchbox2/scripts/sb2-config-debian fails
	# to create the correct debian conf file because it calls dpkg-architecture with
	# arch ppc and dpkg-architecture does not understand it.
	# sb2-config-debian can be fixed by mapping ppc to DEBIAN_CPU powerpc.
	# This is a build machine change.
	# For now, copy our version of debian.conf
	@ cp -f ./conf/sb2-debian.conf.powerpc ~/.scratchbox2/$(SB2_TARGET)/sb2.config.d/debian.conf
else ifeq ($(CARCH), amd64)
	@ cd $(SYSROOTDIR) && \
		sb2-init -n -A x86_64 $(SB2_TARGET) /usr/bin/gcc
	@ cp -f ./conf/sb2-debian.conf.amd64 ~/.scratchbox2/$(SB2_TARGET)/sb2.config.d/debian.conf
endif
	@ touch $@

# FIXME:  Need to understand why the first version doesn't work!!!
#	sb2-init -n -A ppc -c $(TOOLROOT)/bin/qemu-ppc .....
#	sb2-init -n -A ppc -c /usr/bin/qemu-ppc .....

#---

CLEAN += sb2-clean
sb2-clean:
	rm -rf $(SB2DIR)
	rm -vf $(SB2_STAMP)

#-------------------------------------------------------------------------------
#
# logrotate
#
#---
LOGROTATE_VERSION		= 3.8.1
LOGROTATE_DEBIAN_VERSION	= $(LOGROTATE_VERSION)-4
LOGROTATE_CUMULUS_VERSION	= $(LOGROTATE_DEBIAN_VERSION)+cl2.5
LOGROTATEDIR		= $(PACKAGESDIR)/logrotate-$(LOGROTATE_VERSION)
LOGROTATEDIR_COMMON		= $(PACKAGESDIR_COMMON)/logrotate-$(LOGROTATE_VERSION)

LOGROTATE_SOURCE_STAMP	= $(STAMPDIR_COMMON)/logrotate-source
LOGROTATE_PATCH_STAMP	= $(STAMPDIR_COMMON)/logrotate-patch
LOGROTATE_BUILD_STAMP	= $(STAMPDIR)/logrotate-build
LOGROTATE_STAMP		= $(LOGROTATE_SOURCE_STAMP) \
			  $(LOGROTATE_PATCH_STAMP) \
			  $(LOGROTATE_BUILD_STAMP)

LOGROTATE_DEB		= $(PACKAGESDIR)/logrotate_$(LOGROTATE_CUMULUS_VERSION)_$(CARCH).deb

PHONY += logrotate logrotate-source logrotate-patch logrotate-build logrotate-clean logrotate-common-clean

#---

PACKAGES1 += $(LOGROTATE_STAMP)
logrotate: $(LOGROTATE_STAMP)

#---

SOURCE += $(LOGROTATE_PATCH_STAMP)

logrotate-source: $(LOGROTATE_SOURCE_STAMP)
$(LOGROTATE_SOURCE_STAMP): $(PATCHDIR)/logrotate/* $(TREE_STAMP_COMMON)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting and building logrotate ===="
	@ rm -rf $(PACKAGESDIR)/logrotate-* $(PACKAGESDIR)/logrotate_*
	$(call getsrc_fnc,logrotate,$(LOGROTATE_DEBIAN_VERSION))
	@ touch $@

#---

logrotate-patch: $(LOGROTATE_PATCH_STAMP)
$(LOGROTATE_PATCH_STAMP): $(LOGROTATE_SOURCE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Patching $(LOGROTATEDIR) ===="
	$(call patch_fnc,logrotate,$(LOGROTATEDIR_COMMON),$(LOGROTATE_CUMULUS_VERSION))
	@ touch $@

#---

logrotate-build: $(LOGROTATE_BUILD_STAMP)
$(LOGROTATE_BUILD_STAMP): $(SB2_STAMP) $(LOGROTATE_PATCH_STAMP) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building logrotate-$(LOGROTATE_VERSION) ===="
	$(call copybuilddir,logrotate,$(LOGROTATEDIR),$(LOGROTATE_VERSION))
	$(call copytar,logrotate,$(LOGROTATE_VERSION))
	$(call deb_build_fnc,$(LOGROTATEDIR))
	@ touch $@

#---

PACKAGES1_INSTALL_DEBS += $(LOGROTATE_DEB)

PACKAGES_COMMON_CLEAN += logrotate-common-clean
PACKAGES_CLEAN += logrotate-clean

logrotate-clean:
	rm -rf $(PACKAGESDIR)/logrotate*
	@ rm -rf $(LOGROTATE_DEB)
	@ rm -vf $(LOGROTATE_BUILD_STAMP)

logrotate-common-clean:
	rm -rf $(PACKAGESDIR)/logrotate*
	rm -rf $(PACKAGESDIR_COMMON)/logrotate*
	@ rm -vf $(LOGROTATE_DEB)
	@ rm -vf $(LOGROTATE_STAMP)

#-------------------------------------------------------------------------------
#
# i2ctools
#
#---
I2CTOOLS_VERSION		= 3.1.0
I2CTOOLS_DEBIAN_VERSION	= $(I2CTOOLS_VERSION)-2
I2CTOOLS_CUMULUS_VERSION	= $(I2CTOOLS_DEBIAN_VERSION)+cl2.1
I2CTOOLSDIR		= $(PACKAGESDIR)/i2c-tools-$(I2CTOOLS_VERSION)
I2CTOOLSDIR_COMMON      = $(PACKAGESDIR_COMMON)/i2c-tools-$(I2CTOOLS_VERSION)

I2CTOOLS_SOURCE_STAMP	= $(STAMPDIR_COMMON)/i2c-tools-source
I2CTOOLS_PATCH_STAMP	= $(STAMPDIR_COMMON)/i2c-tools-patch
I2CTOOLS_BUILD_STAMP	= $(STAMPDIR)/i2c-tools-build
I2CTOOLS_STAMP		= $(I2CTOOLS_SOURCE_STAMP) \
			  $(I2CTOOLS_PATCH_STAMP) \
			  $(I2CTOOLS_BUILD_STAMP)

I2CTOOLS_DEB		= $(PACKAGESDIR)/i2c-tools_$(I2CTOOLS_CUMULUS_VERSION)_$(CARCH).deb

PHONY += i2ctools i2ctools-source i2ctools-patch i2ctools-build i2ctools-clean i2ctools-common-clean

#---

PACKAGES1 += $(I2CTOOLS_STAMP)
i2ctools: $(I2CTOOLS_STAMP)

#---

SOURCE += $(I2CTOOLS_PATCH_STAMP)

i2ctools-source: $(I2CTOOLS_SOURCE_STAMP)
$(I2CTOOLS_SOURCE_STAMP): $(PATCHDIR)/i2c-tools/* $(TREE_STAMP_COMMON)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting and building i2ctools ===="
	@ rm -rf $(PACKAGESDIR_COMMON)/i2c-tools-* $(PACKAGESDIR_COMMON)/i2c-tools_*
	$(call getsrc_fnc,i2c-tools,$(I2CTOOLS_DEBIAN_VERSION))
	@ touch $@

#---

i2ctools-patch: $(I2CTOOLS_PATCH_STAMP)
$(I2CTOOLS_PATCH_STAMP): $(PATCHDIR)/i2c-tools/* $(I2CTOOLS_SOURCE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Patching $(I2CTOOLSDIR) ===="
	$(call patch_fnc,i2c-tools,$(I2CTOOLSDIR_COMMON),$(I2CTOOLS_CUMULUS_VERSION))
	@ touch $@

#---

i2ctools-build: $(I2CTOOLS_BUILD_STAMP)
$(I2CTOOLS_BUILD_STAMP): $(SB2_STAMP) $(I2CTOOLS_PATCH_STAMP) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building i2ctools-$(I2CTOOLS_VERSION) ===="
	$(call copybuilddir,i2c-tools,$(I2CTOOLSDIR),$(I2CTOOLS_VERSION))
	$(call copytar,i2c-tools,$(I2CTOOLS_VERSION))
	$(call deb_build_fnc,$(I2CTOOLSDIR))
	@ touch $@

#---

PACKAGES1_INSTALL_DEBS += $(I2CTOOLS_DEB)

PACKAGES_CLEAN += i2ctools-clean
PACKAGES_COMMON_CLEAN += i2ctools-common-clean

i2ctools-clean:
	rm -rf $(PACKAGESDIR)/i2c-tools*
	@ rm -rf $(I2CTOOLS_DEB)
	@ rm -vf $(I2CTOOLS_STAMP)

i2ctools-common-clean:
	@ rm -rf {$(PACKAGESDIR_COMMON),$(PACKAGESDIR)}/i2c-tools[_-]$(i2ctools_version)*
	@ rm -vf $(I2CTOOLS_STAMP)

#-------------------------------------------------------------------------------
#
# iproute
#
#---
IPROUTE_VERSION		= 20120521
IPROUTE_DEBIAN_VERSION	= $(IPROUTE_VERSION)-3
IPROUTE_CUMULUS_VERSION	= $(IPROUTE_DEBIAN_VERSION)+cl2.5+3
IPROUTEDIR		= $(PACKAGESDIR)/iproute-$(IPROUTE_VERSION)
IPROUTEDIR_COMMON	= $(PACKAGESDIR_COMMON)/iproute-$(IPROUTE_VERSION)

IPROUTE_SOURCE_STAMP	= $(STAMPDIR_COMMON)/iproute-source
IPROUTE_PATCH_STAMP	= $(STAMPDIR_COMMON)/iproute-patch
IPROUTE_BUILD_STAMP	= $(STAMPDIR)/iproute-build
IPROUTE_STAMP		= $(IPROUTE_SOURCE_STAMP) \
			  $(IPROUTE_PATCH_STAMP) \
			  $(IPROUTE_BUILD_STAMP)

IPROUTE_DEB		= $(PACKAGESDIR)/iproute_$(IPROUTE_CUMULUS_VERSION)_$(CARCH).deb

PHONY += iproute iproute-source iproute-patch iproute-build iproute-clean iproute-common-clean

#---

PACKAGES1 += $(IPROUTE_STAMP)
iproute: $(IPROUTE_STAMP)

#---

SOURCE += $(IPROUTE_PATCH_STAMP)

iproute-source: $(IPROUTE_SOURCE_STAMP)
$(IPROUTE_SOURCE_STAMP): $(PATCHDIR)/iproute/* $(TREE_STAMP_COMMON)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting and building iproute ===="
	@ rm -rf $(PACKAGESDIR_COMMON)/iproute-* $(PACKAGESDIR_COMMON)/iproute_*
	$(call getsrc_fnc,iproute,$(IPROUTE_DEBIAN_VERSION))
	@ touch $@

#---

iproute-patch: $(IPROUTE_PATCH_STAMP)
$(IPROUTE_PATCH_STAMP): $(IPROUTE_SOURCE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Patching $(IPROUTEDIR) ===="
	$(call patch_fnc,iproute,$(IPROUTEDIR_COMMON),$(IPROUTE_CUMULUS_VERSION))
	@ touch $@

#---

iproute-build: $(IPROUTE_BUILD_STAMP)
$(IPROUTE_BUILD_STAMP): $(SB2_STAMP) $(IPROUTE_PATCH_STAMP) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building iproute-$(IPROUTE_VERSION) ===="
	$(call copybuilddir,iproute,$(IPROUTEDIR),$(IPROUTE_VERSION))
	$(call copytar,iproute,$(IPROUTE_VERSION))
	$(call deb_build_fnc,$(IPROUTEDIR))
	@ touch $@

#---

PACKAGES1_INSTALL_DEBS += $(IPROUTE_DEB)

#---

PACKAGES_CLEAN += iproute-clean
PACKAGES_COMMON_CLEAN += iproute-common-clean

iproute-clean:
	@ rm -rf $(PACKAGESDIR)/iproute[_-]$(iproute_version)*
	@ rm -vf $(IPROUTE_BUILD_STAMP)

iproute-common-clean:
	@ rm -rf {$(PACKAGESDIR_COMMON),$(PACKAGESDIR)}/iproute[_-]$(iproute_version)*
	@ rm -vf $(IPROUTE_STAMP)

#
#-------------------------------------------------------------------------------
#
# libnl3
#

LIBNL_VERSION		= 3.2.7
LIBNL_DEBIAN_VERSION	= $(LIBNL_VERSION)-4
LIBNL_CUMULUS_VERSION	= $(LIBNL_DEBIAN_VERSION)+cl2.5+3
LIBNLDIR		= $(PACKAGESDIR)/libnl3-$(LIBNL_VERSION)
LIBNLDIR_COMMON		= $(PACKAGESDIR_COMMON)/libnl3-$(LIBNL_VERSION)

LIBNL_SOURCE_STAMP	= $(STAMPDIR_COMMON)/libnl-source
LIBNL_PATCH_STAMP	= $(STAMPDIR_COMMON)/libnl-patch
LIBNL_BUILD_STAMP	= $(STAMPDIR)/libnl-build
LIBNL_INSTALL_STAMP = $(STAMPDIR)/libnl-install
LIBNL_STAMP		= $(LIBNL_SOURCE_STAMP) \
			  $(LIBNL_PATCH_STAMP) \
			  $(LIBNL_BUILD_STAMP)


LIBNL_DEB	= $(PACKAGESDIR)/libnl-3-200_$(LIBNL_CUMULUS_VERSION)_$(CARCH).deb
LIBNL_DEV_DEB	= $(PACKAGESDIR)/libnl-3-dev_$(LIBNL_CUMULUS_VERSION)_$(CARCH).deb
LIBNL_CLI_DEB   = $(PACKAGESDIR)/libnl-cli-3-200_$(LIBNL_CUMULUS_VERSION)_$(CARCH).deb
LIBNL_CLI_DEV_DEB	= $(PACKAGESDIR)/libnl-cli-3-dev_$(LIBNL_CUMULUS_VERSION)_$(CARCH).deb
LIBNL_GENL_DEB  = $(PACKAGESDIR)/libnl-genl-3-200_$(LIBNL_CUMULUS_VERSION)_$(CARCH).deb
LIBNL_GENL_DEV_DEB	= $(PACKAGESDIR)/libnl-genl-3-dev_$(LIBNL_CUMULUS_VERSION)_$(CARCH).deb
LIBNL_RT_DEB    = $(PACKAGESDIR)/libnl-route-3-200_$(LIBNL_CUMULUS_VERSION)_$(CARCH).deb
LIBNL_RT_DEV_DEB	= $(PACKAGESDIR)/libnl-route-3-dev_$(LIBNL_CUMULUS_VERSION)_$(CARCH).deb
LIBNL_NF_DEB    = $(PACKAGESDIR)/libnl-nf-3-200_$(LIBNL_CUMULUS_VERSION)_$(CARCH).deb
LIBNL_NF_DEV_DEB	= $(PACKAGESDIR)/libnl-nf-3-dev_$(LIBNL_CUMULUS_VERSION)_$(CARCH).deb
LIBNL_UTL_DEB   = $(PACKAGESDIR)/libnl-utils_$(LIBNL_CUMULUS_VERSION)_$(CARCH).deb

PHONY += libnl libnl-source libnl-patch libnl-build libnl-clean libnl-common-clean

#---

PACKAGES1 += $(LIBNL_STAMP)
libnl: $(LIBNL_STAMP)

#---

SOURCE += $(LIBNL_PATCH_STAMP)

libnl-source: $(LIBNL_SOURCE_STAMP)
$(LIBNL_SOURCE_STAMP): $(PATCHDIR)/libnl/* $(TREE_STAMP_COMMON)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting and building libnl ===="
	@ rm -rf $(PACKAGESDIR_COMMON)/libnl-* $(PACKAGESDIR_COMMON)/libnl_*
	$(call getsrc_fnc,libnl3,$(LIBNL_DEBIAN_VERSION))
	@ touch $@

#---

libnl-patch: $(LIBNL_PATCH_STAMP)
$(LIBNL_PATCH_STAMP): $(LIBNL_SOURCE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Patching $(LIBNLDIR) ===="
	$(call patch_fnc,libnl,$(LIBNLDIR_COMMON),$(LIBNL_CUMULUS_VERSION))
	@ touch $@

#---
ifndef MAKE_CLEAN
LIBNL_NEW_FILES = $(shell test -d $(LIBNLDIR_COMMON) && test -f $(LIBNL_BUILD_STAMP) && \
				  find -L $(LIBNLDIR_COMMON) -mindepth 1 -newer $(LIBNL_BUILD_STAMP) \
			-type f -print -quit 2> /dev/null)
endif

libnl-build: $(LIBNL_BUILD_STAMP)
$(LIBNL_BUILD_STAMP): $(LIBNL_NEW_FILES) $(SB2_STAMP) $(LIBNL_PATCH_STAMP) \
			$(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building libnl-$(LIBNL_VERSION) ===="
	$(call copybuilddir,libnl3,$(LIBNLDIR),$(LIBNL_VERSION))
	$(call copytar,libnl3,$(LIBNL_VERSION))
	$(call deb_build_fnc,$(LIBNLDIR))
	@ touch $@

#---

LIBNL_INSTALL_DEBS = $(LIBNL_DEB) $(LIBNL_DEV_DEB) $(LIBNL_RT_DEB) \
	$(LIBNL_RT_DEV_DEB) $(LIBNL_GENL_DEB) $(LIBNL_GENL_DEV_DEB)

PACKAGES1_INSTALL_DEBS += $(LIBNL_INSTALL_DEBS)
#---

libnl-install: $(LIBNL_INSTALL_STAMP)
$(LIBNL_INSTALL_STAMP): $(LIBNL_BUILD_STAMP) $(BASEINIT_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Unpack packages in $(SYSROOTDIR) ===="
	cd $(PACKAGESDIR) && \
		sudo $(SCRIPTDIR)/dpkg-unpack --force \
		--aptconf=$(BUILDDIR)/apt.conf $(LIBNL_INSTALL_DEBS)
	@ touch $@

#---

PACKAGES_CLEAN += libnl-clean
PACKAGES_COMMON_CLEAN += libnl-common-clean
libnl-clean:
	rm -rf $(PACKAGESDIR)/libnl3[_-]$(libnl_version)*
	@ rm -vf $(LIBNL_BUILD_STAMP)

libnl-common-clean:
	rm -rf {$(PACKAGESDIR),$(PACKAGESDIR_COMMON)}/libnl3[_-]$(libnl_version)*
	@ rm -vf $(LIBNL_STAMP)

#-------------------------------------------------------------------------------
#
# isc-dhcp
#

ISC_DHCP_VERSION	    = 4.2.2.dfsg.1
ISC_DHCP_DEBIAN_VERSION	    = $(ISC_DHCP_VERSION)-5+deb70u6
ISC_DHCP_CUMULUS_VERSION    = $(ISC_DHCP_DEBIAN_VERSION)+cl2+1
ISC_DHCP_DIR		    = $(PACKAGESDIR)/isc-dhcp-$(ISC_DHCP_VERSION)
ISC_DHCP_DIR_COMMON	    = $(PACKAGESDIR_COMMON)/isc-dhcp-$(ISC_DHCP_VERSION)

ISC_DHCP_SOURCE_STAMP	    = $(STAMPDIR_COMMON)/isc-dhcp-source
ISC_DHCP_PATCH_STAMP	    = $(STAMPDIR_COMMON)/isc-dhcp-patch
ISC_DHCP_BUILD_STAMP	    = $(STAMPDIR)/isc-dhcp-build
ISC_DHCP_STAMP		    = $(ISC_DHCP_SOURCE_STAMP) \
				  $(ISC_DHCP_PATCH_STAMP) \
				  $(ISC_DHCP_BUILD_STAMP)

ISC_DHCP_PKGS		    = isc-dhcp-common \
				  isc-dhcp-client \
				  isc-dhcp-relay \
				  isc-dhcp-server

ISC_DHCP_DEBS		    = $(addsuffix _$(ISC_DHCP_CUMULUS_VERSION)_$(CARCH).deb, \
				$(ISC_DHCP_PKGS))

PHONY += isc-dhcp isc-dhcp-source isc-dhcp-patch isc-dhcp-build isc-dhcp-clean isc-dhcp-common-clean

#---

PACKAGES1 += $(ISC_DHCP_STAMP)
isc-dhcp: $(ISC_DHCP_STAMP)

#---

SOURCE += $(ISC_DHCP_PATCH_STAMP)

isc-dhcp-source: $(ISC_DHCP_SOURCE_STAMP)
$(ISC_DHCP_SOURCE_STAMP): $(PATCHDIR)/isc-dhcp/* $(TREE_STAMP_COMMON)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting isc-dhcp ===="
	@ rm -rf $(PACKAGESDIR_COMMON)/isc-dhcp[-_]*
	$(call getsrc_fnc,isc-dhcp,$(ISC_DHCP_DEBIAN_VERSION))
	@ touch $@

#---

isc-dhcp-patch: $(ISC_DHCP_PATCH_STAMP)
$(ISC_DHCP_PATCH_STAMP): $(ISC_DHCP_SOURCE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Patching isc-dhcp ===="
	$(call patch_fnc,isc-dhcp,$(ISC_DHCP_DIR_COMMON),$(ISC_DHCP_CUMULUS_VERSION))
	@ touch $@

#---
ifndef MAKE_CLEAN
ISC_DHCP_NEW_FILES = $(shell test -d $(ISC_DHCP_DIR_COMMON) && test -f $(ISC_DHCP_BUILD_STAMP) && \
				  find -L $(ISC_DHCP_DIR_COMMON) -mindepth 1 -newer $(ISC_DHCP_BUILD_STAMP) \
			-type f -print -quit )
endif

isc-dhcp-build: $(ISC_DHCP_BUILD_STAMP)
$(ISC_DHCP_BUILD_STAMP): $(ISC_DHCP_NEW_FILES) $(SB2_STAMP) \
		$(ISC_DHCP_PATCH_STAMP) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building isc-dhcp ===="
	$(call copybuilddir,isc-dhcp,$(ISC_DHCP_DIR),$(ISC_DHCP_VERSION))
	$(call copytar,isc-dhcp,$(ISC_DHCP_VERSION))
	$(call deb_build_fnc,$(ISC_DHCP_DIR))
	@ touch $@

#---

PACKAGES1_INSTALL_DEBS += $(ISC_DHCP_DEBS)

#---

PACKAGES_CLEAN += isc-dhcp-clean
PACKAGES_COMMON_CLEAN += isc-dhcp-common-clean
isc-dhcp-clean:
	@ rm -rf $(ISC_DHCP_DIR) $(addprefix $(PACKAGESDIR)/, $(ISC_DHCP_DEBS))
	@ rm -vf $(ISC_DHCP_BUILD_STAMP)

isc-dhcp-common-clean:
	@ rm -rf $(ISC_DHCP_DIR_COMMON) $(addprefix {$(PACKAGESDIR),$(PACKAGESDIR_COMMON)}/, $(ISC_DHCP_DEBS))
	@ rm -vf $(ISC_DHCP_STAMP)

#
#-------------------------------------------------------------------------------
#
# net-snmp
#

NET_SNMP_VERSION		= 5.4.3~dfsg
NET_SNMP_DEBIAN_EPOCH		=
NET_SNMP_DEBIAN_BUILD		= $(NET_SNMP_VERSION)-2.7
NET_SNMP_DEBIAN_VERSION		= $(NET_SNMP_DEBIAN_EPOCH)$(NET_SNMP_DEBIAN_BUILD)
NET_SNMP_CUMULUS_VERSION	= $(NET_SNMP_DEBIAN_BUILD)+cl2.5+1
NET_SNMP_DIR			= $(PACKAGESDIR)/net-snmp-$(NET_SNMP_VERSION)
NET_SNMP_DIR_COMMON		= $(PACKAGESDIR_COMMON)/net-snmp-$(NET_SNMP_VERSION)

NET_SNMP_SOURCE_STAMP	= $(STAMPDIR_COMMON)/net-snmp-source
NET_SNMP_PATCH_STAMP	= $(STAMPDIR_COMMON)/net-snmp-patch
NET_SNMP_BUILD_STAMP	= $(STAMPDIR)/net-snmp-build
NET_SNMP_STAMP		= $(NET_SNMP_SOURCE_STAMP) \
			  $(NET_SNMP_PATCH_STAMP) \
			  $(NET_SNMP_BUILD_STAMP)

NET_SNMP_DEBS		= $(PACKAGESDIR)/libsnmp-base_$(NET_SNMP_CUMULUS_VERSION)_all.deb \
			  $(PACKAGESDIR)/libsnmp15_$(NET_SNMP_CUMULUS_VERSION)_$(CARCH).deb \
			  $(PACKAGESDIR)/libsnmp-perl_$(NET_SNMP_CUMULUS_VERSION)_$(CARCH).deb \
			  $(PACKAGESDIR)/libsnmp-dev_$(NET_SNMP_CUMULUS_VERSION)_$(CARCH).deb \
			  $(PACKAGESDIR)/snmpd_$(NET_SNMP_CUMULUS_VERSION)_$(CARCH).deb

PHONY += net-snmp net-snmp-source net-snmp-patch net-snmp-build net-snmp-clean net-snmp-common-clean

#---

PACKAGES1 += $(NET_SNMP_STAMP)
net-snmp: $(NET_SNMP_STAMP)

#---

SOURCE += $(NET_SNMP_PATCH_STAMP)

net-snmp-source: $(NET_SNMP_SOURCE_STAMP)
$(NET_SNMP_SOURCE_STAMP): $(PATCHDIR)/net-snmp/* $(TREE_STAMP_COMMON)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting and building net-snmp-$(NET_SNMP_VERSION) ===="
	@ rm -rf $(PACKAGESDIR_COMMON)/*snmp* $(PACKAGESDIR_COMMON)/tkmib*
	$(call getsrc_fnc,net-snmp,$(NET_SNMP_DEBIAN_VERSION))
	@ touch $@

net-snmp-patch: $(NET_SNMP_PATCH_STAMP)
$(NET_SNMP_PATCH_STAMP): $(NET_SNMP_SOURCE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Patching $(NET_SNMP_DIR) ===="
	$(call patch_fnc,net-snmp,$(NET_SNMP_DIR_COMMON),$(NET_SNMP_CUMULUS_VERSION))
	@ touch $@

net-snmp-build: $(NET_SNMP_BUILD_STAMP)
$(NET_SNMP_BUILD_STAMP): $(SB2_STAMP) $(NET_SNMP_PATCH_STAMP) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building net-snmp-$(NET_SNMP_VERSION) ===="
	$(call copybuilddir,net-snmp,$(NET_SNMP_DIR),$(NET_SNMP_VERSION))
	$(call copytar,net-snmp,$(NET_SNMP_VERSION))
	$(call deb_build_fnc,$(NET_SNMP_DIR))
	@ touch $@

PACKAGES1_INSTALL_DEBS += $(NET_SNMP_DEBS)

PACKAGES_CLEAN += net-snmp-clean
PACKAGES_COMMON_CLEAN += net-snmp-common-clean

net-snmp-clean:
	@ rm -rf $(PACKAGESDIR)/*snmp* $(PACKAGESDIR)/tkmib*
	@ rm -vf $(NET_SNMP_BUILD_STAMP)

net-snmp-common-clean:
	@ rm -rf {$(PACKAGESDIR_COMMON),$(PACKAGESDIR)}/*snmp* {$(PACKAGESDIR_COMMON),$(PACKAGESDIR)}/tkmib*
	@ rm -vf $(NET_SNMP_STAMP)
#-------------------------------------------------------------------------------
#
# quagga
#
QUAGGA_VERSION		= 0.99.23.1
QUAGGA_DEBIAN_VERSION	= $(QUAGGA_VERSION)-1
QUAGGA_CUMULUS_VERSION	= $(QUAGGA_DEBIAN_VERSION)+cl2.5+6
QUAGGADIR		= $(PACKAGESDIR)/quagga-$(QUAGGA_VERSION)
QUAGGADIR_COMMON	= $(PACKAGESDIR_COMMON)/quagga-$(QUAGGA_VERSION)

QUAGGA_SOURCE_STAMP	= $(STAMPDIR_COMMON)/quagga-source
QUAGGA_PATCH_STAMP	= $(STAMPDIR_COMMON)/quagga-patch
QUAGGA_BUILD_STAMP	= $(STAMPDIR)/quagga-build
QUAGGA_STAMP		= $(QUAGGA_SOURCE_STAMP) \
			  $(QUAGGA_PATCH_STAMP) \
			  $(QUAGGA_BUILD_STAMP)

QUAGGA_DEB		= $(PACKAGESDIR)/quagga_$(QUAGGA_CUMULUS_VERSION)_$(CARCH).deb

PHONY += quagga quagga-source quagga-patch quagga-build quagga-clean quagga-common-clean

#---
#
PACKAGES1 += $(QUAGGA_STAMP)
quagga: $(QUAGGA_STAMP)
#
##---

SOURCE += $(QUAGGA_PATCH_STAMP)

quagga-source: $(QUAGGA_SOURCE_STAMP)
$(QUAGGA_SOURCE_STAMP): $(PATCHDIR)/quagga/* $(TREE_STAMP_COMMON)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting quagga-$(QUAGGA_VERSION) ===="
	$(SCRIPTDIR)/stg-saferm $(QUAGGADIR)
	@ rm -rf $(PACKAGESDIR_COMMON)/quagga-* $(PACKAGESDIR_COMMON)/quagga_*
	@ cd $(PACKAGESDIR_COMMON) && tar -zxvf $(UPSTREAMDIR)/quagga-$(QUAGGA_VERSION).tar.gz
	@ cd $(PACKAGESDIR_COMMON) && tar -czf quagga_$(QUAGGA_VERSION).orig.tar.gz --exclude='debian' quagga-$(QUAGGA_VERSION)
	@ touch $@
#---
#
quagga-patch: $(QUAGGA_PATCH_STAMP)
$(QUAGGA_PATCH_STAMP): $(QUAGGA_SOURCE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Patching $(QUAGGADIR) ===="
	$(call patch_fnc,quagga,$(QUAGGADIR_COMMON),$(QUAGGA_CUMULUS_VERSION))
	@ touch $@

#---
#
#ifndef MAKE_CLEAN
QUAGGA_NEW_FILES = $(shell test -d $(QUAGGADIR_COMMON) && test -f $(QUAGGA_BUILD_STAMP) && \
				  find -L $(QUAGGADIR_COMMON) -mindepth 1 -newer $(QUAGGA_BUILD_STAMP) \
			-type f -print -quit)
#endif

quagga-build: $(QUAGGA_BUILD_STAMP)
$(QUAGGA_BUILD_STAMP): $(SB2_STAMP) $(QUAGGA_PATCH_STAMP) $(QUAGGA_NEW_FILES) \
			$(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building quagga-$(QUAGGA_VERSION) ===="
	$(call copybuilddir,quagga,$(QUAGGADIR),$(QUAGGA_VERSION))
	$(call copytar,quagga,$(QUAGGA_VERSION))
	$(call deb_build_fnc,$(QUAGGADIR),WANT_SNMP=0)
	@ touch $@

#---

PACKAGES1_INSTALL_DEBS += $(QUAGGA_DEB)

#---

PACKAGES_CLEAN += quagga-clean
PACKAGES_COMMON_CLEAN += quagga-common-clean

quagga-clean:
# uncomment and indent next line if you want safe rm protection here
#@ $(SCRIPTDIR)/stg-saferm $(QUAGGADIR)
	@ rm -rf $(PACKAGESDIR)/quagga[_-]$(QUAGGA_VERSION)*
	@ rm -vf $(QUAGGA_BUILD_STAMP)

quagga-common-clean:
# uncomment and indent next line if you want safe rm protection here
#@ $(SCRIPTDIR)/stg-saferm $(QUAGGADIR)
	@ rm -rf {$(PACKAGESDIR_COMMON),$(PACKAGESDIR)}/quagga[_-]$(QUAGGA_VERSION)*
	@ rm -vf $(QUAGGA_STAMP)


#-------------------------------------------------------------------------------
#
# openvswitch
#

OVS_VERSION             = 1.4.2+git20120612
OVS_DEBIAN_RELEASE	= wheezy
OVS_DEBIAN_VERSION	= $(OVS_VERSION)-9
OVS_CUMULUS_VERSION	= $(OVS_DEBIAN_VERSION)+cl2.5+1
OVS_DIR			= $(PACKAGESDIR)/openvswitch-$(OVS_VERSION)
OVS_DIR_COMMON		= $(PACKAGESDIR_COMMON)/openvswitch-$(OVS_VERSION)
OVS_SOURCE_STAMP	= $(STAMPDIR_COMMON)/openvswitch-source
OVS_PATCH_STAMP	        = $(STAMPDIR_COMMON)/openvswitch-patch
OVS_BUILD_STAMP	        = $(STAMPDIR)/openvswitch-build
OVS_STAMP		= $(OVS_SOURCE_STAMP) \
						  $(OVS_PATCH_STAMP) \
						  $(OVS_BUILD_STAMP)

OVS_DEBS		= $(PACKAGESDIR)/openvswitch-common_$(OVS_CUMULUS_VERSION)_$(CARCH).deb \
			  $(PACKAGESDIR)/openvswitch-vtep_$(OVS_CUMULUS_VERSION)_$(CARCH).deb \
			  $(PACKAGESDIR)/python-openvswitch_$(OVS_CUMULUS_VERSION)_all.deb

PHONY += openvswitch openvswitch-source openvswitch-patch openvswitch-build openvswitch-clean openvswitch-common-clean

#---

PACKAGES1 += $(OVS_STAMP)
openvswitch: $(OVS_STAMP)

#---

SOURCE += $(OVS_PATCH_STAMP)

openvswitch-source: $(OVS_SOURCE_STAMP)
$(OVS_SOURCE_STAMP): $(PATCHDIR)/openvswitch/* $(TREE_STAMP_COMMON)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Extracting and patching the OVS ===="
	@ rm -rf $(PACKAGESDIR_COMMON)/openvswitch-* $(PACKAGESDIR_COMMON)/openvswitch_*
	$(call getsrc_fnc,openvswitch,$(OVS_DEBIAN_VERSION),$(OVS_DEBIAN_RELEASE))
	@ cd $(OVS_DIR_COMMON) && dh_quilt_patch
	touch $@

#---

openvswitch-patch: $(OVS_PATCH_STAMP)
$(OVS_PATCH_STAMP): $(OVS_SOURCE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Patching $(OVS_DIR) ===="
	$(call patch_fnc,openvswitch,$(OVS_DIR_COMMON),$(OVS_CUMULUS_VERSION))
	@ touch $@

#---

ifndef MAKE_CLEAN
OVS_NEW_FILES = $(shell test -d $(OVS_DIR_COMMON) && test -f $(OVS_BUILD_STAMP) && \
		find -L $(OVS_DIR_COMMON) -mindepth 1 -newer $(OVS_BUILD_STAMP) \
		-type f -print -quit)
endif

openvswitch-build: $(OVS_BUILD_STAMP)
$(OVS_BUILD_STAMP): $(SB2_STAMP) $(OVS_PATCH_STAMP) $(OVS_NEW_FILES) \
			$(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building openvswitch-$(OVS_VERSION) ===="
	$(call copybuilddir,openvswitch,$(OVS_DIR),$(OVS_VERSION))
	$(call copytar,openvswitch,$(OVS_VERSION))
	$(call deb_build_fnc,$(OVS_DIR))
	@ touch $@

#---

PACKAGES1_INSTALL_DEBS += $(OVS_DEBS)

#---

PACKAGES_CLEAN += openvswitch-clean
PACKAGES_COMMON_CLEAN += openvswitch-common-clean

openvswitch-clean:
	@ rm -rf $(PACKAGESDIR)/openvswitch[_-]$(OVS_VERSION)*
	@ rm -vf $(OVS_BUILD_STAMP)
	@ rm -f $(PACKAGESDIR)/python-openvswitch_$(OVS_VERSION)*
	@ rm -vf $(OVS_STAMP)

openvswitch-common-clean:
	@ rm -rf {$(PACKAGESDIR_COMMON),$(PACKAGESDIR)}/openvswitch[_-]$(OVS_VERSION)*
	@ rm -vf $(OVS_STAMP)

#-------------------------------------------------------------------------------
#
# lldpd
#

LLDPD_VERSION		= 0.7.11
LLDPD_DEBIAN_VERSION	= $(LLDPD_VERSION)-0
LLDPD_CUMULUS_VERSION	= $(LLDPD_DEBIAN_VERSION)+cl2.5+3
LLDPD_DIR		= $(PACKAGESDIR)/lldpd-$(LLDPD_VERSION)
LLDPD_DIR_COMMON	= $(PACKAGESDIR_COMMON)/lldpd-$(LLDPD_VERSION)

LLDPD_SOURCE_STAMP	= $(STAMPDIR_COMMON)/lldpd-source
LLDPD_PATCH_STAMP	= $(STAMPDIR_COMMON)/lldpd-patch
LLDPD_BUILD_STAMP	= $(STAMPDIR)/lldpd-build
LLDPD_INSTALL_STAMP	= $(STAMPDIR)/lldpd-install
LLDPD_STAMP		= $(LLDPD_SOURCE_STAMP) \
			  $(LLDPD_PATCH_STAMP) \
			  $(LLDPD_BUILD_STAMP)


LLDPD_DEB		= $(PACKAGESDIR)/lldpd_$(LLDPD_CUMULUS_VERSION)_$(CARCH).deb
LLDPD_DEV_DEB		= $(PACKAGESDIR)/liblldpctl-dev_$(LLDPD_CUMULUS_VERSION)_$(CARCH).deb

PHONY += lldpd lldpd-source lldpd-patch lldpd-build lldpd-clean lldpd-common-clean

#---

PACKAGES1 += $(LLDPD_STAMP)
lldpd: $(LLDPD_STAMP)

#---

SOURCE += $(LLDPD_PATCH_STAMP)

lldpd-source: $(LLDPD_SOURCE_STAMP)
$(LLDPD_SOURCE_STAMP): $(PATCHDIR)/lldpd/* $(TREE_STAMP_COMMON)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting and building lldpd ===="
	@ rm -rf $(PACKAGESDIR)/lldpd-* $(PACKAGESDIR)/lldpd_*
	@ cd $(PACKAGESDIR_COMMON) && tar -zxvf $(UPSTREAMDIR)/lldpd-$(LLDPD_VERSION).tar.gz
	@ cd $(PACKAGESDIR_COMMON) && tar -czf lldpd_$(LLDPD_VERSION).orig.tar.gz --exclude='debian' lldpd-$(LLDPD_VERSION)
	@ touch $@

lldpd-patch: $(LLDPD_PATCH_STAMP)

$(LLDPD_PATCH_STAMP): $(LLDPD_SOURCE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Patching $(LLDPD_DIR) ===="
	$(call patch_fnc,lldpd,$(LLDPD_DIR_COMMON),$(LLDPD_CUMULUS_VERSION))
	@ touch $@


#---

lldpd-build: $(LLDPD_BUILD_STAMP)
$(LLDPD_BUILD_STAMP): $(SB2_STAMP) $(LLDPD_PATCH_STAMP) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building lldpd-$(LLDPD_VERSION) ===="
	$(call copybuilddir,lldpd,$(LLDPD_DIR),$(LLDPD_VERSION))
	$(call copytar,lldpd,$(LLDPD_VERSION))
	$(call deb_build_fnc,$(LLDPD_DIR))
	@ touch $@

#---

LLDPD_INSTALL_DEBS = $(LLDPD_DEB) $(LLDPD_DEV_DEB)
PACKAGES1_INSTALL_DEBS += $(LLDPD_INSTALL_DEBS)
#---

lldpd-install: $(LLDPD_INSTALL_STAMP)
$(LLDPD_INSTALL_STAMP): $(LLDPD_BUILD_STAMP) $(BASEINIT_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Unpack packages in $(SYSROOTDIR) ===="
	cd $(PACKAGESDIR) && \
		sudo $(SCRIPTDIR)/dpkg-unpack --force \
		--aptconf=$(BUILDDIR)/apt.conf $(LLDPD_INSTALL_DEBS)
	@ touch $@

#---

PACKAGES_CLEAN += lldpd-clean
PACKAGES_COMMON_CLEAN += lldpd-common-clean

lldpd-clean:
	@ rm -rf $(PACKAGESDIR)/lldpd[_-]$(LLDPD_VERSION)*
	@ rm -vf $(LLDPD_BUILD_STAMP)

lldpd-common-clean:
	@ rm -rf {$(PACKAGESDIR_COMMON),$(PACKAGESDIR)}/lldpd[_-]$(LLDPD_VERSION)*
	@ rm -vf $(LLDPD_STAMP)
#-------------------------------------------------------------------------------
#
# jdoo
#

JDOO_VERSION		= 0.10.3
JDOO_DEBIAN_EPOCH	=
JDOO_DEBIAN_BUILD	= $(JDOO_VERSION)-1
JDOO_DEBIAN_VERSION	= $(JDOO_DEBIAN_EPOCH)$(JDOO_DEBIAN_BUILD)
JDOO_CUMULUS_VERSION	= $(JDOO_DEBIAN_BUILD)
JDOO_UPSTREAM		= $(UPSTREAMDIR)/jdoo-$(JDOO_VERSION).tar.gz
JDOODIR			= $(PACKAGESDIR)/jdoo-$(JDOO_VERSION)

JDOO_SOURCE_STAMP	= $(STAMPDIR)/jdoo-source
JDOO_BUILD_STAMP	= $(STAMPDIR)/jdoo-build
JDOO_STAMP		= $(JDOO_SOURCE_STAMP) \
			  $(JDOO_BUILD_STAMP)

JDOO_DEB		= $(PACKAGESDIR)/jdoo_$(JDOO_CUMULUS_VERSION)_$(CARCH).deb

PHONY += jdoo jdoo-source jdoo-build jdoo-clean

#---

PACKAGES1 += $(JDOO_STAMP)
jdoo: $(JDOO_STAMP)

#---

SOURCE += $(JDOO_PATCH_STAMP)

jdoo-source: $(JDOO_SOURCE_STAMP)
$(JDOO_SOURCE_STAMP): $(TREE_STAMP) $(JDOO_UPSTREAM)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting jdoo ===="
	@ rm -rf $(PACKAGESDIR_COMMON)/jdoo[-_]*
	@ cd $(PACKAGESDIR) && tar -xzf $(JDOO_UPSTREAM)
	@ cd $(JDOODIR) && debchange -v $(JDOO_DEBIAN_BUILD) -D $(DISTRO_NAME) \
		--force-distribution "Cumulus Networks patches"
	@ touch $@

jdoo-build: $(JDOO_BUILD_STAMP)
$(JDOO_BUILD_STAMP): $(SB2_STAMP) $(JDOO_SOURCE_STAMP) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building jdoo-$(JDOO_VERSION) ===="
	$(call copytar,jdoo,$(JDOO_VERSION))
	$(call deb_build_fnc,$(JDOODIR))
	@ touch $@

#---

PACKAGES1_INSTALL_DEBS += $(JDOO_DEB)

#---

PACKAGES_CLEAN += jdoo-clean

jdoo-clean:
	@ rm -rf $(PACKAGESDIR)/jdoo[_-]$(JDOO_VERSION)*
	@ rm -vf $(JDOO_BUILD_STAMP)
	@ rm -vf $(JDOO_DEB)

#-------------------------------------------------------------------------------
#
# ethtool
#

ETHTOOL_VERSION		= 3.4.2
ETHTOOL_DEBIAN_EPOCH	= 1:
ETHTOOL_DEBIAN_BUILD	= $(ETHTOOL_VERSION)-1
ETHTOOL_DEBIAN_VERSION	= $(ETHTOOL_DEBIAN_EPOCH)$(ETHTOOL_DEBIAN_BUILD)
ETHTOOL_CUMULUS_VERSION	= $(ETHTOOL_DEBIAN_BUILD)+cl2.2
ETHTOOLDIR		= $(PACKAGESDIR)/ethtool-$(ETHTOOL_VERSION)
ETHTOOLDIR_COMMON	= $(PACKAGESDIR_COMMON)/ethtool-$(ETHTOOL_VERSION)

ETHTOOL_SOURCE_STAMP	= $(STAMPDIR_COMMON)/ethtool-source
ETHTOOL_PATCH_STAMP	= $(STAMPDIR_COMMON)/ethtool-patch
ETHTOOL_BUILD_STAMP	= $(STAMPDIR)/ethtool-build
ETHTOOL_STAMP		= $(ETHTOOL_SOURCE_STAMP) \
			  $(ETHTOOL_PATCH_STAMP) \
			  $(ETHTOOL_BUILD_STAMP)

ETHTOOL_DEB		= $(PACKAGESDIR)/ethtool_$(ETHTOOL_CUMULUS_VERSION)_$(CARCH).deb

PHONY += ethtool ethtool-source ethtool-patch ethtool-build ethtool-clean ethtool-common-clean

#---

PACKAGES1 += $(ETHTOOL_STAMP)
ethtool: $(ETHTOOL_STAMP)

#---

SOURCE += $(ETHTOOL_PATCH_STAMP)

ethtool-source: $(ETHTOOL_SOURCE_STAMP)
$(ETHTOOL_SOURCE_STAMP): $(PATCHDIR)/ethtool/* $(TREE_STAMP_COMMON)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting and building ethtool ===="
	@ rm -rf $(PACKAGESDIR_COMMON)/ethtool-* $(PACKAGESDIR_COMMON)/ethtool_*
	$(call getsrc_fnc,ethtool,$(ETHTOOL_DEBIAN_VERSION))
	@ touch $@

ethtool-patch: $(ETHTOOL_PATCH_STAMP)
$(ETHTOOL_PATCH_STAMP): $(ETHTOOL_SOURCE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Patching $(ETHTOOLDIR) ===="
	$(call patch_fnc,ethtool,$(ETHTOOLDIR_COMMON),$(ETHTOOL_DEBIAN_EPOCH)$(ETHTOOL_CUMULUS_VERSION))
	@ touch $@


#---

ethtool-build: $(ETHTOOL_BUILD_STAMP)
$(ETHTOOL_BUILD_STAMP): $(SB2_STAMP) $(ETHTOOL_PATCH_STAMP) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building ethtool-$(ETHTOOL_VERSION) ===="
	$(call copybuilddir,ethtool,$(ETHTOOLDIR),$(ETHTOOL_VERSION))
	$(call copytar,ethtool,$(ETHTOOL_VERSION))
	$(call deb_build_fnc,$(ETHTOOLDIR))
	@ touch $@

#---

PACKAGES1_INSTALL_DEBS += $(ETHTOOL_DEB)

#---

PACKAGES_CLEAN += ethtool-clean
PACKAGES_COMMON_CLEAN += ethtool-common-clean

ethtool-clean:
	@ rm -rf $(PACKAGESDIR)/ethtool[_-]$(ETHTOOL_VERSION)*
	@ rm -vf $(ETHTOOL_BUILD_STAMP)

ethtool-common-clean:
	@ rm -rf {$(PACKAGESDIR_COMMON),$(PACKAGESDIR)}/ethtool[_-]$(ETHTOOL_VERSION)*
	@ rm -vf $(ETHTOOL_STAMP)
#-------------------------------------------------------------------------------
#
# cl-cmd
#
#---
CLCMD_VERSION		= 0.01
CLCMD_CLVERSION_EXT	= cl2.5+2
CLCMD_CUMULUS_VERSION	= $(CLCMD_VERSION)-$(CLCMD_CLVERSION_EXT)
CLCMDDIR		= $(PACKAGESDIR)/clcmd-$(CLCMD_VERSION)
CLCMDDIR_COMMON		= $(PACKAGESDIR_COMMON)/clcmd-$(CLCMD_VERSION)

CLCMD_SOURCE_STAMP	= $(STAMPDIR_COMMON)/clcmd-source
CLCMD_BUILD_STAMP	= $(STAMPDIR)/clcmd-build
CLCMD_STAMP		= $(CLCMD_SOURCE_STAMP) \
			  $(CLCMD_BUILD_STAMP)

CLCMD_DEB		= $(PACKAGESDIR)/python-clcmd_$(CLCMD_CUMULUS_VERSION)_all.deb

PHONY += clcmd clcmd-source clcmd-build clcmd-clean clcmd-common-clean

#---

SOURCE += $(CLCMD_SOURCE_STAMP)
PACKAGES1 += $(CLCMD_STAMP)
clcmd: $(CLCMD_STAMP)

#---

ifndef MAKE_CLEAN
CLCMDNEW = $(shell test -d $(PKGSRCDIR)/clcmd  && test -f $(CLCMD_SOURCE_STAMP) && \
				find -L $(PKGSRCDIR)/clcmd -type f \
			-newer $(CLCMD_SOURCE_STAMP) -print -quit)
endif

clcmd-source: $(CLCMD_SOURCE_STAMP)
$(CLCMD_SOURCE_STAMP): $(TREE_STAMP_COMMON) $(CLCMDNEW)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting clcmd ===="
	@ rm -rf $(PACKAGESDIR_COMMON)/clcmd
	cp -R $(PKGSRCDIR)/clcmd $(CLCMDDIR_COMMON)
	@ touch $@

#---

clcmd-build: $(CLCMD_BUILD_STAMP)
$(CLCMD_BUILD_STAMP): $(SB2_STAMP) $(CLCMD_SOURCE_STAMP) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building clcmd-$(CLCMD_VERSION) ===="
	$(call copybuilddir,clcmd,$(CLCMDDIR),$(CLCMD_VERSION))
	cd $(CLCMDDIR) && python gen_man_pages.py
	cd $(CLCMDDIR) && python setup.py --command-packages=stdeb.command sdist_dsc --debian-version $(CLCMD_CLVERSION_EXT) bdist_deb
	# Everything in PACKAGESDIR goes to main repo. This one goes
	# into testing
	mv $(CLCMDDIR)/deb_dist/python-clcmd_$(CLCMD_CUMULUS_VERSION)_all.deb $(CLCMD_DEB)
	@ touch $@

#---

PACKAGES1_INSTALL_DEBS += $(CLCMD_DEB)

#---

PACKAGES_CLEAN += clcmd-clean
PACKAGES_COMMON_CLEAN += clcmd-common-clean

clcmd-clean:
	@ rm -rf $(PACKAGESDIR)/clcmd*
	@ rm -vf $(CLCMD_DEB)
	@ rm -vf $(CLCMD_BUILD_STAMP)

clcmd-common-clean:
	@ rm -rf {$(PACKAGESDIR_COMMON),$(PACKAGESDIR)}/clcmd*
	@ rm -vf $(CLCMD_DEB)
	@ rm -vf $(CLCMD_STAMP)
#-------------------------------------------------------------------------------
#
# iptables
#

IPTABLES_VERSION	= 1.4.14
IPTABLES_DEBIAN_VERSION	= $(IPTABLES_VERSION)-3.1
IPTABLES_CUMULUS_VERSION	= $(IPTABLES_DEBIAN_VERSION)+cl2.5
IPTABLES_DIR		= $(PACKAGESDIR)/iptables-$(IPTABLES_VERSION)
IPTABLES_DIR_COMMON	= $(PACKAGESDIR_COMMON)/iptables-$(IPTABLES_VERSION)

IPTABLES_SOURCE_STAMP	= $(STAMPDIR_COMMON)/iptables-source
IPTABLES_PATCH_STAMP	= $(STAMPDIR_COMMON)/iptables-patch
IPTABLES_BUILD_STAMP	= $(STAMPDIR)/iptables-build
IPTABLES_STAMP		= $(IPTABLES_SOURCE_STAMP) \
			  $(IPTABLES_PATCH_STAMP) \
			  $(IPTABLES_BUILD_STAMP)

IPTABLES_DEB		= $(PACKAGESDIR)/iptables_$(IPTABLES_CUMULUS_VERSION)_$(CARCH).deb
IPTABLES_DEV_DEB	= $(PACKAGESDIR)/iptables-dev_$(IPTABLES_CUMULUS_VERSION)_$(CARCH).deb

PHONY += iptables iptables-source iptables-patch iptables-build iptables-clean iptables-common-clean

#---

PACKAGES1 += $(IPTABLES_STAMP)
iptables: $(IPTABLES_STAMP)

#---

SOURCE += $(IPTABLES_PATCH_STAMP)

iptables-source: $(IPTABLES_SOURCE_STAMP)
$(IPTABLES_SOURCE_STAMP): $(PATCHDIR)/iptables/* $(TREE_STAMP_COMMON)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting and building iptables ===="
	@ rm -rf $(PACKAGESDIR_COMMON)/iptables-* $(PACKAGESDIR_COMMON)/iptables_*
	$(call getsrc_fnc,iptables,$(IPTABLES_DEBIAN_VERSION))
	@ touch $@

iptables-patch: $(IPTABLES_PATCH_STAMP)

$(IPTABLES_PATCH_STAMP): $(IPTABLES_SOURCE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Patching $(IPTABLES_DIR) ===="
	$(call patch_fnc,iptables,$(IPTABLES_DIR_COMMON),$(IPTABLES_CUMULUS_VERSION))
	@ touch $@


#---

iptables-build: $(IPTABLES_BUILD_STAMP)
$(IPTABLES_BUILD_STAMP): $(SB2_STAMP) $(IPTABLES_PATCH_STAMP) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building iptables-$(IPTABLES_VERSION) ===="
	$(call copybuilddir,iptables,$(IPTABLES_DIR),$(IPTABLES_VERSION))
	$(call copytar,iptables,$(IPTABLES_VERSION))
	$(call deb_build_fnc,$(IPTABLES_DIR))
	@ touch $@

#---

PACKAGES1_INSTALL_DEBS += $(IPTABLES_DEB)
PACKAGES1_INSTALL_DEBS += $(IPTABLES_DEV_DEB)

#---

PACKAGES_CLEAN += iptables-clean
PACKAGES_COMMON_CLEAN += iptables-common-clean

iptables-clean:
	@ rm -rf $(PACKAGESDIR)/iptables[_-]$(IPTABLES_VERSION)*
	@ rm -vf $(IPTABLES_BUILD_STAMP)

iptables-common-clean:
	@ rm -rf {$(PACKAGESDIR_COMMON),$(PACKAGESDIR)}/iptables[_-]$(IPTABLES_VERSION)*
	@ rm -vf $(IPTABLES_STAMP)
#-------------------------------------------------------------------------------
#
# ebtables
#

EBTABLES_VERSION	= 2.0.10.4
EBTABLES_DEBIAN_VERSION	= $(EBTABLES_VERSION)-1
EBTABLES_CUMULUS_VERSION	= $(EBTABLES_DEBIAN_VERSION)+cl2.5
EBTABLES_DIR		= $(PACKAGESDIR)/ebtables-$(EBTABLES_VERSION)
EBTABLES_DIR_COMMON	= $(PACKAGESDIR_COMMON)/ebtables-$(EBTABLES_VERSION)

EBTABLES_SOURCE_STAMP	= $(STAMPDIR_COMMON)/ebtables-source
EBTABLES_PATCH_STAMP	= $(STAMPDIR_COMMON)/ebtables-patch
EBTABLES_BUILD_STAMP	= $(STAMPDIR)/ebtables-build
EBTABLES_STAMP		= $(EBTABLES_SOURCE_STAMP) \
			  $(EBTABLES_PATCH_STAMP) \
			  $(EBTABLES_BUILD_STAMP)

EBTABLES_DEB		= $(PACKAGESDIR)/ebtables_$(EBTABLES_CUMULUS_VERSION)_$(CARCH).deb

PHONY += ebtables ebtables-source ebtables-patch ebtables-build ebtables-clean ebtables-common-clean

#---

PACKAGES1 += $(EBTABLES_STAMP)
ebtables: $(EBTABLES_STAMP)

#---

SOURCE += $(EBTABLES_PATCH_STAMP)

ebtables-source: $(EBTABLES_SOURCE_STAMP)
$(EBTABLES_SOURCE_STAMP): $(PATCHDIR)/ebtables/* $(TREE_STAMP_COMMON)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting and building ebtables ===="
	@ rm -rf $(PACKAGESDIR_COMMON)/ebtables-* $(PACKAGESDIR_COMMON)/ebtables_*
	$(call getsrc_fnc,ebtables,$(EBTABLES_DEBIAN_VERSION))
	@ touch $@

ebtables-patch: $(EBTABLES_PATCH_STAMP)

$(EBTABLES_PATCH_STAMP): $(EBTABLES_SOURCE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Patching $(EBTABLES_DIR) ===="
	$(call patch_fnc,ebtables,$(EBTABLES_DIR_COMMON),$(EBTABLES_CUMULUS_VERSION))
	@ touch $@


#---

ebtables-build: $(EBTABLES_BUILD_STAMP)
$(EBTABLES_BUILD_STAMP): $(SB2_STAMP) $(EBTABLES_PATCH_STAMP) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building ebtables-$(EBTABLES_VERSION) ===="
	$(call copybuilddir,ebtables,$(EBTABLES_DIR),$(EBTABLES_VERSION))
	$(call copytar,ebtables,$(EBTABLES_VERSION))
	$(call deb_build_fnc,$(EBTABLES_DIR))
	@ touch $@

#---

PACKAGES1_INSTALL_DEBS += $(EBTABLES_DEB)

#---

PACKAGES_CLEAN += ebtables-clean
PACKAGES_COMMON_CLEAN += ebtables-common-clean

ebtables-clean:
	@ rm -rf $(PACKAGESDIR)/ebtables[_-]$(EBTABLES_VERSION)*
	@ rm -vf $(EBTABLES_BUILD_STAMP)

ebtables-common-clean:
	@ rm -rf {$(PACKAGESDIR_COMMON),$(PACKAGESDIR)}/ebtables[_-]$(EBTABLES_VERSION)*
	@ rm -vf $(EBTABLES_STAMP)
#-------------------------------------------------------------------------------
#
# ntp
#

NTP_VERSION		= 4.2.6.p5+dfsg
NTP_DEBIAN_EPOCH	= 1:
NTP_DEBIAN_BUILD	= $(NTP_VERSION)-2
NTP_DEBIAN_VERSION	= $(NTP_DEBIAN_EPOCH)$(NTP_DEBIAN_BUILD)
NTP_CUMULUS_VERSION	= $(NTP_DEBIAN_BUILD)+cl2
NTPDIR			= $(PACKAGESDIR)/ntp-$(NTP_VERSION)
NTPDIR_COMMON		= $(PACKAGESDIR_COMMON)/ntp-$(NTP_VERSION)

NTP_SOURCE_STAMP	= $(STAMPDIR_COMMON)/ntp-source
NTP_PATCH_STAMP		= $(STAMPDIR_COMMON)/ntp-patch
NTP_BUILD_STAMP		= $(STAMPDIR)/ntp-build
NTP_STAMP		= $(NTP_SOURCE_STAMP) \
			  $(NTP_PATCH_STAMP) \
			  $(NTP_BUILD_STAMP)

NTP_DEB		= $(PACKAGESDIR)/ntp_$(NTP_CUMULUS_VERSION)_$(CARCH).deb

PHONY += ntp ntp-source ntp-patch ntp-build ntp-clean ntp-common-clean

#---

PACKAGES1 += $(NTP_STAMP)
ntp: $(NTP_STAMP)

#---

SOURCE += $(NTP_PATCH_STAMP)

ntp-source: $(NTP_SOURCE_STAMP)
$(NTP_SOURCE_STAMP): $(PATCHDIR)/ntp/* $(TREE_STAMP_COMMON)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting and building ntp ===="
	@ rm -rf $(PACKAGESDIR_COMMON)/ntp-* $(PACKAGESDIR_COMMON)/ntp_*
	$(call getsrc_fnc,ntp,$(NTP_DEBIAN_VERSION))
	@ touch $@

ntp-patch: $(NTP_PATCH_STAMP)
$(NTP_PATCH_STAMP): $(NTP_SOURCE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Patching $(NTPDIR) ===="
	$(call patch_fnc,ntp,$(NTPDIR_COMMON),$(NTP_DEBIAN_EPOCH)$(NTP_CUMULUS_VERSION))
	@ touch $@


#---

ntp-build: $(NTP_BUILD_STAMP)
$(NTP_BUILD_STAMP): $(SB2_STAMP) $(NTP_PATCH_STAMP) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building ntp-$(NTP_VERSION) ===="
	$(call copybuilddir,ntp,$(NTPDIR),$(NTP_VERSION))
	$(call copytar,ntp,$(NTP_VERSION))
	$(call deb_build_fnc,$(NTPDIR))
	@ touch $@

#---

PACKAGES1_INSTALL_DEBS += $(NTP_DEB)

#---

PACKAGES_CLEAN += ntp-clean
PACKAGES_COMMON_CLEAN += ntp-common-clean

ntp-clean:
	@ rm -rf $(PACKAGESDIR)/ntp[_-]$(NTP_VERSION)*
	rm -vf $(NTP_BUILD_STAMP)

ntp-common-clean:
	@ rm -rf {$(PACKAGESDIR_COMMON),$(PACKAGESDIR)}/ntp[_-]$(NTP_VERSION)*
	rm -vf $(NTP_STAMP)
#-------------------------------------------------------------------------------
#
# coreutils
#
COREUTILS_VERSION  = 8.13
COREUTILS_DEBIAN_VERSION  = $(COREUTILS_VERSION)-3.5
COREUTILS_CUMULUS_VERSION = $(COREUTILS_DEBIAN_VERSION)+cl2+1
COREUTILSDIR    = $(PACKAGESDIR)/coreutils-$(COREUTILS_VERSION)
COREUTILSDIR_COMMON    = $(PACKAGESDIR_COMMON)/coreutils-$(COREUTILS_VERSION)

COREUTILS_SOURCE_STAMP  = $(STAMPDIR_COMMON)/coreutils-source
COREUTILS_PATCH_STAMP = $(STAMPDIR_COMMON)/coreutils-patch
COREUTILS_BUILD_STAMP = $(STAMPDIR)/coreutils-build
COREUTILS_STAMP   = $(COREUTILS_SOURCE_STAMP) \
							 $(COREUTILS_PATCH_STAMP) \
							 $(COREUTILS_BUILD_STAMP)

COREUTILS_DEB   = $(PACKAGESDIR)/coreutils_$(COREUTILS_CUMULUS_VERSION)_$(CARCH).deb

PHONY += coreutils coreutils-source coreutils-patch coreutils-build coreutils-clean coreutils-common-clean

PACKAGES1 += $(COREUTILS_STAMP)
coreutils: $(COREUTILS_STAMP)

SOURCE += $(COREUTILS_PATCH_STAMP)

coreutils-source: $(COREUTILS_SOURCE_STAMP)
$(COREUTILS_SOURCE_STAMP): $(PATCHDIR)/coreutils/* $(TREE_STAMP_COMMON)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting and building coreutils ===="
	@ rm -rf $(PACKAGESDIR_COMMON)/coreutils-* $(PACKAGESDIR_COMMON)/coreutils_*
	$(call getsrc_fnc,coreutils,$(COREUTILS_DEBIAN_VERSION))
	@ touch $@

coreutils-patch: $(COREUTILS_PATCH_STAMP)
$(COREUTILS_PATCH_STAMP): $(COREUTILS_SOURCE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Patching $(COREUTILSDIR) ===="
	$(call patch_fnc_noquilt,coreutils,$(COREUTILSDIR_COMMON),$(COREUTILS_CUMULUS_VERSION))
	@ touch $@

coreutils-build: $(COREUTILS_BUILD_STAMP)
$(COREUTILS_BUILD_STAMP): $(SB2_STAMP) $(COREUTILS_PATCH_STAMP) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building coreutils-$(COREUTILS_VERSION) ===="
	$(call copybuilddir,coreutils,$(COREUTILSDIR),$(COREUTILS_VERSION))
	$(call copytar,coreutils,$(COREUTILS_VERSION))
	$(call deb_build_fnc_nosource,$(COREUTILSDIR), DEB_BUILD_OPTIONS=nocheck)
	@ touch $@

PACKAGES1_INSTALL_DEBS += $(COREUTILS_DEB)
PACKAGES_CLEAN += coreutils-clean
PACKAGES_COMMON_CLEAN += coreutils-common-clean


coreutils-clean:
	@ rm -rf $(PACKAGESDIR)/coreutils[_-]$(COREUTILS_VERSION)*
	rm -vf $(COREUTILS_BUILD_STAMP)

coreutils-common-clean:
	@ rm -rf {$(PACKAGESDIR_COMMON),$(PACKAGESDIR)}/coreutils[_-]$(COREUTILS_VERSION)*
	rm -vf $(COREUTILS_STAMP)

#
#-------------------------------------------------------------------------------
#
# bird
#

BIRD_VERSION		= 1.3.10
BIRD_DEBIAN_EPOCH	= 1:
BIRD_DEBIAN_BUILD	= $(BIRD_VERSION)-2
BIRD_DEBIAN_VERSION	= $(BIRD_DEBIAN_EPOCH)$(BIRD_DEBIAN_BUILD)
BIRD_CUMULUS_VERSION	= $(BIRD_DEBIAN_BUILD)+cl2
BIRDDIR			= $(PACKAGESDIR)/bird-$(BIRD_VERSION)
BIRDDIR_COMMON		= $(PACKAGESDIR_COMMON)/bird-$(BIRD_VERSION)

BIRD_SOURCE_STAMP	= $(STAMPDIR_COMMON)/bird-source
BIRD_PATCH_STAMP	= $(STAMPDIR_COMMON)/bird-patch
BIRD_BUILD_STAMP	= $(STAMPDIR)/bird-build
BIRD_STAMP		= $(BIRD_SOURCE_STAMP) \
			  $(BIRD_PATCH_STAMP) \
			  $(BIRD_BUILD_STAMP)

BIRD_DEB		= $(PACKAGESDIR)/bird_$(BIRD_CUMULUS_VERSION)_$(CARCH).deb \
			  $(PACKAGESDIR)/bird6_$(BIRD_CUMULUS_VERSION)_$(CARCH).deb \
			  $(PACKAGESDIR)/bird-dbg_$(BIRD_CUMULUS_VERSION)_$(CARCH).deb

PHONY += bird bird-source bird-patch bird-build bird-clean bird-common-clean

#---

PACKAGES1 += $(BIRD_STAMP)
#PACKAGES1_INSTALL_DEBS += $(BIRD_DEB)
bird: $(BIRD_STAMP)

#---

SOURCE += $(BIRD_PATCH_STAMP)

bird-source: $(BIRD_SOURCE_STAMP)
$(BIRD_SOURCE_STAMP): $(PATCHDIR)/bird/* $(TREE_STAMP_COMMON)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting bird source ===="
	@ rm -rf $(PACKAGESDIR_COMMON)/bird-* $(PACKAGESDIR_COMMON)/bird_*
	@ dpkg-source -x $(UPSTREAMDIR)/bird_$(BIRD_DEBIAN_BUILD).dsc $(BIRDDIR_COMMON)
	@ (cd $(BIRDDIR_COMMON) && dh_quilt_patch)
	@ touch $@

bird-patch: $(BIRD_PATCH_STAMP)
$(BIRD_PATCH_STAMP): $(BIRD_SOURCE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Patching $(BIRDDIR) ===="
	$(call patch_fnc,bird,$(BIRDDIR_COMMON),$(BIRD_DEBIAN_EPOCH)$(BIRD_CUMULUS_VERSION))
	@ touch $@

#---

bird-build: $(BIRD_BUILD_STAMP)
$(BIRD_BUILD_STAMP): $(SB2_STAMP) $(BIRD_PATCH_STAMP) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building bird-$(BIRD_VERSION) ===="
	rm -rf $(BIRDDIR)
	mkdir -p $(BIRDDIR)
	cp -ura $(BIRDDIR_COMMON)/{.pc,*} $(BIRDDIR)
	ln -sf $(BIRDDIR_COMMON)/.{git,cvsignore} $(BIRDDIR)
	$(call copytar,bird,$(BIRD_VERSION))
	$(call deb_build_fnc,$(BIRDDIR))
	@ mv $(BIRD_DEB) $(PACKAGESDIR_TESTING)
	@ touch $@


#---

PACKAGES_CLEAN += bird-clean
PACKAGES_COMMON_CLEAN += bird-common-clean

bird-clean:
	@ rm -f $(BIRD_DEB)
	@ rm -rf $(PACKAGESDIR)/bird[_-]$(BIRD_VERSION)*
	rm -vf $(BIRD_BUILD_STAMP)

bird-common-clean:
	@ rm -f $(BIRD_DEB)
	@ rm -rf {$(PACKAGESDIR_COMMON),$(PACKAGESDIR)}/bird[_-]$(BIRD_VERSION)*
	rm -vf $(BIRD_STAMP)
#-------------------------------------------------------------------------------
#
# rsyslog
#

RSYSLOG_VERSION		= 5.8.11
RSYSLOG_DEBIAN_BUILD	= $(RSYSLOG_VERSION)-3
RSYSLOG_DEBIAN_VERSION	= $(RSYSLOG_DEBIAN_BUILD)
RSYSLOG_CUMULUS_VERSION	= $(RSYSLOG_DEBIAN_BUILD)+cl2.5+1
RSYSLOGDIR		= $(PACKAGESDIR)/rsyslog-$(RSYSLOG_VERSION)
RSYSLOGDIR_COMMON	= $(PACKAGESDIR_COMMON)/rsyslog-$(RSYSLOG_VERSION)

RSYSLOG_SOURCE_STAMP	= $(STAMPDIR_COMMON)/rsyslog-source
RSYSLOG_PATCH_STAMP	= $(STAMPDIR_COMMON)/rsyslog-patch
RSYSLOG_BUILD_STAMP	= $(STAMPDIR)/rsyslog-build
RSYSLOG_STAMP		= $(RSYSLOG_SOURCE_STAMP) \
			  $(RSYSLOG_PATCH_STAMP) \
			  $(RSYSLOG_BUILD_STAMP)

RSYSLOG_DEB		= $(PACKAGESDIR)/rsyslog_$(RSYSLOG_CUMULUS_VERSION)_$(CARCH).deb

PHONY += rsyslog rsyslog-source rsyslog-patch rsyslog-build rsyslog-clean rsyslog-common-clean

#---

PACKAGES1 += $(RSYSLOG_STAMP)
rsyslog: $(RSYSLOG_STAMP)

#---

SOURCE += $(RSYSLOG_PATCH_STAMP)

rsyslog-source: $(RSYSLOG_SOURCE_STAMP)
$(RSYSLOG_SOURCE_STAMP): $(PATCHDIR)/rsyslog/* $(TREE_STAMP_COMMON)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting and building rsyslog ===="
	@ rm -rf $(PACKAGESDIR_COMMON)/rsyslog-* $(PACKAGESDIR_COMMON)/rsyslog_*
	$(call getsrc_fnc,rsyslog,$(RSYSLOG_DEBIAN_VERSION))
	@ touch $@

rsyslog-patch: $(RSYSLOG_PATCH_STAMP)
$(RSYSLOG_PATCH_STAMP): $(RSYSLOG_SOURCE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Patching $(RSYSLOGDIR) ===="
	$(call patch_fnc,rsyslog,$(RSYSLOGDIR_COMMON),$(RSYSLOG_CUMULUS_VERSION))
	@ touch $@


#---

rsyslog-build: $(RSYSLOG_BUILD_STAMP)
$(RSYSLOG_BUILD_STAMP): $(SB2_STAMP) $(RSYSLOG_PATCH_STAMP) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building rsyslog-$(RSYSLOG_VERSION) ===="
	$(call copybuilddir,rsyslog,$(RSYSLOGDIR),$(RSYSLOG_VERSION))
	$(call copytar,rsyslog,$(RSYSLOG_VERSION))
	$(call deb_build_fnc,$(RSYSLOGDIR))
	@ touch $@


PACKAGES1_INSTALL_DEBS += $(RSYSLOG_DEB)

#---

PACKAGES_CLEAN += rsyslog-clean
PACKAGES_COMMON_CLEAN += rsyslog-common-clean

rsyslog-clean:
	@ rm -rf $(PACKAGESDIR)/rsyslog[_-]$(RSYSLOG_VERSION)*
	rm -vf $(RSYSLOG_BUILD_STAMP)

rsyslog-common-clean:
	@ rm -rf {$(PACKAGESDIR_COMMON),$(PACKAGESDIR)}/rsyslog[_-]$(RSYSLOG_VERSION)*
	rm -vf $(RSYSLOG_STAMP)


#---------
#
# package cl-basefiles
#

CL_BASEFILES_VERSION	= 2.6
CL_BASEFILES_CUMULUS_VERSION	= $(CL_BASEFILES_VERSION)-cl2.5+3
CL_BASEFILES_DIR	= $(PACKAGESDIR)/cl-basefiles-$(CL_BASEFILES_VERSION)
CL_BASEFILES_DIR_COMMON	= $(PACKAGESDIR_COMMON)/cl-basefiles-$(CL_BASEFILES_VERSION)

CL_BASEFILES_SOURCE_STAMP	= $(STAMPDIR_COMMON)/cl-basefiles-source
CL_BASEFILES_PATCH_STAMP	= $(STAMPDIR_COMMON)/cl-basefiles-patch
CL_BASEFILES_BUILD_STAMP	= $(STAMPDIR)/cl-basefiles-build
CL_BASEFILES_STAMP		= $(CL_BASEFILES_SOURCE_STAMP) \
				  $(CL_BASEFILES_PATCH_STAMP) \
				  $(CL_BASEFILES_BUILD_STAMP)

CL_BASEFILES_DEB_NAME  = cl-basefiles_$(CL_BASEFILES_CUMULUS_VERSION)_all.deb
CL_BASEFILES_DEB		= 	$(PACKAGESDIR)/$(CL_BASEFILES_DEB_NAME)

PHONY += cl-basefiles cl-basefiles-source cl-basefiles-patch cl-basefiles-common-clean
PHONY += cl-basefiles-build cl-basefiles-clean
#PHONY += cl-basefiles-log-component-versions


#---

PACKAGES1 += $(CL_BASEFILES_STAMP)
cl-basefiles: $(CL_BASEFILES_STAMP)

#---

CL_BASEFILES_SOURCE_DIR = $(realpath ../packages/cl-basefiles)
SOURCE += $(CL_BASEFILES_PATCH_STAMP)

ifndef MAKE_CLEAN
CL_BASEFILESNEW = $(shell test -d $(CL_BASEFILES_SOURCE_DIR)  && \
	test -f $(CL_BASEFILES_SOURCE_STAMP) && \
	find -L $(CL_BASEFILES_SOURCE_DIR) -type f \
		-newer $(CL_BASEFILES_SOURCE_STAMP) -print -quit)
endif

cl-basefiles-source: $(CL_BASEFILES_SOURCE_STAMP)
$(CL_BASEFILES_SOURCE_STAMP): $(CL_BASEFILESNEW) $(TREE_STAMP_COMMON)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting and building cl-basefiles ===="
	@ rm -rf $(PACKAGESDIR_COMMON)/cl-basefiles-* $(PACKAGESDIR_COMMON)/cl-basefiles_*
	@ cp -ar $(CL_BASEFILES_SOURCE_DIR) $(CL_BASEFILES_DIR_COMMON)
	@ cd $(PACKAGESDIR_COMMON) && tar -czf cl-basefiles_$(CL_BASEFILES_VERSION).orig.tar.gz --exclude='debian' cl-basefiles-$(CL_BASEFILES_VERSION)
	@ touch $@

cl-basefiles-patch: $(CL_BASEFILES_PATCH_STAMP)
$(CL_BASEFILES_PATCH_STAMP): $(CL_BASEFILES_SOURCE_STAMP)
	@ (cd $(CL_BASEFILES_DIR_COMMON) && debchange -v \
	    $(CL_BASEFILES_CUMULUS_VERSION) \
	    -D $(DISTRO_NAME)  --force-distribution "Re-version for release")
	@ touch $@

#---

cl-basefiles-build: $(CL_BASEFILES_BUILD_STAMP)
$(CL_BASEFILES_BUILD_STAMP): $(CL_BASEFILES_PATCH_STAMP) $(CL_BASEFILESNEW) \
		$(SB2_STAMP) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building cl-basefiles-$(CL_BASEFILES_VERSION) ===="
	@ cp -ura $(CL_BASEFILES_DIR_COMMON) $(CL_BASEFILES_DIR)
	@ $(call copytar,cl-basefiles,$(CL_BASEFILES_VERSION))
	$(call deb_build_fnc,$(CL_BASEFILES_DIR),\
		LSB_RELEASE_TAG="$(LSB_RELEASE_TAG)" \
		RELEASE_VERSION="$(RELEASE_VERSION)")
	@ touch $@

#---

PACKAGES1_INSTALL_DEBS += $(CL_BASEFILES_DEB)

#---

# As the version of cl-basefiles needs to be updated if the RELEASE_VERSION 
# changes, add it to the list of targets that should be checked for component 
# version changes.

COMPONENT_VERSION_CHECK_TARGETS += cl-basefiles-log-component-versions
cl-basefiles-log-component-versions:
# Fortunately all this info is not dynamically generated.	
	@ echo -e "cl-basefiles -e $(CL_BASEFILES_DEB_NAME)  \
   RELEASE_VERSION $(RELEASE_VERSION) \
\n# cl-basefiles depends on RELEASE_VERSION used in lsb-release and os-release files.\n" \
>> $(COMPONENT_VERSION_CHANGE_MANIFEST_TMP)

#---

PACKAGES_CLEAN += cl-basefiles-clean
PACKAGES_COMMON_CLEAN += cl-basefiles-common-clean

cl-basefiles-clean:
	@ rm -rf $(PACKAGESDIR)/cl-basefiles*
	@ rm -vf $(CL_BASEFILES_BUILD_STAMP)

cl-basefiles-common-clean:
	@ rm -rf {$(PACKAGESDIR_COMMON),$(PACKAGESDIR)}/cl-basefiles*
	@ rm -vf $(CL_BASEFILES_STAMP)


#---------
#
# package cl-l2tune
#

CL_L2TUNE_VERSION	= 2.5
CL_L2TUNE_CUMULUS_VERSION	= $(CL_L2TUNE_VERSION)-cl2.5
CL_L2TUNE_DIR	= $(PACKAGESDIR)/cl-l2tune-$(CL_L2TUNE_VERSION)
CL_L2TUNE_DIR_COMMON	= $(PACKAGESDIR_COMMON)/cl-l2tune-$(CL_L2TUNE_VERSION)

CL_L2TUNE_SOURCE_STAMP	= $(STAMPDIR_COMMON)/cl-l2tune-source
CL_L2TUNE_PATCH_STAMP	= $(STAMPDIR_COMMON)/cl-l2tune-patch
CL_L2TUNE_BUILD_STAMP	= $(STAMPDIR)/cl-l2tune-build
CL_L2TUNE_STAMP		= $(CL_L2TUNE_SOURCE_STAMP) \
				  $(CL_L2TUNE_PATCH_STAMP) \
				  $(CL_L2TUNE_BUILD_STAMP)

CL_L2TUNE_DEB		= \
	$(PACKAGESDIR)/cl-l2tune_$(CL_L2TUNE_CUMULUS_VERSION)_all.deb

PHONY += cl-l2tune cl-l2tune-source cl-l2tune-patch cl-l2tune-common-clean
PHONY += cl-l2tune-build cl-l2tune-clean

#---

PACKAGES1 += $(CL_L2TUNE_STAMP)
cl-l2tune: $(CL_L2TUNE_STAMP)

#---

CL_L2TUNE_SOURCE_DIR = $(realpath ../packages/cl-l2tune)
SOURCE += $(CL_L2TUNE_PATCH_STAMP)

ifndef MAKE_CLEAN
CL_L2TUNENEW = $(shell test -d $(CL_L2TUNE_SOURCE_DIR)  && \
	test -f $(CL_L2TUNE_SOURCE_STAMP) && \
	find -L $(CL_L2TUNE_SOURCE_DIR) -type f \
		-newer $(CL_L2TUNE_SOURCE_STAMP) -print -quit)
endif

cl-l2tune-source: $(CL_L2TUNE_SOURCE_STAMP)
$(CL_L2TUNE_SOURCE_STAMP): $(CL_L2TUNENEW) $(TREE_STAMP_COMMON)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting and building cl-l2tune ===="
	@ rm -rf $(PACKAGESDIR_COMMON)/cl-l2tune-* $(PACKAGESDIR_COMMON)/cl-l2tune_*
	@ cp -ar $(CL_L2TUNE_SOURCE_DIR) $(CL_L2TUNE_DIR_COMMON)
	@ cd $(PACKAGESDIR_COMMON) && tar -czf cl-l2tune-$(CL_L2TUNE_VERSION).orig.tar.gz --exclude='debian' cl-l2tune-$(CL_L2TUNE_VERSION)
	@ touch $@

cl-l2tune-patch: $(CL_L2TUNE_PATCH_STAMP)
$(CL_L2TUNE_PATCH_STAMP): $(CL_L2TUNE_SOURCE_STAMP)
	@ (cd $(CL_L2TUNE_DIR_COMMON) && debchange -v \
	    $(CL_L2TUNE_CUMULUS_VERSION) \
	    -D $(DISTRO_NAME)  --force-distribution "Re-version for release")
	@ touch $@

#---

cl-l2tune-build: $(CL_L2TUNE_BUILD_STAMP)
$(CL_L2TUNE_BUILD_STAMP): $(CL_L2TUNE_PATCH_STAMP) $(CL_L2TUNENEW) \
		$(SB2_STAMP) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building cl-l2tune-$(CL_L2TUNE_VERSION) ===="
	@ cp -ura $(CL_L2TUNE_DIR_COMMON) $(CL_L2TUNE_DIR)
	@ $(call copytar,cl-l2tune-,$(CL_L2TUNE_VERSION))
	$(call deb_build_fnc,$(CL_L2TUNE_DIR),\
		LSB_RELEASE_TAG="$(LSB_RELEASE_TAG)" \
		RELEASE_VERSION="$(RELEASE_VERSION)")
	@ touch $@

#---

PACKAGES1_INSTALL_DEBS += $(CL_L2TUNE_DEB)

#---

PACKAGES_CLEAN += cl-l2tune-clean
PACKAGES_COMMON_CLEAN += cl-l2tune-common-clean

cl-l2tune-clean:
	@ rm -rf $(PACKAGESDIR)/cl-l2tune*
	@ rm -vf $(CL_L2TUNE_BUILD_STAMP)

cl-l2tune-common-clean:
	@ rm -rf {$(PACKAGESDIR_COMMON),$(PACKAGESDIR)}/cl-l2tune*
	@ rm -vf $(CL_L2TUNE_STAMP)

#
#
# simple_pkg_template
#
# Generic template for create simple Cumulus packages
#
# arg $1 -- variable name prefix, all caps and use underscores
# arg $2 -- Makefile targets, use dashes
# arg $3 -- package version
# arg $4 -- Cumulus version suffix
# arg $5 -- architecture -- "all", "amd64", "powerpc"

V ?= 0
Q = @
ifneq ($V,0)
  Q = 
endif

define __simple_pkg_template

$(1)_CUMULUS_VERSION	= $(3)-$(4)
$(1)_DIR		= $(PACKAGESDIR)/$(2)-$(3)
$(1)_DIR_COMMON		= $(PACKAGESDIR_COMMON)/$(2)-$(3)

$(1)_SOURCE_STAMP	= $(STAMPDIR_COMMON)/$(2)-source
$(1)_PATCH_STAMP	= $(STAMPDIR_COMMON)/$(2)-patch
$(1)_BUILD_STAMP	= $(STAMPDIR)/$(2)-build
$(1)_STAMP		= $$($(1)_SOURCE_STAMP) \
			  $$($(1)_PATCH_STAMP) \
			  $$($(1)_BUILD_STAMP)

$(1)_DEB	= \
	$(PACKAGESDIR)/$(2)_$$($(1)_CUMULUS_VERSION)_$(5).deb

PHONY += $(2) $(2)-source $(2)-patch $(2)-common-clean
PHONY += $(2)-build $(2)-clean

#---

PACKAGES1 += $$($(1)_STAMP)
PACKAGES1_INSTALL_DEBS += $$($(1)_DEB)

$(2): $$($(1)_STAMP)

#---

$(1)_SOURCE_DIR = $$(realpath ../packages/$(2))
SOURCE += $$($(1)_PATCH_STAMP)

ifndef MAKE_CLEAN
$(1)_NEW = $$(shell test -d $$($(1)_SOURCE_DIR)  && \
		test -f $$($(1)_SOURCE_STAMP) && \
		find -L $$($(1)_SOURCE_DIR) -type f \
		-newer $$($(1)_SOURCE_STAMP) -print -quit)
endif

$(2)-source: $$($(1)_SOURCE_STAMP)
$$($(1)_SOURCE_STAMP): $$($(1)_NEW) $(TREE_STAMP_COMMON)
	$(Q) rm -f $@ && eval $(PROFILE_STAMP)
	$(Q) echo "==== Getting and building $(2) ===="
	$(Q) rm -rf $(PACKAGESDIR_COMMON)/$(2)-* $(PACKAGESDIR_COMMON)/$(2)_*
	$(Q) cp -ar $$($(1)_SOURCE_DIR) $(PACKAGESDIR_COMMON)/$(2)-$(3)
	$(Q) tar -C $(PACKAGESDIR_COMMON) -czf $(PACKAGESDIR_COMMON)/$(2)_$(3).orig.tar.gz --exclude='debian' $(2)-$(3)
	$(Q) touch $$@

$(2)-patch: $$($(1)_PATCH_STAMP)
$$($(1)_PATCH_STAMP): $$($(1)_SOURCE_STAMP)
	$(Q) (cd $$($(1)_DIR_COMMON) && debchange -v \
		    $$($(1)_CUMULUS_VERSION) \
		    -D $(DISTRO_NAME) --force-distribution "Re-version for release")
	$(Q) touch $$@

#---

$(2)-build: $$($(1)_BUILD_STAMP)
$$($(1)_BUILD_STAMP): $$($(1)_PATCH_STAMP) $(SB2_STAMP) $(BASE_STAMP)
	$(Q) rm -f $@ && eval $(PROFILE_STAMP)
	$(Q) echo "====	 Building $(2)-$(3) ===="
	$(Q) $$(call copybuilddir,$(2),$$($(1)_DIR),$(3))
	$(call copytar,$(2),$(3))
	$(Q) $$(call deb_build_fnc,$$($(1)_DIR),\
		LSB_RELEASE_TAG="$(LSB_RELEASE_TAG)" \
		RELEASE_VERSION="$(RELEASE_VERSION)")
	$(Q) touch $$@

#---

PACKAGES_CLEAN += $(2)-clean
PACKAGES_COMMON_CLEAN += $(2)-common-clean

$(2)-clean:
	$(Q) rm -rf $(PACKAGESDIR)/$(2)*
	$(Q) rm -vf $$($(1)_BUILD_STAMP)

$(2)-common-clean:
	$(Q) rm -rf $(PACKAGESDIR_COMMON)/$(2)*
	$(Q) rm -rf $(PACKAGESDIR)/$(2)*
	$(Q) rm -vf $$($(1)_STAMP)

endef

# Small wrapper around __simple_pkg_template that strips white space
# off the arguments.
define simple_pkg_template
	$(call __simple_pkg_template,$(strip $(1)),$(strip $(2)),$(strip $(3)),$(strip $(4)),$(strip $(5)))
endef

#---------
#
# package onie-tools
#
ifeq ($(CARCH),amd64)
  $(eval $(call simple_pkg_template, ONIE_TOOLS, onie-tools, 0.1, cl2.2, amd64))
endif

#---------
#
# package cl-initramfs
#
$(eval $(call simple_pkg_template, CL_INITRAMFS, cl-initramfs, 0.3, cl2.5+2, $(CARCH)))

#---------
#
# package cl-image
#
$(eval $(call simple_pkg_template, CL_IMAGE, cl-image, 0.2, cl2.5+3, $(CARCH)))

#---------
#
# package iorw
#
$(eval $(call simple_pkg_template, IORW, iorw, 0.1, cl2.2, $(CARCH)))

#---------
#
# package dummy bdb
#
$(eval $(call simple_pkg_template, LIBDB, libdb5.1, 9999, cl2.5, $(CARCH)))

#---------
#
# package opermode
#
$(eval $(call simple_pkg_template, OPERMODE, opermode, 0.1, cl2.5+1, all))

#---------
#
# package dmidecode
#

DMIDECODE_VERSION	= 2.1
DMIDECODE_CUMULUS_VERSION	= $(DMIDECODE_VERSION)-cl2.5
DMIDECODE_DIR	= $(PACKAGESDIR)/dmidecode-$(DMIDECODE_VERSION)
DMIDECODE_DIR_COMMON	= $(PACKAGESDIR_COMMON)/dmidecode-$(DMIDECODE_VERSION)

DMIDECODE_SOURCE_STAMP	= $(STAMPDIR_COMMON)/dmidecode-source
DMIDECODE_PATCH_STAMP	= $(STAMPDIR_COMMON)/dmidecode-patch
DMIDECODE_BUILD_STAMP	= $(STAMPDIR)/dmidecode-build
DMIDECODE_STAMP		= $(DMIDECODE_SOURCE_STAMP) \
				  $(DMIDECODE_PATCH_STAMP) \
				  $(DMIDECODE_BUILD_STAMP)

DMIDECODE_DEB		= \
	$(PACKAGESDIR)/dmidecode_$(DMIDECODE_CUMULUS_VERSION)_powerpc.deb

PHONY += dmidecode dmidecode-source dmidecode-patch dmidecode-common-clean
PHONY += dmidecode-build dmidecode-clean

#---

ifeq ($(CARCH),powerpc)
PACKAGES1 += $(DMIDECODE_STAMP)
PACKAGES1_INSTALL_DEBS += $(DMIDECODE_DEB)
endif

dmidecode: $(DMIDECODE_STAMP)

#---

DMIDECODE_SOURCE_DIR = $(realpath ../packages/dmidecode)
SOURCE += $(DMIDECODE_PATCH_STAMP)

ifndef MAKE_CLEAN
DMIDECODENEW = $(shell test -d $(DMIDECODE_SOURCE_DIR)  && \
	test -f $(DMIDECODE_SOURCE_STAMP) && \
	find -L $(DMIDECODE_SOURCE_DIR) -type f \
		-newer $(DMIDECODE_SOURCE_STAMP) -print -quit)
endif

dmidecode-source: $(DMIDECODE_SOURCE_STAMP)
$(DMIDECODE_SOURCE_STAMP): $(DMIDECODENEW) $(TREE_STAMP_COMMON)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting and building dmidecode ===="
	@ rm -rf $(PACKAGESDIR_COMMON)/dmidecode-* $(PACKAGESDIR_COMMON)/dmidecode_*
	@ cp -ar $(DMIDECODE_SOURCE_DIR) $(DMIDECODE_DIR_COMMON)
	@ cd $(PACKAGESDIR_COMMON) && tar -czf dmidecode_$(DMIDECODE_VERSION).orig.tar.gz --exclude='debian' dmidecode-$(DMIDECODE_VERSION)
	@ touch $@

dmidecode-patch: $(DMIDECODE_PATCH_STAMP)
$(DMIDECODE_PATCH_STAMP): $(DMIDECODE_SOURCE_STAMP)
	@ (cd $(DMIDECODE_DIR_COMMON) && debchange -v \
	    $(DMIDECODE_CUMULUS_VERSION) \
	    -D $(DISTRO_NAME)  --force-distribution "Re-version for release")
	@ touch $@

#---

dmidecode-build: $(DMIDECODE_BUILD_STAMP)
$(DMIDECODE_BUILD_STAMP): $(DMIDECODE_PATCH_STAMP) $(DMIDECODENEW) \
		$(SB2_STAMP) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building dmidecode-$(DMIDECODE_VERSION) ===="
	@ cp -ura $(DMIDECODE_DIR_COMMON) $(DMIDECODE_DIR)
	$(call copytar,dmidecode,$(DMIDECODE_VERSION))
	$(call deb_build_fnc,$(DMIDECODE_DIR),\
		LSB_RELEASE_TAG="$(LSB_RELEASE_TAG)" \
		RELEASE_VERSION="$(RELEASE_VERSION)")
	@ touch $@

#---

PACKAGES_CLEAN += dmidecode-clean
PACKAGES_COMMON_CLEAN += dmidecode-common-clean

dmidecode-clean:
	@ rm -rf $(PACKAGESDIR)/dmidecode*
	@ rm -vf $(DMIDECODE_BUILD_STAMP)

dmidecode-common-clean:
	@ rm -rf {$(PACKAGESDIR_COMMON),$(PACKAGESDIR)}/dmidecode*
	@ rm -vf $(DMIDECODE_STAMP)



#-------------------------------------------------------------------------------
#
# bridge-utils
#
BRIDGE_UTILS_VERSION  = 1.5
BRIDGE_UTILS_DEBIAN_VERSION  = $(BRIDGE_UTILS_VERSION)-6
BRIDGE_UTILS_CUMULUS_VERSION = $(BRIDGE_UTILS_DEBIAN_VERSION)+cl2.5
BRIDGE_UTILSDIR    = $(PACKAGESDIR)/bridge-utils-$(BRIDGE_UTILS_VERSION)
BRIDGE_UTILSDIR_COMMON    = $(PACKAGESDIR_COMMON)/bridge-utils-$(BRIDGE_UTILS_VERSION)

BRIDGE_UTILS_SOURCE_STAMP  = $(STAMPDIR_COMMON)/bridge-utils-source
BRIDGE_UTILS_PATCH_STAMP = $(STAMPDIR_COMMON)/bridge-utils-patch
BRIDGE_UTILS_BUILD_STAMP = $(STAMPDIR)/bridge-utils-build
BRIDGE_UTILS_STAMP   = $(BRIDGE_UTILS_SOURCE_STAMP) \
							 $(BRIDGE_UTILS_PATCH_STAMP) \
							 $(BRIDGE_UTILS_BUILD_STAMP)

BRIDGE_UTILS_DEB   = $(PACKAGESDIR)/bridge-utils_$(BRIDGE_UTILS_CUMULUS_VERSION)_$(CARCH).deb

PHONY += bridge-utils bridge-utils-source bridge-utils-patch bridge-utils-build bridge-utils-clean bridge-utils-common-clean

PACKAGES1 += $(BRIDGE_UTILS_STAMP)
bridge-utils: $(BRIDGE_UTILS_STAMP)

SOURCE += $(BRIDGE_UTILS_PATCH_STAMP)

bridge-utils-source: $(BRIDGE_UTILS_SOURCE_STAMP)
$(BRIDGE_UTILS_SOURCE_STAMP): $(PATCHDIR)/bridge-utils/* $(TREE_STAMP_COMMON)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting and building bridge-utils ===="
	@ rm -rf $(PACKAGESDIR_COMMON)/bridge-utils-* $(PACKAGESDIR_COMMON)/bridge-utils_*
	$(call getsrc_fnc,bridge-utils,$(BRIDGE_UTILS_DEBIAN_VERSION))
	@ touch $@

bridge-utils-patch: $(BRIDGE_UTILS_PATCH_STAMP)
$(BRIDGE_UTILS_PATCH_STAMP): $(BRIDGE_UTILS_SOURCE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Patching $(BRIDGE_UTILSDIR) ===="
	$(call patch_fnc_noquilt,bridge-utils,$(BRIDGE_UTILSDIR_COMMON),$(BRIDGE_UTILS_CUMULUS_VERSION))
	@ touch $@

bridge-utils-build: $(BRIDGE_UTILS_BUILD_STAMP)
$(BRIDGE_UTILS_BUILD_STAMP): $(SB2_STAMP) $(BRIDGE_UTILS_PATCH_STAMP) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building bridge-utils-$(BRIDGE_UTILS_VERSION) ===="
	$(call copybuilddir,bridge-utils,$(BRIDGE_UTILSDIR),$(BRIDGE_UTILS_VERSION))
	$(call copytar,bridge-utils,$(BRIDGE_UTILS_VERSION))
	$(call deb_build_fnc_nosource,$(BRIDGE_UTILSDIR), DEB_BUILD_OPTIONS=nocheck)
	@ touch $@

PACKAGES1_INSTALL_DEBS += $(BRIDGE_UTILS_DEB)
PACKAGES_CLEAN += bridge-utils-clean
PACKAGES_COMMON_CLEAN += bridge-utils-common-clean


bridge-utils-clean:
	@ rm -rf $(PACKAGESDIR)/bridge-utils[_-]$(BRIDGE_UTILS_VERSION)*
	rm -vf $(BRIDGE_UTILS_BUILD_STAMP)

bridge-utils-common-clean:
	@ rm -rf {$(PACKAGESDIR_COMMON),$(PACKAGESDIR)}/bridge-utils[_-]$(BRIDGE_UTILS_VERSION)*
	rm -vf $(BRIDGE_UTILS_STAMP)

#-------------------------------------------------------------------------------
#
# vlan
#
VLAN_VERSION  = 1.9
VLAN_DEBIAN_VERSION  = $(VLAN_VERSION)-3
VLAN_CUMULUS_VERSION = $(VLAN_DEBIAN_VERSION)+cl2.1
VLANDIR    = $(PACKAGESDIR)/vlan-$(VLAN_VERSION)
VLANDIR_COMMON    = $(PACKAGESDIR_COMMON)/vlan-$(VLAN_VERSION)

VLAN_SOURCE_STAMP  = $(STAMPDIR_COMMON)/vlan-source
VLAN_PATCH_STAMP = $(STAMPDIR_COMMON)/vlan-patch
VLAN_BUILD_STAMP = $(STAMPDIR)/vlan-build
VLAN_STAMP   = $(VLAN_SOURCE_STAMP) \
							 $(VLAN_PATCH_STAMP) \
							 $(VLAN_BUILD_STAMP)

VLAN_DEB   = $(PACKAGESDIR)/vlan_$(VLAN_CUMULUS_VERSION)_$(CARCH).deb

PHONY += vlan vlan-source vlan-patch vlan-build vlan-clean vlan-common-clean

PACKAGES1 += $(VLAN_STAMP)
vlan: $(VLAN_STAMP)

SOURCE += $(VLAN_PATCH_STAMP)

vlan-source: $(VLAN_SOURCE_STAMP)
$(VLAN_SOURCE_STAMP): $(PATCHDIR)/vlan/* $(TREE_STAMP_COMMON)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting and building vlan ===="
	@ rm -rf $(PACKAGESDIR_COMMON)/vlan-* $(PACKAGESDIR_COMMON)/vlan_*
	$(call getsrc_fnc,vlan,$(VLAN_DEBIAN_VERSION))
	@ touch $@

vlan-patch: $(VLAN_PATCH_STAMP)
$(VLAN_PATCH_STAMP): $(VLAN_SOURCE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Patching $(VLANDIR) ===="
	$(call patch_fnc_noquilt,vlan,$(VLANDIR_COMMON),$(VLAN_CUMULUS_VERSION))
	@ touch $@

vlan-build: $(VLAN_BUILD_STAMP)
$(VLAN_BUILD_STAMP): $(SB2_STAMP) $(VLAN_PATCH_STAMP) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building vlan-$(VLAN_VERSION) ===="
	$(call copybuilddir,vlan,$(VLANDIR),$(VLAN_VERSION))
	$(call copytar,vlan,$(VLAN_VERSION))
	$(call deb_build_fnc_nosource,$(VLANDIR), DEB_BUILD_OPTIONS=nocheck)
	@ touch $@

PACKAGES1_INSTALL_DEBS += $(VLAN_DEB)
PACKAGES_CLEAN += vlan-clean
PACKAGES_COMMON_CLEAN += vlan-common-clean


vlan-clean:
	@ rm -rf $(PACKAGESDIR)/vlan[_-]$(VLAN_VERSION)*
	rm -vf $(VLAN_BUILD_STAMP)

vlan-common-clean:
	@ rm -rf {$(PACKAGESDIR_COMMON),$(PACKAGESDIR)}/vlan[_-]$(VLAN_VERSION)*
	rm -vf $(VLAN_STAMP)

#-------------------------------------------------------------------------------
#
# apt
#

APT_VERSION   = 0.9.7.9+deb7u5
APT_DEBIAN_VERSION  = $(APT_VERSION)
APT_CUMULUS_VERSION = $(APT_DEBIAN_VERSION)-cl2.1+2
APTDIR    = $(PACKAGESDIR)/apt-$(APT_VERSION)
APTDIR_COMMON    = $(PACKAGESDIR_COMMON)/apt-$(APT_VERSION)

APT_SOURCE_STAMP  = $(STAMPDIR_COMMON)/apt-source
APT_PATCH_STAMP = $(STAMPDIR_COMMON)/apt-patch
APT_BUILD_STAMP = $(STAMPDIR)/apt-build
APT_STAMP   = $(APT_SOURCE_STAMP) \
								$(APT_PATCH_STAMP) \
								$(APT_BUILD_STAMP)

APT_DEB   = $(PACKAGESDIR)/apt_$(APT_CUMULUS_VERSION)_$(CARCH).deb

PHONY += apt apt-source apt-patch apt-build apt-clean apt-common-clean

#---

PACKAGES1 += $(APT_STAMP)
apt: $(APT_STAMP)

#---

SOURCE += $(APT_PATCH_STAMP)

apt-source: $(APT_SOURCE_STAMP)
$(APT_SOURCE_STAMP): $(PATCHDIR)/apt/* $(TREE_STAMP_COMMON)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting and building apt ===="
	@ rm -rf $(PACKAGESDIR_COMMON)/apt-* $(PACKAGESDIR_COMMON)/apt_*
	$(call getsrc_fnc,apt,$(APT_VERSION))
	@ touch $@

apt-patch: $(APT_PATCH_STAMP)
$(APT_PATCH_STAMP): $(APT_SOURCE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Patching $(APTDIR) ===="
	$(call patch_fnc,apt,$(APTDIR_COMMON),$(APT_CUMULUS_VERSION))
	@ touch $@

# Make sure there is a distribution key for apt.
apt-build:  $(APT_BUILD_STAMP)
ifdef BUILD_CI
# If this is a test build, the repository needs to build with it.
$(APT_BUILD_STAMP): $(SB2_STAMP) $(APT_PATCH_STAMP) $(BASE_STAMP) distro-initialize
else
$(APT_BUILD_STAMP): $(SB2_STAMP) $(APT_PATCH_STAMP) $(BASE_STAMP)
endif
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building apt-$(APT_VERSION) ===="
	$(call copybuilddir,apt,$(APTDIR),$(APT_VERSION))
	$(call deb_build_fnc,$(APTDIR))
	@ touch $@

#---
LIBAPTPKG_MAJOR=$(shell grep -E '^\#define APT_PKG_MAJOR' $(APTDIR)/apt-pkg/init.h | cut -d ' ' -f 3)
LIBAPTPKG_MINOR=$(shell grep -E '^\#define APT_PKG_MINOR' $(APTDIR)/apt-pkg/init.h | cut -d ' ' -f 3)
LIBAPTPKG_VERSION=$(LIBAPTPKG_MAJOR).$(LIBAPTPKG_MINOR)
PACKAGES1_INSTALL_DEBS += $(APT_DEB)
# Multiarch pkgs get installed with dpkg not dpkg-unpack.  See CM-17
# Collect these seperately
PACKAGES1_INSTALL_MADEBS += $(PACKAGESDIR)/libapt-pkg$(LIBAPTPKG_VERSION)_$(APT_CUMULUS_VERSION)_$(CARCH).deb
PACKAGES1_INSTALL_DEBS += $(PACKAGESDIR)/apt-transport-https_$(APT_CUMULUS_VERSION)_$(CARCH).deb
#---

PACKAGES_CLEAN += apt-clean
PACKAGES_COMMON_CLEAN += apt-common-clean

apt-clean:
	@ rm -rf $(PACKAGESDIR)/apt[_-]$(APT_VERSION)*
	@ rm -vf $(APT_BUILD_STAMP)


apt-common-clean:
	@ rm -rf {$(PACKAGESDIR_COMMON),$(PACKAGESDIR)}/apt[_-]$(APT_VERSION)*
	@ rm -vf $(APT_STAMP)

#-------------------------------------------------------------------------------
#
# ifenslave-2.6
#

IFENSLAVE_VERSION		= 1.1.0
IFENSLAVE_DEBIAN_VERSION	= $(IFENSLAVE_VERSION)-20
IFENSLAVE_CUMULUS_VERSION	= $(IFENSLAVE_DEBIAN_VERSION)+cl2.1
IFENSLAVEDIR		= $(PACKAGESDIR)/ifenslave-2.6-$(IFENSLAVE_VERSION)
IFENSLAVEDIR_COMMON		= $(PACKAGESDIR_COMMON)/ifenslave-2.6-$(IFENSLAVE_VERSION)

IFENSLAVE_SOURCE_STAMP	= $(STAMPDIR_COMMON)/ifenslave-source
IFENSLAVE_PATCH_STAMP	= $(STAMPDIR_COMMON)/ifenslave-patch
IFENSLAVE_BUILD_STAMP	= $(STAMPDIR)/ifenslave-build
IFENSLAVE_STAMP		= $(IFENSLAVE_SOURCE_STAMP) \
			  $(IFENSLAVE_PATCH_STAMP) \
			  $(IFENSLAVE_BUILD_STAMP)

IFENSLAVE_DEB		= $(PACKAGESDIR)/ifenslave-2.6_$(IFENSLAVE_CUMULUS_VERSION)_$(CARCH).deb

PHONY += ifenslave ifenslave-source ifenslave-patch ifenslave-build ifenslave-clean ifenslave-common-clean

#---

PACKAGES1 += $(IFENSLAVE_STAMP)
ifenslave: $(IFENSLAVE_STAMP)

#---

SOURCE += $(IFENSLAVE_PATCH_STAMP)

ifenslave-source: $(IFENSLAVE_SOURCE_STAMP)
$(IFENSLAVE_SOURCE_STAMP): $(PATCHDIR)/ifenslave-2.6/* $(TREE_STAMP_COMMON)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting and building ifenslave ===="
	@ rm -rf $(PACKAGESDIR_COMMON)/ifenslave-2.6[-_]*
	$(call getsrc_fnc,ifenslave-2.6,$(IFENSLAVE_DEBIAN_VERSION))
	@ touch $@

ifenslave-patch: $(IFENSLAVE_PATCH_STAMP)
$(IFENSLAVE_PATCH_STAMP): $(IFENSLAVE_SOURCE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Patching $(IFENSLAVEDIR) ===="
	$(call patch_fnc,ifenslave-2.6,$(IFENSLAVEDIR_COMMON),$(IFENSLAVE_DEBIAN_EPOCH)$(IFENSLAVE_CUMULUS_VERSION))
	@ touch $@


ifenslave-build: $(IFENSLAVE_BUILD_STAMP)
$(IFENSLAVE_BUILD_STAMP): $(SB2_STAMP) $(IFENSLAVE_PATCH_STAMP) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building ifenslave-2.6-$(IFENSLAVE_VERSION) ===="
	$(call copybuilddir,ifenslave-2.6,$(IFENSLAVEDIR),$(IFENSLAVE_VERSION))
	$(call copytar,ifenslave-2.6,$(IFENSLAVE_VERSION))
	$(call deb_build_fnc,$(IFENSLAVEDIR))
	@ touch $@

#---

PACKAGES1_INSTALL_DEBS += $(IFENSLAVE_DEB)

#---

PACKAGES_CLEAN += ifenslave-clean
PACKAGES_COMMON_CLEAN += ifenslave-common-clean

ifenslave-clean:
	@ rm -rf $(PACKAGESDIR)/ifenslave-2.6[_-]$(IFENSLAVE_VERSION)*
	rm -vf $(IFENSLAVE_BUILD_STAMP)

ifenslave-common-clean:
	@ rm -rf {$(PACKAGESDIR_COMMON),$(PACKAGESDIR)}/ifenslave-2.6[_-]$(IFENSLAVE_VERSION)*
	rm -vf $(IFENSLAVE_STAMP)

#
#-------------------------------------------------------------------------------
#
# python-gvgen
#

PYTHON-GVGEN_VERSION		= 0.9
PYTHON-GVGEN_DEBIAN_BUILD	= $(PYTHON-GVGEN_VERSION)-2
PYTHON-GVGEN_DEBIAN_VERSION	= $(PYTHON-GVGEN_DEBIAN_EPOCH)$(PYTHON-GVGEN_DEBIAN_BUILD)
#PYTON-GVGEN_CUMULUS_VERSION	= $(PYTHON-GVGEN_DEBIAN_BUILD)+cl2
PYTHON-GVGENDIR			= $(PACKAGESDIR)/python-gvgen-$(PYTHON-GVGEN_VERSION)
PYTHON-GVGENDIR_COMMON		= $(PACKAGESDIR_COMMON)/python-gvgen-$(PYTHON-GVGEN_VERSION)

PYTHON-GVGEN_SOURCE_STAMP	= $(STAMPDIR_COMMON)/python-gvgen-source
PYTHON-GVGEN_BUILD_STAMP	= $(STAMPDIR)/python-gvgen-build
PYTHON-GVGEN_STAMP		= $(PYTHON-GVGEN_SOURCE_STAMP) \
			  $(PYTHON-GVGEN_BUILD_STAMP)

PYTHON-GVGEN_DEB		= $(PACKAGESDIR)/python-gvgen_$(PYTHON-GVGEN_DEBIAN_VERSION)_all.deb

PHONY += python-gvgen python-gvgen-source python-gvgen-build python-gvgen-clean python-gvgen-common-clean

#---

PACKAGES1 += $(PYTHON-GVGEN_STAMP)
PACKAGES1_INSTALL_DEBS += $(PYTHON-GVGEN_DEB)
python-gvgen: $(PYTHON-GVGEN_STAMP)

#---

SOURCE += $(PYTHON-GVGEN_SOURCE_STAMP)

python-gvgen-source: $(PYTHON-GVGEN_SOURCE_STAMP)
$(PYTHON-GVGEN_SOURCE_STAMP): $(TREE_STAMP_COMMON)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting python-gvgen source ===="
	@ rm -rf $(PACKAGESDIR_COMMON)/python-gvgen-* $(PACKAGESDIR_COMMON)/python-gvgen_*
	@ dpkg-source -x $(UPSTREAMDIR)/python-gvgen_$(PYTHON-GVGEN_DEBIAN_BUILD).dsc $(PYTHON-GVGENDIR_COMMON)
	@ (cd $(PYTHON-GVGENDIR_COMMON) && dh_quilt_patch)
	@ touch $@

#---

python-gvgen-build: $(PYTHON-GVGEN_BUILD_STAMP)
$(PYTHON-GVGEN_BUILD_STAMP): $(SB2_STAMP) $(PYTHON-GVGEN_SOURCE_STAMP) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building python-gvgen-$(PYTHON-GVGEN_VERSION) ===="
	$(call copybuilddir,python-gvgen,$(PYTHON-GVGENDIR),$(PYTHON-GVGEN_VERSION))
	$(call copytar,python-gvgen,$(PYTHON-GVGEN_VERSION))
	$(call deb_build_fnc,$(PYTHON-GVGENDIR))
	@ touch $@

#---

PACKAGES_CLEAN += python-gvgen-clean
python-gvgen-clean:
	@ rm -f $(PYTHON-GVGEN_DEB)
	@ rm -rf $(PACKAGESDIR)/python-gvgen[_-]$(PYTHON-GVGEN_VERSION)*
	rm -vf $(PYTHON-GVGEN_BUILD_STAMP)

python-gvgen-common-clean:
	@ rm -f $(PYTHON-GVGEN_DEB)
	@ rm -rf $(PACKAGESDIR)/python-gvgen[_-]$(PYTHON-GVGEN_VERSION)*
	@ rm -rf $(PACKAGESDIR_COMMON)/python-gvgen[_-]$(PYTHON-GVGEN_VERSION)*
	rm -vf $(PYTHON-GVGEN_STAMP)

#-------------------------------------------------------------------------------
#
# ifupdown2
#
#---
IFUPDOWN2_VERSION		= 0.1
IFUPDOWN_CLVERSION_EXT		= cl2.5+4
IFUPDOWN2_CUMULUS_VERSION	= $(IFUPDOWN2_VERSION)-$(IFUPDOWN_CLVERSION_EXT)
IFUPDOWN2DIR		= $(PACKAGESDIR)/ifupdown2-$(IFUPDOWN2_VERSION)
IFUPDOWN2DIR_COMMON		= $(PACKAGESDIR_COMMON)/ifupdown2-$(IFUPDOWN2_VERSION)

IFUPDOWN2_SOURCE_STAMP	= $(STAMPDIR_COMMON)/ifupdown2-source
IFUPDOWN2_BUILD_STAMP	= $(STAMPDIR)/ifupdown2-build
IFUPDOWN2_STAMP		= $(IFUPDOWN2_SOURCE_STAMP) \
			  $(IFUPDOWN2_BUILD_STAMP)

IFUPDOWN2_DEB		= $(PACKAGESDIR)/python-ifupdown2_$(IFUPDOWN2_CUMULUS_VERSION)_all.deb

PHONY += ifupdown2 ifupdown2-source ifupdown2-build ifupdown2-clean ifupdown2-common-clean

#---

SOURCE += $(IFUPDOWN2_SOURCE_STAMP)
PACKAGES1 += $(IFUPDOWN2_STAMP)
ifupdown2: $(IFUPDOWN2_STAMP)

#---

ifndef MAKE_CLEAN
IFUPDOWN2NEW = $(shell test -d $(PKGSRCDIR)/ifupdown2  && test -f $(IFUPDOWN2_SOURCE_STAMP) && \
	    	    find -L $(PKGSRCDIR)/ifupdown2 -type f \
			-newer $(IFUPDOWN2_SOURCE_STAMP) -print -quit)
endif

ifupdown2-source: $(IFUPDOWN2_SOURCE_STAMP)
$(IFUPDOWN2_SOURCE_STAMP): $(TREE_STAMP_COMMON) $(IFUPDOWN2NEW)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting ifupdown2 ===="
	@ rm -rf $(PACKAGESDIR_COMMON)/ifupdown2
	cp -R $(PKGSRCDIR)/ifupdown2 $(IFUPDOWN2DIR_COMMON)
	cd $(IFUPDOWN2DIR_COMMON) && ./scripts/genmanpages.sh ./man.rst ./man
	@ touch $@

#---

ifupdown2-build: $(IFUPDOWN2_BUILD_STAMP)
$(IFUPDOWN2_BUILD_STAMP): $(IFUPDOWN2_SOURCE_STAMP) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building ifupdown2-$(IFUPDOWN2_VERSION) ===="
	$(call copybuilddir,ifupdown2,$(IFUPDOWN2DIR),$(IFUPDOWN2_VERSION))
	cd $(IFUPDOWN2DIR) && python setup.py --command-packages=stdeb.command sdist_dsc --debian-version $(IFUPDOWN_CLVERSION_EXT) bdist_deb 
	# Everything in PACKAGESDIR goes to main repo. This one goes
	# into testing
	mv $(IFUPDOWN2DIR)/deb_dist/python-ifupdown2_$(IFUPDOWN2_CUMULUS_VERSION)_all.deb $(IFUPDOWN2_DEB)
	@ touch $@

#---

PACKAGES1_INSTALL_DEBS += $(IFUPDOWN2_DEB)

#---

PACKAGES_CLEAN += ifupdown2-clean
PACKAGES_COMMON_CLEAN += ifupdown2-common-clean

ifupdown2-clean:
	@ rm -rf $(IFUPDOWN2DIR)
	@ rm -vf $(IFUPDOWN2_DEB)
	@ rm -vf $(IFUPDOWN2_BUILD_STAMP)

ifupdown2-common-clean:
	@ rm -rf $(IFUPDOWN2DIR_COMMON)
	@ rm -rf $(IFUPDOWN2DIR)
	@ rm -vf $(IFUPDOWN2_DEB)
	@ rm -vf $(IFUPDOWN2_STAMP)


#-------------------------------------------------------------------
#
# pimd
#

PIMD_VERS		= 2.1.8
PIMD_DEBIAN_VERS	= $(PIMD_VERS)-2
PIMD_CUMULUS_VERS	= $(PIMD_DEBIAN_VERS)+cl2
PIMD_UPSTREAM		= $(UPSTREAMDIR)/pimd-$(PIMD_DEBIAN_VERS).zip
PIMDDIR			= $(PACKAGESDIR)/pimd-$(PIMD_VERS)
PIMDDIR_COMMON		= $(PACKAGESDIR_COMMON)/pimd-$(PIMD_VERS)

PIMD_SOURCE_STAMP	= $(STAMPDIR_COMMON)/pimd-source
PIMD_PATCH_STAMP	= $(STAMPDIR_COMMON)/pimd-patch
PIMD_BUILD_STAMP	= $(STAMPDIR)/pimd-build
PIMD_STAMP		= $(PIMD_SOURCE_STAMP) \
			  $(PIMD_PATCH_STAMP) \
			  $(PIMD_BUILD_STAMP)

PIMD_DEB	= $(PACKAGESDIR)/pimd_$(PIMD_CUMULUS_VERS)_$(CARCH).deb

PHONY += pimd pimd-source pimd-patch pimd-build pimd-clean pimd-common-clean

#---

PACKAGES1 += $(PIMD_STAMP)
pimd: $(PIMD_STAMP)

#---

SOURCE += $(PIMD_PATCH_STAMP)

# pimd src pkg from debian is broken so we keep a good copy in upstream
pimd-source: $(PIMD_SOURCE_STAMP)
$(PIMD_SOURCE_STAMP): $(TREE_STAMP_COMMON) $(PATCHDIR)/pimd/* $(PIMD_UPSTREAM)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting pimd ===="
	@ rm -rf $(PACKAGESDIR_COMMON)/pimd[-_]*
	@ cd $(PACKAGESDIR_COMMON) && unzip $(PIMD_UPSTREAM)
	@ mv $(PACKAGESDIR_COMMON)/pimd-master $(PIMDDIR_COMMON)
	@ cd $(PIMDDIR_COMMON) && echo 3.0 \(quilt\) > debian/source/format
	@ cd $(PACKAGESDIR_COMMON) && tar -czf pimd_$(PIMD_VERS).orig.tar.gz --exclude='debian' pimd-$(PIMD_VERS)
	@ touch $@

pimd-patch: $(PIMD_PATCH_STAMP)
$(PIMD_PATCH_STAMP): $(PIMD_SOURCE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Patching $(PIMDDIR) ===="
	$(call patch_fnc,pimd,$(PIMDDIR_COMMON),$(PIMD_CUMULUS_VERS))
	@ touch $@


#---

pimd-build: $(PIMD_BUILD_STAMP)
$(PIMD_BUILD_STAMP): $(SB2_STAMP) $(PIMD_PATCH_STAMP) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building pimd-$(PIMD_VERS) ===="
	$(call copybuilddir,pimd,$(PIMDDIR),$(PIMD_VERS))
	$(call copytar,pimd,$(PIMD_VERS))
	$(call deb_build_fnc,$(PIMDDIR), DEB_BUILD_OPTIONS=nostrip)
	@ mv $(PIMD_DEB) $(PACKAGESDIR_TESTING)
	@ touch $@


# Not installed.  Goes into testing
#PACKAGES1_INSTALL_DEBS += $(PIMD_DEB)

#---

PACKAGES_CLEAN += pimd-clean
PACKAGES_COMMON_CLEAN += pimd-common-clean

pimd-clean:
	@ rm -rf $(PACKAGESDIR)/pimd[_-]$(PIMD_VERS)*
	rm -vf $(PIMD_BUILD_STAMP)

pimd-common-clean:
	@ rm -rf {$(PACKAGESDIR_COMMON),$(PACKAGESDIR)}/pimd[_-]$(PIMD_VERS)*
	rm -vf $(PIMD_STAMP)

#-------------------------------------------------------------------------------
#
# smcroute
#

SMCROUTE_VERS		= 2.0.0-beta1
# No debian version on this upstream.  Fake it as '0'
# This is so we can upgrade to deb version '1' if there is one
SMCROUTE_CUMULUS_VERS	= $(SMCROUTE_VERS)-0+cl2
SMCROUTE_UPSTREAM	= $(UPSTREAMDIR)/smcroute-$(SMCROUTE_VERS).zip
SMCROUTE_DIR		= $(PACKAGESDIR)/smcroute-$(SMCROUTE_VERS)
SMCROUTE_DIR_COMMON	= $(PACKAGESDIR_COMMON)/smcroute-$(SMCROUTE_VERS)

SMCROUTE_SOURCE_STAMP	= $(STAMPDIR_COMMON)/smcroute-source
SMCROUTE_PATCH_STAMP	= $(STAMPDIR_COMMON)/smcroute-patch
SMCROUTE_BUILD_STAMP	= $(STAMPDIR)/smcroute-build
SMCROUTE_STAMP		= $(SMCROUTE_SOURCE_STAMP) \
			   $(SMCROUTE_PATCH_STAMP) \
			   $(SMCROUTE_BUILD_STAMP)


SMCROUTE_DEB = $(PACKAGESDIR)/smcroute_$(SMCROUTE_CUMULUS_VERS)_$(CARCH).deb

PHONY += smcroute smcroute-source smcroute-patch smcroute-build \
	 smcroute-clean smcroute-common-clean

#-------------------------------------------------------------------------------

PACKAGES1 += $(SMCROUTE_STAMP)
smcroute: $(SMCROUTE_STAMP)
SOURCE += $(SMCROUTE_PATCH_STAMP)

SMCROUTE_SOURCE_DIR = $(realpath ../packages/smcroute)
ifndef MAKE_CLEAN
SMCROUTENEW = $(shell [ -d $(SMCROUTE_SOURCE_DIR) ] && \
		[ -f $(SMCROUTE_SOURCE_STAMP) ] && \
	    	    find -L $(SMCROUTE_SOURCE_DIR) -type f \
			-newer $(SMCROUTE_SOURCE_STAMP) -print -quit)
endif

smcroute-source: $(SMCROUTE_SOURCE_STAMP)
$(SMCROUTE_SOURCE_STAMP): $(TREE_STAMP_COMMON) $(SMCROUTE_UPSTREAM) $(SMCROUTENEW) \
	$(PATCHDIR)/smcroute/*
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Extracting smcroute source ===="
	@ rm -rf $(SMCROUTE_DIR_COMMON)
	@ cd $(PACKAGESDIR_COMMON) && unzip $(SMCROUTE_UPSTREAM)
	@ mv $(PACKAGESDIR_COMMON)/smcroute-master $(SMCROUTE_DIR_COMMON)
	@ cp -ar $(SMCROUTE_SOURCE_DIR)/* $(SMCROUTE_DIR_COMMON)
	@ cd $(PACKAGESDIR_COMMON) && tar -czf smcroute_$(SMCROUTE_VERS).orig.tar.gz smcroute-$(SMCROUTE_VERS)
	@ touch $@


smcroute-patch: $(SMCROUTE_PATCH_STAMP)
$(SMCROUTE_PATCH_STAMP): $(SMCROUTE_SOURCE_STAMP)
	@ echo "==== Patching smcroute ===="
	$(call patch_fnc,smcroute,$(SMCROUTE_DIR_COMMON),$(SMCROUTE_CUMULUS_VERS))
	@ touch $@


#---

#ifndef MAKE_CLEAN
SMCROUTE_NEW_FILES = $(shell test -d $(SMCROUTE_DIR_COMMON) && \
	test -f $(SMCROUTE_BUILD_STAMP) && \
	find -L $(SMCROUTE_DIR_COMMON) -mindepth 1 -newer $(SMCROUTE_BUILD_STAMP) \
	-type f -print -quit)
#endif


smcroute-build: $(SMCROUTE_BUILD_STAMP)
$(SMCROUTE_BUILD_STAMP): $(SB2_STAMP) $(SMCROUTE_PATCH_STAMP) \
		$(SMCROUTE_NEW_FILES) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Building smcroute ===="
	@ cp -ura $(SMCROUTE_DIR_COMMON) $(SMCROUTE_DIR)
	$(call copytar,smcroute,$(SMCROUTE_VERS))
	$(call deb_build_fnc,$(SMCROUTE_DIR))
	@ mv $(SMCROUTE_DEB) $(PACKAGESDIR_TESTING)
	@ touch $@


#---

# Not installed.  Goes to testing
#PACKAGES1_INSTALL_DEBS += $(SMCROUTE_DEB)

#---

PACKAGES_CLEAN += smcroute-clean
PACKAGES_COMMON_CLEAN += smcroute-common-clean

smcroute-clean:
	rm -rf $(PACKAGESDIR)/smcroute*
	rm -f $(SMCROUTE_BUILD_STAMP)

smcroute-common-clean:
	rm -rf {$(PACKAGESDIR_COMMON),$(PACKAGESDIR)}/smcroute*
	rm -f $(SMCROUTE_STAMP)


#-------------------------------------------------------------------------------
#
# mstpd
#

MSTPD_UPSTREAM_VERSION	= r37
MSTPD_VERSION		= 0.$(MSTPD_UPSTREAM_VERSION)
MSTPD_CUMULUS_VERSION	= $(MSTPD_VERSION)-cl2.5+2
MSTPD_UPSTREAM		= $(UPSTREAMDIR)/mstpd-$(MSTPD_UPSTREAM_VERSION).tar.gz
MSTPD_DIR		= $(PACKAGESDIR)/mstpd-$(MSTPD_VERSION)
MSTPD_DIR_COMMON	= $(PACKAGESDIR_COMMON)/mstpd-$(MSTPD_VERSION)

MSTPD_SOURCE_STAMP	= $(STAMPDIR_COMMON)/mstpd-source
MSTPD_PATCH_STAMP	= $(STAMPDIR_COMMON)/mstpd-patch
MSTPD_BUILD_STAMP	= $(STAMPDIR)/mstpd-build
MSTPD_STAMP		= $(MSTPD_SOURCE_STAMP) \
			   $(MSTPD_PATCH_STAMP) \
			   $(MSTPD_BUILD_STAMP)


MSTPD_DEB = $(PACKAGESDIR)/mstpd_$(MSTPD_CUMULUS_VERSION)_$(CARCH).deb

PHONY += mstpd mstpd-source mstpd-patch mstpd-build mstpd-clean mstpd-common-clean

#-------------------------------------------------------------------------------

SOURCE += $(MSTPD_PATCH_STAMP)
PACKAGES1 += $(MSTPD_STAMP)
PACKAGES1_INSTALL_DEBS += $(MSTPD_DEB)
mstpd: $(MSTPD_STAMP)

#---

MSTPD_SOURCE_DIR = $(realpath ../packages/mstpd)
ifndef MAKE_CLEAN
MSTPDNEW = $(shell [ -d $(MSTPD_SOURCE_DIR) ] && \
		[ -f $(MSTPD_SOURCE_STAMP) ] && \
	    	    find -L $(MSTPD_SOURCE_DIR) -type f \
			-newer $(MSTPD_SOURCE_STAMP) -print -quit)
endif

mstpd-source: $(MSTPD_SOURCE_STAMP)
$(MSTPD_SOURCE_STAMP): $(TREE_STAMP_COMMON) $(MSTPD_UPSTREAM) $(PATCHDIR)/mstpd/* \
	$(MSTPDNEW)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Extracting MSDPD ===="
	@ rm -rf $(MSTPD_DIR_COMMON)
	@ tar -zxf $(MSTPD_UPSTREAM) -C $(PACKAGESDIR_COMMON)
	@ mv $(PACKAGESDIR_COMMON)/mstpd $(MSTPD_DIR_COMMON)
	@ cd $(PACKAGESDIR_COMMON) && tar -czf mstpd_$(MSTPD_VERSION).orig.tar.gz --exclude='debian' mstpd-$(MSTPD_VERSION)
	@ cp -ar $(MSTPD_SOURCE_DIR)/* $(MSTPD_DIR_COMMON)
	@ touch $@


mstpd-patch: $(MSTPD_PATCH_STAMP)
$(MSTPD_PATCH_STAMP): $(MSTPD_SOURCE_STAMP)
	@ echo "==== Patching MSDPD ===="
	$(call patch_fnc,mstpd,$(MSTPD_DIR_COMMON),$(MSTPD_CUMULUS_VERSION))
	@ touch $@


#---


ifndef MAKE_CLEAN
MSTPD_NEW_FILES = $(shell [ -d $(MSTPD_DIR_COMMON) ] && \
	[ -f $(MSTPD_BUILD_STAMP) ] && \
	find -L $(MSTPD_DIR_COMMON) -type f -newer $(MSTPD_BUILD_STAMP) -print -quit)
endif

mstpd-build: $(MSTPD_BUILD_STAMP)
$(MSTPD_BUILD_STAMP): $(SB2_STAMP) $(MSTPD_PATCH_STAMP) $(MSTPD_NEW_FILES)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Building mstpd ===="
	@ cp -ura $(MSTPD_DIR_COMMON) $(MSTPD_DIR)
	$(call copytar,mstpd,$(MSTPD_VERSION))
	$(call deb_build_fnc,$(MSTPD_DIR), \
		SYSROOTDIR=$(SYSROOTDIR) TOPDIR=$(TOPDIR))
	@ touch $@

#---

PACKAGES_CLEAN += mstpd-clean
PACKAGES_COMMON_CLEAN += mstpd-common-clean

mstpd-clean:
	rm -rf $(PACKAGESDIR)/mstp*
	rm -rf $(MSTPD_BUILD_STAMP)

mstpd-common-clean:
	rm -rf {$(PACKAGESDIR_COMMON),$(PACKAGESDIR)}/mstp*
	rm -rf $(MSTPD_STAMP)

#---------
#
# cl-platform-config
#
CLPLATFORMCONF_VERSION		= 1.2
CLPLATFORMCONF_CUMULUS_VERSION	= $(CLPLATFORMCONF_VERSION)-cl2.5+2
CLPLATFORMCONF_DIR		= $(PACKAGESDIR)/cl-platform-config-$(CLPLATFORMCONF_VERSION)
CLPLATFORMCONF_DIR_COMMON	= $(PACKAGESDIR_COMMON)/cl-platform-config-$(CLPLATFORMCONF_VERSION)
CLPLATFORMCONFREQDIRS		= 
CLPLATFORMCONF_SOURCE_STAMP	= $(STAMPDIR_COMMON)/cl-platform-config-source
CLPLATFORMCONF_PATCH_STAMP	= $(STAMPDIR_COMMON)/cl-platform-config-patch
CLPLATFORMCONF_BUILD_STAMP	= $(STAMPDIR)/cl-platform-config-build
CLPLATFORMCONF_STAMP		= $(CLPLATFORMCONF_SOURCE_STAMP) \
					$(CLPLATFORMCONF_PATCH_STAMP) \
					$(CLPLATFORMCONF_BUILD_STAMP)

CLPLATFORMCONF_DEB		= $(PACKAGESDIR)/cl-platform-config_$(CLPLATFORMCONF_CUMULUS_VERSION)_$(CARCH).deb

PHONY += cl-platform-config cl-platform-config-source cl-platform-config-patch cl-platform-config-build cl-platform-config-clean cl-platform-config-common-clean
#---

PACKAGES1 += $(CLPLATFORMCONF_STAMP)
PACKAGES1_INSTALL_DEBS += $(CLPLATFORMCONF_DEB)

cl-platform-config: $(CLPLATFORMCONF_STAMP)

#---

CLPLATFORMCONF_SOURCE_DIR = $(realpath ../packages/cl-platform-config/)
SOURCE += $(CLPLATFORMCONF_PATCH_STAMP)

ifndef MAKE_CLEAN
CLPLATFORMCONFNEW = $(shell test -d $(CLPLATFORMCONF_SOURCE_DIR) && test -f \
             $(CLPLATFORMCONF_SOURCE_STAMP) && find -L $(CLPLATFORMCONF_SOURCE_DIR) \
             $(CLPLATFORMCONFREQDIRS) -type f -newer $(CLPLATFORMCONF_SOURCE_STAMP) -print -quit)
endif

cl-platform-config-source: $(CLPLATFORMCONF_SOURCE_STAMP)
$(CLPLATFORMCONF_SOURCE_STAMP): $(CLPLATFORMCONFNEW) $(TREE_STAMP_COMMON)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Setting up cl-platform-config package source ===="
	@ rm -rf $(PACKAGESDIR_COMMON)/cl-platform-config-* $(PACKAGESDIR_COMMON)/cl-platform-config_*
	@ cp -ar $(CLPLATFORMCONF_SOURCE_DIR) $(CLPLATFORMCONF_DIR_COMMON)
	@ cd $(PACKAGESDIR_COMMON) && tar -czf cl-platform-config_$(CLPLATFORMCONF_VERSION).orig.tar.gz --exclude='debian' cl-platform-config-$(CLPLATFORMCONF_VERSION)
	@ touch $@


cl-platform-config-patch: $(CLPLATFORMCONF_PATCH_STAMP)
$(CLPLATFORMCONF_PATCH_STAMP): $(CLPLATFORMCONF_SOURCE_STAMP)
	@ (cd $(CLPLATFORMCONF_DIR_COMMON) && debchange -v $(CLPLATFORMCONF_CUMULUS_VERSION) \
		-D $(DISTRO_NAME) --force-distribution "Re-version for release")
	@ touch $@

#---

cl-platform-config-build: $(CLPLATFORMCONF_BUILD_STAMP)
$(CLPLATFORMCONF_BUILD_STAMP): $(CLPLATFORMCONF_PATCH_STAMP) $(CLPLATFORMCONFNEW) $(SB2_STAMP)
	@ rm -f && eval $(PROFILE_STAMP)
	@ echo "==== Building cl-platform-config-$(CLPLATFORMCONF_VERSION) ===="
	@ cp -ura $(CLPLATFORMCONF_DIR_COMMON) $(CLPLATFORMCONF_DIR)
	$(call deb_build_fnc,$(CLPLATFORMCONF_DIR),\
		SYSROOTDIR=$(SYSROOTDIR) TOPDIR=$(TOPDIR))
	@ touch $@

#---

PACKAGES_CLEAN += cl-platform-config-clean
PACKAGES_COMMON_CLEAN += cl-platform-config-common-clean

cl-platform-config-clean:
	@ rm -rf $(PACKAGESDIR)/cl-platform-config*
	@ rm -vf $(CLPLATFORMCONF_BUILD_STAMP)

cl-platform-config-common-clean:
	@ rm -rf {$(PACKAGESDIR_COMMON),$(PACKAGESDIR)}/cl-platform-config*
	@ rm -vf $(CLPLATFORMCONF_STAMP)

#---------
#
# package cl-utilities
#

CLUTIL_VERSION		= 1.1
CLUTIL_CUMULUS_VERSION	= $(CLUTIL_VERSION)-cl2.5+6
CLUTIL_DIR		= $(PACKAGESDIR)/cl-utilities-$(CLUTIL_VERSION)
CLUTIL_DIR_COMMON	= $(PACKAGESDIR_COMMON)/cl-utilities-$(CLUTIL_VERSION)
CLUTILREQDIRS		= 

CLUTIL_SOURCE_STAMP	= $(STAMPDIR_COMMON)/cl-utilities-source
CLUTIL_PATCH_STAMP	= $(STAMPDIR_COMMON)/cl-utilities-patch
CLUTIL_BUILD_STAMP	= $(STAMPDIR)/cl-utilities-build
CLUTIL_STAMP		= $(CLUTIL_SOURCE_STAMP) \
			  $(CLUTIL_PATCH_STAMP) \
			  $(CLUTIL_BUILD_STAMP)

CLUTIL_DEB	= $(PACKAGESDIR)/cl-utilities_$(CLUTIL_CUMULUS_VERSION)_$(CARCH).deb

PHONY += clutils clutils-source clutils-patch clutils-build clutils-clean clutils-common-clean
#---

PACKAGES1 += $(CLUTIL_STAMP)
PACKAGES1_INSTALL_DEBS += $(CLUTIL_DEB)

clutils: $(CLUTIL_STAMP)

#---

CLUTIL_SOURCE_DIR = $(realpath ../packages/cl-utilities/)
SOURCE += $(CLUTIL_PATCH_STAMP)

ifndef MAKE_CLEAN
CLUTILNEW = $(shell test -d $(CLUTIL_SOURCE_DIR) && test -f \
	$(CLUTIL_SOURCE_STAMP) && find -L $(CLUTIL_SOURCE_DIR) \
	$(CLUTILREQDIRS) -type f -newer $(CLUTIL_SOURCE_STAMP) -print -quit)
endif

clutils-source: $(CLUTIL_SOURCE_STAMP)
$(CLUTIL_SOURCE_STAMP): $(CLUTILNEW) $(TREE_STAMP_COMMON)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Setting up cl-utilities package source ===="
	@ rm -rf $(PACKAGESDIR_COMMON)/cl-utilities-* $(PACKAGESDIR_COMMON)/cl-utilities_*
	@ cp -ar $(CLUTIL_SOURCE_DIR) $(CLUTIL_DIR_COMMON)
	@ echo "Exclude residual pyc files in src tree (hidden by .gitignore)"
	@ find $(CLUTIL_DIR_COMMON) -name '*.pyc' -exec rm '{}' \;
	@ $(SCRIPTDIR)/deb-rst2man.sh $(CLUTIL_DIR_COMMON)
	@ cd $(PACKAGESDIR_COMMON) && tar -czf cl-utilities_$(CLUTIL_VERSION).orig.tar.gz --exclude='debian' cl-utilities-$(CLUTIL_VERSION)
	@ touch $@

clutils-patch: $(CLUTIL_PATCH_STAMP)
$(CLUTIL_PATCH_STAMP): $(CLUTIL_SOURCE_STAMP)
	@ (cd $(CLUTIL_DIR_COMMON) && debchange -v $(CLUTIL_CUMULUS_VERSION) \
	     -D $(DISTRO_NAME) --force-distribution "Re-version for release")
	@ touch $@

#---

clutils-build: $(CLUTIL_BUILD_STAMP)
$(CLUTIL_BUILD_STAMP): $(CLUTIL_PATCH_STAMP) $(CLUTILNEW) $(SB2_STAMP)
	@ rm -f && eval $(PROFILE_STAMP)
	@ echo "==== Building cl-utilities-$(CLUTIL_VERSION) ===="
	@ cp -ura $(CLUTIL_DIR_COMMON) $(CLUTIL_DIR)
	$(call copytar,cl-utilities,$(CLUTIL_VERSION))
	$(call deb_build_fnc,$(CLUTIL_DIR),\
		SYSROOTDIR=$(SYSROOTDIR) TOPDIR=$(TOPDIR))
	@ touch $@

#---

PACKAGES_CLEAN += clutils-clean
PACKAGES_COMMON_CLEAN += clutils-common-clean

clutils-clean:
	@ rm -rf $(PACKAGESDIR)/cl-utilities*
	@ rm -vf $(CLUTIL_BUILD_STAMP)

clutils-common-clean:
	@ rm -rf {$(PACKAGESDIR_COMMON),$(PACKAGESDIR)}/cl-utilities*
	@ rm -vf $(CLUTIL_STAMP)

#-------------------------------------------------------------------------------
#
# clag
#
#---
CLAG_VERSION		= 0.3
CLAG_CLVERSION_EXT	= cl2.5+3
CLAG_CUMULUS_VERSION	= $(CLAG_VERSION)-$(CLAG_CLVERSION_EXT)
CLAG_DIR		= $(PACKAGESDIR)/clag-$(CLAG_VERSION)
CLAG_DIR_COMMON		= $(PACKAGESDIR_COMMON)/clag-$(CLAG_VERSION)
CLAGREQDIRS		= 

CLAG_SOURCE_STAMP	= $(STAMPDIR_COMMON)/clag-source
CLAG_BUILD_STAMP	= $(STAMPDIR)/clag-build
CLAG_STAMP		= $(CLAG_SOURCE_STAMP) \
			  $(CLAG_BUILD_STAMP)

CLAG_DEB		= $(PACKAGESDIR)/clag_$(CLAG_CUMULUS_VERSION)_all.deb

PHONY += clag clag-source clag-build clag-clean clag-common-clean

#---

PACKAGES1 += $(CLAG_STAMP)
PACKAGES1_INSTALL_DEBS += $(CLAG_DEB)

clag: $(CLAG_STAMP)

#---

SOURCE += $(CLAG_SOURCE_STAMP)
CLAG_SOURCE_DIR = $(realpath ../packages/clag/)

ifndef MAKE_CLEAN
CLAGNEW = $(shell test -d $(CLAG_SOURCE_DIR)  && test -f $(CLAG_SOURCE_STAMP) && \
	    	    find -L $(CLAG_SOURCE_DIR) $(CLAGREQDIRS) -type f \
			-newer $(CLAG_SOURCE_STAMP) -print -quit)
endif

clag-source: $(CLAG_SOURCE_STAMP)
$(CLAG_SOURCE_STAMP): $(TREE_STAMP_COMMON) $(CLAGNEW)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Setting up clag package source ===="
	@ rm -rf $(PACKAGESDIR_COMMON)/clag-* $(PACKAGESDIR_COMMON)/clag_*
	@ cp -ar $(CLAG_SOURCE_DIR) $(CLAG_DIR_COMMON)
	@ echo "Exclude residual pyc files in src tree (hidden by .gitignore)"
	@ find $(CLAG_DIR_COMMON) -name '*.pyc' -exec rm '{}' \;
	@ cd $(PACKAGESDIR_COMMON) && tar -czf clag_$(CLAG_VERSION).orig.tar.gz --exclude='debian' clag-$(CLAG_VERSION)
	@ touch $@

#---

clag-build: $(CLAG_BUILD_STAMP)
$(CLAG_BUILD_STAMP): $(CLAG_SOURCE_STAMP) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building clag-$(CLAG_VERSION) ===="
	$(call copybuilddir,clag,$(CLAG_DIR),$(CLAG_VERSION))
	$(call copytar,clag,$(CLAG_VERSION))
	cd $(CLAG_DIR) && python setup.py --command-packages=stdeb.command sdist_dsc --debian-version $(CLAG_CLVERSION_EXT) bdist_deb 
	mv $(CLAG_DIR)/deb_dist/python-clag_$(CLAG_CUMULUS_VERSION)_all.deb $(CLAG_DEB)
	@ touch $@

#---

PACKAGES_CLEAN += clag-clean
PACKAGES_COMMON_CLEAN += clag-common-clean

clag-clean:
	@ rm -rf $(PACKAGESDIR)/clag*
	@ rm -vf $(CLAG_DEB)
	@ rm -vf $(CLAG_BUILD_STAMP)

clag-common-clean:
	@ rm -rf {$(PACKAGESDIR_COMMON),$(PACKAGESDIR)}/clag*
	@ rm -vf $(CLAG_DEB)
	@ rm -vf $(CLAG_STAMP)


#-------------------------------------------------------------------------------
#
# bash-completion
#

BASHCOMPLETION_VERSION		= 2.0
BASHCOMPLETION_DEBIAN_EPOCH	= 1:
BASHCOMPLETION_DEBIAN_BUILD	= $(BASHCOMPLETION_VERSION)-1
BASHCOMPLETION_DEBIAN_VERSION	= $(BASHCOMPLETION_DEBIAN_EPOCH)$(BASHCOMPLETION_DEBIAN_BUILD)
BASHCOMPLETION_CUMULUS_VERSION	= $(BASHCOMPLETION_DEBIAN_BUILD)+cl2+1
BASHCOMPLETIONDIR		= $(PACKAGESDIR)/bash-completion-$(BASHCOMPLETION_VERSION)
BASHCOMPLETIONDIR_COMMON	= $(PACKAGESDIR_COMMON)/bash-completion-$(BASHCOMPLETION_VERSION)

BASHCOMPLETION_SOURCE_STAMP	= $(STAMPDIR_COMMON)/bash-completion-source
BASHCOMPLETION_PATCH_STAMP	= $(STAMPDIR_COMMON)/bash-completion-patch
BASHCOMPLETION_BUILD_STAMP	= $(STAMPDIR)/bash-completion-build
BASHCOMPLETION_STAMP		= $(BASHCOMPLETION_SOURCE_STAMP) \
			  $(BASHCOMPLETION_PATCH_STAMP) \
			  $(BASHCOMPLETION_BUILD_STAMP)

BASHCOMPLETION_DEB		= $(PACKAGESDIR)/bash-completion_$(BASHCOMPLETION_CUMULUS_VERSION)_all.deb

PHONY += bash-completion bash-completion-source bash-completion-patch bash-completion-build bash-completion-clean bash-completion-common-clean

#---

PACKAGES1 += $(BASHCOMPLETION_STAMP)
bash-completion: $(BASHCOMPLETION_STAMP)

#---

SOURCE += $(BASHCOMPLETION_PATCH_STAMP)

bash-completion-source: $(BASHCOMPLETION_SOURCE_STAMP)
$(BASHCOMPLETION_SOURCE_STAMP): $(PATCHDIR)/bash-completion/* $(TREE_STAMP_COMMON)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting and building bash-completion ===="
	@ rm -rf $(PACKAGESDIR_COMMON)/bash-completion-* $(PACKAGESDIR_COMMON)/bash-completion_*
	$(call getsrc_fnc,bash-completion,$(BASHCOMPLETION_DEBIAN_VERSION))
	@ touch $@

bash-completion-patch: $(BASHCOMPLETION_PATCH_STAMP)
$(BASHCOMPLETION_PATCH_STAMP): $(BASHCOMPLETION_SOURCE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Patching $(BASHCOMPLETIONDIR_COMMON) ===="
	$(call patch_fnc,bash-completion,$(BASHCOMPLETIONDIR_COMMON),$(BASHCOMPLETION_DEBIAN_EPOCH)$(BASHCOMPLETION_CUMULUS_VERSION))
	@ touch $@


#---

bash-completion-build: $(BASHCOMPLETION_BUILD_STAMP)
$(BASHCOMPLETION_BUILD_STAMP): $(SB2_STAMP) $(BASHCOMPLETION_PATCH_STAMP) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building bash-completion-$(BASHCOMPLETION_VERSION) ===="
	$(call copybuilddir,bash-completion,$(BASHCOMPLETIONDIR),$(BASHCOMPLETION_VERSION))
	$(call copytar,bash-completion,$(BASHCOMPLETION_VERSION))
	$(call deb_build_fnc,$(BASHCOMPLETIONDIR))
	@ touch $@

#---

PACKAGES1_INSTALL_DEBS += $(BASHCOMPLETION_DEB)

#---

PACKAGES_CLEAN += bash-completion-clean
PACKAGES_COMMON_CLEAN += bash-completion-common-clean

bash-completion-clean:
	@ rm -rf $(PACKAGESDIR)/bash-completion[_-]$(BASHCOMPLETION_VERSION)*
	rm -vf $(BASHCOMPLETION_BUILD_STAMP)

bash-completion-common-clean:
	@ rm -rf {$(PACKAGESDIR_COMMON),$(PACKAGESDIR)}/bash-completion[_-]$(BASHCOMPLETION_VERSION)*
	rm -vf $(BASHCOMPLETION_STAMP)
#
#-------------------------------------------------------------------------------
#
# python-argcomplete
#

PYTHON-ARGCOMPLETE_VERSION		= 0.6.9
PYTHON-ARGCOMPLETE_DEBIAN_BUILD	= $(PYTHON-ARGCOMPLETE_VERSION)-1
PYTHON-ARGCOMPLETE_DEBIAN_VERSION	= $(PYTHON-ARGCOMPLETE_DEBIAN_EPOCH)$(PYTHON-ARGCOMPLETE_DEBIAN_BUILD)
#PYTON-ARGCOMPLETE_CUMULUS_VERSION	= $(PYTHON-ARGCOMPLETE_DEBIAN_BUILD)+cl2
PYTHON-ARGCOMPLETEDIR			= $(PACKAGESDIR)/python-argcomplete-$(PYTHON-ARGCOMPLETE_VERSION)
PYTHON-ARGCOMPLETEDIR_COMMON		= $(PACKAGESDIR_COMMON)/python-argcomplete-$(PYTHON-ARGCOMPLETE_VERSION)

PYTHON-ARGCOMPLETE_SOURCE_STAMP	= $(STAMPDIR_COMMON)/python-argcomplete-source
PYTHON-ARGCOMPLETE_BUILD_STAMP	= $(STAMPDIR)/python-argcomplete-build
PYTHON-ARGCOMPLETE_STAMP		= $(PYTHON-ARGCOMPLETE_SOURCE_STAMP) \
			  $(PYTHON-ARGCOMPLETE_BUILD_STAMP)

PYTHON-ARGCOMPLETE_DEB		= $(PACKAGESDIR)/python-argcomplete_$(PYTHON-ARGCOMPLETE_DEBIAN_VERSION)_all.deb

PHONY += python-argcomplete python-argcomplete-source python-argcomplete-build python-argcomplete-clean python-argcomplete-common-clean

#---

PACKAGES1 += $(PYTHON-ARGCOMPLETE_STAMP)
PACKAGES1_INSTALL_DEBS += $(PYTHON-ARGCOMPLETE_DEB)
python-argcomplete: $(PYTHON-ARGCOMPLETE_STAMP)

#---

SOURCE += $(PYTHON-ARGCOMPLETE_SOURCE_STAMP)

python-argcomplete-source: $(PYTHON-ARGCOMPLETE_SOURCE_STAMP)
$(PYTHON-ARGCOMPLETE_SOURCE_STAMP): $(TREE_STAMP_COMMON)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting python-argcomplete source ===="
	@ rm -rf $(PACKAGESDIR_COMMON)/python-argcomplete-* $(PACKAGESDIR_COMMON)/python-argcomplete_*
	@ dpkg-source -x $(UPSTREAMDIR)/python-argcomplete_$(PYTHON-ARGCOMPLETE_DEBIAN_BUILD).dsc $(PYTHON-ARGCOMPLETEDIR_COMMON)
	@ (cd $(PYTHON-ARGCOMPLETEDIR_COMMON) && dh_quilt_patch)
	@ touch $@

#---

python-argcomplete-build: $(PYTHON-ARGCOMPLETE_BUILD_STAMP)
$(PYTHON-ARGCOMPLETE_BUILD_STAMP): $(SB2_STAMP) $(PYTHON-ARGCOMPLETE_SOURCE_STAMP) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building python-argcomplete-$(PYTHON-ARGCOMPLETE_VERSION) ===="
	$(call copybuilddir,python-argcomplete,$(PYTHON-ARGCOMPLETEDIR),$(PYTHON-ARGCOMPLETE_VERSION))
	$(call copytar,python-argcomplete,$(PYTHON-ARGCOMPLETE_VERSION))
	$(call deb_build_fnc,$(PYTHON-ARGCOMPLETEDIR))
	@ touch $@


#---

PACKAGES_CLEAN += python-argcomplete-clean
PACKAGES_COMMON_CLEAN += python-argcomplete-common-clean

python-argcomplete-clean:
	@ rm -f $(PYTHON-ARGCOMPLETE_DEB)
	@ rm -rf $(PACKAGESDIR)/python-argcomplete[_-]$(PYTHON-ARGCOMPLETE_VERSION)*
	rm -vf $(PYTHON-ARGCOMPLETE_BUILD_STAMP)

python-argcomplete-common-clean:
	@ rm -f $(PYTHON-ARGCOMPLETE_DEB)
	@ rm -rf {$(PACKAGESDIR_COMMON),$(PACKAGESDIR)}/python-argcomplete[_-]$(PYTHON-ARGCOMPLETE_VERSION)*
	rm -vf $(PYTHON-ARGCOMPLETE_STAMP)

#-------------------------------------------------------------------------------
#
# hsflowd
HSFLOWD_VERSION         = 1.27.3
HSFLOWD_DEBIAN_VERSION  = $(HSFLOWD_VERSION)-1
HSFLOWD_CUMULUS_VERSION = $(HSFLOWD_DEBIAN_VERSION)+cl2.2
HSFLOWD_UPSTREAM        = $(UPSTREAMDIR)/hsflowd-$(HSFLOWD_VERSION).tar.gz
HSFLOWD_DIR             = $(PACKAGESDIR)/hsflowd-$(HSFLOWD_VERSION)

HSFLOWD_SOURCE_STAMP    = $(STAMPDIR)/hsflowd-source
HSFLOWD_PATCH_STAMP     = $(STAMPDIR)/hsflowd-patch
HSFLOWD_BUILD_STAMP     = $(STAMPDIR)/hsflowd-build
HSFLOWD_STAMP           = $(HSFLOWD_SOURCE_STAMP) \
                          $(HSFLOWD_PATCH_STAMP) \
                          $(HSFLOWD_BUILD_STAMP)

HSFLOWD_DEB             = $(PACKAGESDIR)/hsflowd_$(HSFLOWD_CUMULUS_VERSION)_$(CARCH).deb

PHONY += hsflowd hsflowd-source hsflowd-patch hsflowd-build hsflowd-clean

HSFLOWD_PACKAGES_DIR = $(realpath ../packages/hsflowd)

#---

PACKAGES1 += $(HSFLOWD_STAMP)
hsflowd: $(HSFLOWD_STAMP)

#---

SOURCE += $(HSFLOWD_PATCH_STAMP)
hsflowd-source: $(HSFLOWD_SOURCE_STAMP)
$(HSFLOWD_SOURCE_STAMP): $(TREE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting hsflowd ===="
	@ rm -rf $(PACKAGESDIR)/hsflowd-* $(PACKAGESDIR)/hsflowd_*
	@ tar -zxf $(HSFLOWD_UPSTREAM) -C $(PACKAGESDIR)
	@ [ -d $(HSFLOWD_DIR)/debian ] || mkdir $(HSFLOWD_DIR)/debian
	@ cp $(HSFLOWD_PACKAGES_DIR)/debian/* $(HSFLOWD_DIR)/debian
	@ touch $@

hsflowd-patch: $(HSFLOWD_PATCH_STAMP)
$(HSFLOWD_PATCH_STAMP): $(HSFLOWD_SOURCE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Patching $(HSFLOWD_DIR) ===="
	$(call patch_fnc,hsflowd,$(HSFLOWD_DIR),$(HSFLOWD_CUMULUS_VERSION))
	@ touch $@

#---

hsflowd-build: $(HSFLOWD_BUILD_STAMP)
$(HSFLOWD_BUILD_STAMP): $(SB2_STAMP) $(HSFLOWD_PATCH_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building hsflowd-$(HSFLOWD_VERSION) ===="
	@ echo "-  $(HSFLOWD_DIR) $(SB2MAPPING) $(SB2_TARGET)"
	$(call deb_build_fnc,$(HSFLOWD_DIR))
	@ mv $(HSFLOWD_DEB) $(PACKAGESDIR_ADDONS)
	@ touch $@

#---

PACKAGES_CLEAN += hsflowd-clean
hsflowd-clean:
	@ rm -rf $(PACKAGESDIR)/hsflowd[_-]$(HSFLOWD_VERSION)*
	@ rm -rf $(PACKAGESDIR_TESTING)/hsflowd[_-]$(HSFLOWD_VERSION)*
	@ rm -vf $(HSFLOWD_STAMP)

#-------------------------------------------------------------------------------
#
#
# cl-persistify
#

CLPERSISTIFY_VERSION                    = 0.1.0
CLPERSISTIFY_CLVERSION_EXT              = cl2.5+1
CLPERSISTIFY_CUMULUS_VERSION    = $(CLPERSISTIFY_VERSION)-$(CLPERSISTIFY_CLVERSION_EXT)
CLPERSISTIFYDIR         = $(PACKAGESDIR)/cl-persistify-$(CLPERSISTIFY_VERSION)

CLPERSISTIFY_SOURCE_STAMP       = $(STAMPDIR)/cl-persistify-source
CLPERSISTIFY_BUILD_STAMP        = $(STAMPDIR)/cl-persistify-build
CLPERSISTIFY_STAMP                      = $(CLPERSISTIFY_SOURCE_STAMP) \
                                                          $(CLPERSISTIFY_BUILD_STAMP)

CLPERSISTIFY_DEB                = $(PACKAGESDIR)/cl-persistify_$(CLPERSISTIFY_CUMULUS_VERSION)_all.deb

PHONY += cl-persistify cl-persistify-source cl-persistify-build cl-persistify-clean

#---

PACKAGES1 += $(CLPERSISTIFY_STAMP)
cl-persistify: $(CLPERSISTIFY_STAMP)

#---

ifndef MAKE_CLEAN
CLPERSISTIFYNEW = $(shell test -d $(PKGSRCDIR)/cl-persistify  && test -f $(CLPERSISTIFY_SOURCE_STAMP) && \
                    find -L $(PKGSRCDIR)/cl-persistify -type f \
                        -newer $(CLPERSISTIFY_SOURCE_STAMP) -print -quit)
endif

cl-persistify-source: $(CLPERSISTIFY_SOURCE_STAMP)
$(CLPERSISTIFY_SOURCE_STAMP): $(TREE_STAMP) $(CLPERSISTIFYNEW)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting cl-persistify ===="
	@ rm -rf $(PACKAGESDIR)/cl-persistify
	cp -R $(PKGSRCDIR)/cl-persistify $(PACKAGESDIR)/cl-persistify-$(CLPERSISTIFY_VERSION)
	@ touch $@

#---

cl-persistify-build: $(CLPERSISTIFY_BUILD_STAMP)
$(CLPERSISTIFY_BUILD_STAMP): $(SB2_STAMP) $(CLPERSISTIFY_SOURCE_STAMP) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building cl-persistify-$(CLPERSISTIFY_VERSION) ===="
	@ $(call deb_build_fnc,$(CLPERSISTIFYDIR), \
	SYSROOTDIR=$(SYSROOTDIR) TOPDIR=$(TOPDIR))
	@mv $(PACKAGESDIR)/cl-persistify_$(CLPERSISTIFY_VERSION)_all.deb $(CLPERSISTIFY_DEB)
	@mv $(CLPERSISTIFY_DEB) $(PACKAGESDIR_TESTING)
	@ touch $@


#---

PACKAGES_CLEAN += cl-persistify-clean
cl-persistify-clean:
	@ rm -rf $(PACKAGESDIR)/cl-persistify
	@ rm -vf $(CLPERSISTIFY_DEB)
	rm -vf $(PACKAGESDIR_TESTING)/cl-persistify*
	@ rm -vf $(CLPERSISTIFY_STAMP)


#-------------------------------------------------------------------------------
#
# rdnbrd
#
#---
RDNBRD_VERSION	= 1.0
RDNBRD_CLVERSION_EXT	= cl2.1+1
RDNBRD_CUMULUS_VERSION= $(RDNBRD_VERSION)-$(RDNBRD_CLVERSION_EXT)
RDNBRDDIR		= $(PACKAGESDIR)/rdnbrd-$(RDNBRD_VERSION)

RDNBRD_SOURCE_STAMP	= $(STAMPDIR)/rdnbrd-source
RDNBRD_BUILD_STAMP	= $(STAMPDIR)/rdnbrd-build
RDNBRD_STAMP		= $(RDNBRD_SOURCE_STAMP) \
			  $(RDNBRD_BUILD_STAMP)

RDNBRD_DEB		= $(PACKAGESDIR)/python-rdnbrd_$(RDNBRD_CUMULUS_VERSION)_all.deb

PHONY += rdnbrd rdnbrd-source rdnbrd-build rdnbrd-clean

#---

PACKAGES1 += $(RDNBRD_STAMP)
rdnbrd: $(RDNBRD_STAMP)

#---

ifndef MAKE_CLEAN
RDNBRDNEW = $(shell test -d $(PKGSRCDIR)/rdnbrd  && test -f $(RDNBRD_SOURCE_STAMP) && \
				find -L $(PKGSRCDIR)/rdnbrd -type f \
			-newer $(RDNBRD_SOURCE_STAMP) -print -quit)
endif

rdnbrd-source: $(RDNBRD_SOURCE_STAMP)
$(RDNBRD_SOURCE_STAMP): $(TREE_STAMP) $(RDNBRDNEW)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting rdnbrd ===="
	@ rm -rf $(RDNBRDDIR)
	cp -R $(PKGSRCDIR)/rdnbrd $(RDNBRDDIR)
	cd $(RDNBRDDIR) && ./scripts/genmanpages.sh ./rst ./man
	@ touch $@

#---

rdnbrd-build: $(RDNBRD_BUILD_STAMP)
$(RDNBRD_BUILD_STAMP): $(SB2_STAMP) $(RDNBRD_SOURCE_STAMP) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building rdnbrd-$(RDNBRD_VERSION) ===="
	cd $(RDNBRDDIR) && python setup.py --command-packages=stdeb.command sdist_dsc --debian-version $(RDNBRD_CLVERSION_EXT) bdist_deb
	# Everything in PACKAGESDIR goes to main repo. This one goes
	# into testing
	mv $(RDNBRDDIR)/deb_dist/python-rdnbrd_$(RDNBRD_CUMULUS_VERSION)_all.deb $(PACKAGESDIR_TESTING)
	@ touch $@

#---

# Not built into image.  Must get with APT
#PACKAGES1_INSTALL_DEBS += $(RDNBRD_DEB)

#---

PACKAGES_CLEAN += rdnbrd-clean
rdnbrd-clean:
	@ rm -rf $(RDNBRDDIR)
	@ rm -vf $(RDNBRD_DEB)
	@ rm -vf $(RDNBRD_STAMP)


#-------------------------------------------------------------------------------
#
# python-docopt
#

# The .deb is in upstream dir.  Nothing to build.  Just copy it here
# so it gets included in the repo.  Can easily include in the image
# too if that becomes necessary.

PYTHON-DOCOPT_VERSION		= 0.6.1
PYTHON-DOCOPT_DEBIAN_VERSION	= $(PYTHON-DOCOPT_VERSION)-1
PYTHON-DOCOPT_UPSTREAM		= $(UPSTREAMDIR)/python-docopt_$(PYTHON-DOCOPT_DEBIAN_VERSION)_all.deb

PYTHON-DOCOPT_BUILD_STAMP	= $(STAMPDIR)/python-docopt-build
PYTHON-DOCOPT_STAMP		= $(PYTHON-DOCOPT_BUILD_STAMP)

PYTHON-DOCOPT_DEB		= $(PACKAGESDIR)/python-docopt_$(PYTHON-DOCOPT_DEBIAN_VERSION)_all.deb

PHONY += python-docopt python-docopt-build python-docopt-clean

#---

PACKAGES1 += $(PYTHON-DOCOPT_STAMP)
# Uncomment the next line if you want to install the deb into the image
#PACKAGES1_INSTALL_DEBS += $(PYTHON-DOCOPT_DEB)

#---

python-docopt: $(PYTHON-DOCOPT_STAMP)

python-docopt-build: $(PYTHON-DOCOPT_BUILD_STAMP)
$(PYTHON-DOCOPT_BUILD_STAMP): $(TREE_STAMP) $(PYTHON-DOCOPT_UPSTREAM)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Copying python-docopt-$(PYTHON-DOCOPT_VERSION) ===="
	cp $(PYTHON-DOCOPT_UPSTREAM) $(PACKAGESDIR)
	@ touch $@


PACKAGES_CLEAN += python-docopt-clean
python-docopt-clean:
	@ rm -f $(PYTHON-DOCOPT_DEB)
	rm -vf $(PYTHON-DOCOPT_STAMP)

#-------------------------------------------------------------------------------
#
# python-tabulate
#
#---
PYTHON-TABULATE_VERSION        = 0.7.4
PYTHON-TABULATE_EXTRA_VERSION  = 1+cl2.5+1
PYTHON-TABULATE_CLVERSION      = $(PYTHON-TABULATE_VERSION)-$(PYTHON-TABULATE_EXTRA_VERSION)
PYTHON-TABULATE_DISTRO         = cl2.5
PYHTON-TABULATE_MAINTAINER     = Cumulus Networks <support@cumulusnetworks.com>
PYTHON-TABULATE_UPSTREAM       = \
           $(UPSTREAMDIR)/python-tabulate-$(PYTHON-TABULATE_VERSION).tar.gz
PYTHON-TABULATE_DIR            = \
           $(PACKAGESDIR)/tabulate-$(PYTHON-TABULATE_VERSION)
PYTHON-TABULATE_SOURCE_STAMP   = $(STAMPDIR)/python-tabulate-source
PYTHON-TABULATE_PATCH_STAMP    = $(STAMPDIR)/python-tabulate-patch
PYTHON-TABULATE_BUILD_STAMP    = $(STAMPDIR)/python-tabulate-build
PYTHON-TABULATE_STAMP          = $(PYTHON-TABULATE_SOURCE_STAMP) \
                                 $(PYTHON-TABULATE_PATCH_STAMP) \
                                 $(PYTHON-TABULATE_BUILD_STAMP)

PYTHON-TABULATE_DEB            = \
           $(PACKAGESDIR_ADDONS)/python-tabulate_$(PYTHON-TABULATE_CLVERSION)_all.deb

PHONY += python-tabulate python-tabulate-source python-tabulate-patch \
         python-tabulate-build  python-tabulate-clean

#---

SOURCE += $(PYTHON-TABULATE_SOURCE_STAMP)
PACKAGES1 += $(PYTHON-TABULATE_STAMP)
PACKAGES1_INSTALL_DEBS += $(PYTHON-TABULATE_DEB)
python-tabulate: $(PYTHON-TABULATE_STAMP)

#---

ifndef MAKE_CLEAN
PYTHON-TABULATE_NEW = $(shell test \
            -d $(PYTHON-TABULATE_DIR) && \
        test -f $(PYTHON-TABULATE_SOURCE_STAMP) && \
	    find -L $(PYTHON-TABULATE_DIR) \
            -type f -newer $(PYTHON-TABULATE_SOURCE_STAMP) -print -quit)
endif

python-tabulate-source: $(PYTHON-TABULATE_SOURCE_STAMP)
$(PYTHON-TABULATE_SOURCE_STAMP): $(TREE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Getting python-tabulate ===="
	@ rm -rf $(PYTHON-TABULATE_DIR)
	@ tar -zxf $(PYTHON-TABULATE_UPSTREAM) -C $(PACKAGESDIR)
	@ rm -f $(PYTHON-TABULATE_DIR)/README
	@ mv $(PYTHON-TABULATE_DIR)/README.rst $(PYTHON-TABULATE_DIR)/README
	@ touch $@

#---

python-tabulate-patch: $(PYTHON-TABULATE_PATCH_STAMP)
$(PYTHON-TABULATE_PATCH_STAMP): $(PYTHON-TABULATE_SOURCE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Patching $(PYTHON-TABULATE_DIR) ===="
	cd $(PYTHON-TABULATE_DIR) && \
		$(SCRIPTDIR)/apply-patch-series $(PATCHDIR)/python-tabulate/series \
		$(PYTHON-TABULATE_DIR) --quilt
	@ touch $@

#---

python-tabulate-build: $(PYTHON-TABULATE_BUILD_STAMP)
$(PYTHON-TABULATE_BUILD_STAMP): $(PYTHON-TABULATE_PATCH_STAMP) $(BASE_STAMP) \
					$(PYTHON-TABULATE_NEW)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building python-tabulate-$(PYTHON-TABULATE_VERSION) ===="
	cd $(PYTHON-TABULATE_DIR) && python setup.py \
		--command-packages=stdeb.command sdist_dsc \
		--suite "$(PYTHON-TABULATE_DISTRO)" \
		--maintainer "$(PYHTON-TABULATE_MAINTAINER)" \
		--debian-version $(PYTHON-TABULATE_EXTRA_VERSION)
	cd $(PYTHON-TABULATE_DIR)/deb_dist/tabulate-$(PYTHON-TABULATE_VERSION) && dpkg-buildpackage -us -uc
	mv $(PYTHON-TABULATE_DIR)/deb_dist/python-tabulate*.deb $(PYTHON-TABULATE_DEB)
	@ touch $@

#---

PACKAGES_CLEAN += python-tabulate-clean

python-tabulate-clean:
	@ rm -rf $(PYTHON-TABULATE_DIR)
	@ rm -vf $(PYTHON-TABULATE_DEB)
	@ rm -vf $(PYTHON-TABULATE_STAMP)

#---------
#
# package vxfld
#

VXFLD_VERSION		= 1.1
VXFLD_CUMULUS_VERSION	= $(VXFLD_VERSION)-cl2.5+3
VXFLD_DIR		= $(PACKAGESDIR)/vxfld-$(VXFLD_VERSION)
VXFLDREQDIRS		=

VXFLD_SOURCE_STAMP	= $(STAMPDIR)/vxfld-source
VXFLD_PATCH_STAMP	= $(STAMPDIR)/vxfld-patch
VXFLD_BUILD_STAMP	= $(STAMPDIR)/vxfld-build
VXFLD_STAMP		= $(VXFLD_SOURCE_STAMP) \
			  $(VXFLD_PATCH_STAMP) \
			  $(VXFLD_BUILD_STAMP)

VXFLD_DEBS	= $(PACKAGESDIR)/vxfld-common_$(VXFLD_CUMULUS_VERSION)_all.deb
VXFLD_DEBS	+= $(PACKAGESDIR)/vxsnd_$(VXFLD_CUMULUS_VERSION)_all.deb
VXFLD_DEBS	+= $(PACKAGESDIR)/vxrd_$(VXFLD_CUMULUS_VERSION)_all.deb

PHONY += vxfld vxfld-source vxfld-patch vxfld-build vxfld-clean
#---

PACKAGES1 += $(VXFLD_STAMP)
# Not built into image.  Must get with APT
#PACKAGES1_INSTALL_DEBS += $(VXFLD_DEBS)

vxfld: $(VXFLD_STAMP)

#---

VXFLD_SOURCE_DIR = $(realpath ../packages/vxfld/)

ifndef MAKE_CLEAN
VXFLDNEW = $(shell test -d $(VXFLD_SOURCE_DIR) && test -f \
	$(VXFLD_SOURCE_STAMP) && find -L $(VXFLD_SOURCE_DIR) \
	$(VXFLDREQDIRS) -type f -newer $(VXFLD_SOURCE_STAMP) -print -quit)
endif

vxfld-source: $(VXFLD_SOURCE_STAMP)
$(VXFLD_SOURCE_STAMP): $(VXFLDNEW) $(TREE_STAMP)
	@ echo "==== Setting up vxfld package source ===="
	@ rm -rf $(PACKAGESDIR)/vxfld-* $(PACKAGESDIR)/vxfld_*
	@ cp -ar $(VXFLD_SOURCE_DIR) $(VXFLD_DIR)
	@ echo "Exclude residual pyc files in src tree (hidden by .gitignore)"
	@ find $(VXFLD_DIR) -name '*.pyc' -exec rm '{}' \;
	@ cd $(PACKAGESDIR) && tar -czf vxfld_$(VXFLD_VERSION).orig.tar.gz \
		--exclude='debian' vxfld-$(VXFLD_VERSION)
	@ touch $@

vxfld-patch: $(VXFLD_PATCH_STAMP)
$(VXFLD_PATCH_STAMP): $(VXFLD_SOURCE_STAMP)
	@ (cd $(VXFLD_DIR) && debchange -v $(VXFLD_CUMULUS_VERSION) \
	     -D $(DISTRO_NAME) --force-distribution "Re-version for release")
	@ touch $@

#---

vxfld-build: $(VXFLD_BUILD_STAMP)
$(VXFLD_BUILD_STAMP): $(VXFLD_PATCH_STAMP) $(VXFLDNEW) $(SB2_STAMP)
	@ rm -f && eval $(PROFILE_STAMP)
	@ echo "==== Building vxfld-$(VXFLD_VERSION) ===="
	@ $(call deb_build_fnc,$(VXFLD_DIR),\
		SYSROOTDIR=$(SYSROOTDIR) TOPDIR=$(TOPDIR))
	@ touch $@

#---

PACKAGES_CLEAN += vxfld-clean
vxfld-clean:
	@ rm -rf $(PACKAGESDIR)/vxfld*
	@ rm -vf $(VXFLD_STAMP)
	@ rm -f $(VXFLD_DEBS)


#-------------------------------------------------------------------------------
#
# mgmtmrf
#
#---
MGMTMRF_VERSION	= 0.1
MGMTMRF_CUMULUS_VERSION= $(MGMTMRF_VERSION)-$(MGMTMRF_VERSION)
MGMTMRF_DIR		= $(PACKAGESDIR)/cl-mgmtmrf-$(MGMTMRF_VERSION)

MGMTMRF_SOURCE_STAMP	= $(STAMPDIR)/cl-mgmtmrf-source
MGMTMRF_BUILD_STAMP	= $(STAMPDIR)/cl-mgmtmrf-build
MGMTMRF_STAMP		= $(MGMTMRF_SOURCE_STAMP) \
			  $(MGMTMRF_BUILD_STAMP)

MGMTMRF_DEB		= $(PACKAGESDIR)/cl-mgmtmrf_$(MGMTMRF_VERSION)_all.deb

PHONY += mgmtmrf mgmtmrf-source mgmtmrf-build mgmtmrf-clean

#---

PACKAGES1 += $(MGMTMRF_STAMP)
mgmtmrf: $(MGMTMRF_STAMP)

#---

ifndef MAKE_CLEAN
MGMTMRFNEW = $(shell test -d $(PKGSRCDIR)/mgmtmrf  && test -f $(MGMTMRF_SOURCE_STAMP) && \
				find -L $(PKGSRCDIR)/mgmtmrf -type f \
			-newer $(MGMTMRF_SOURCE_STAMP) -print -quit)
endif

mgmtmrf-source: $(MGMTMRF_SOURCE_STAMP)
$(MGMTMRF_SOURCE_STAMP): $(TREE_STAMP) $(MGMTMRFNEW)
	@ rm -f $@ && eval  $(PROFILE_STAMP)
	@ echo "==== Getting mgmtmrf ===="
	@ rm -rf $(MGMTMRF_DIR)
	cp -ar $(PKGSRCDIR)/cl-mgmtmrf $(MGMTMRF_DIR)
	cd $(MGMTMRF_DIR) && ./scripts/genmanpages.sh ./rst ./man
	@ touch $@

#---

mgmtmrf-build: $(MGMTMRF_BUILD_STAMP)
$(MGMTMRF_BUILD_STAMP): $(MGMTMRF_SOURCE_STAMP) $(MGMTMRF_NEW) \
		$(SB2_STAMP) $(BASE_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "====  Building cl-mgmtmrf-$(MGMTMRF_VERSION) ===="
	$(call deb_build_fnc,$(MGMTMRF_DIR),\
		LSB_RELEASE_TAG="$(LSB_RELEASE_TAG)" \
		RELEASE_VERSION="$(RELEASE_VERSION)")
	@ touch $@

#---

# Not built into image.  Must get with APT
#PACKAGES1_INSTALL_DEBS += $(MGMTMRF_DEB)

#---

PACKAGES_CLEAN += mgmtmrf-clean
mgmtmrf-clean:
	@ rm -rf $(MGMTMRF_DIR)
	@ rm -vf $(MGMTMRF_DEB)
	@ rm -vf $(MGMTMRF_STAMP)


#-------------------------------------------------------------------------------
#
# packages1 aggregate
#

PACKAGES1_INSTALL_STAMP = $(STAMPDIR)/packages1-install
PACKAGES1_INSTALL = $(PACKAGES1_INSTALL_STAMP)

PHONY += packages1-install

#---

packages1: $(PACKAGES1)
	@ echo 'All packages1 are up to date'


packages1-install: $(PACKAGES1_INSTALL_STAMP)
$(PACKAGES1_INSTALL_STAMP): $(PACKAGES1) $(BASEINIT_STAMP)
	@ rm -f $@ && eval $(PROFILE_STAMP)
	@ echo "==== Unpack packages in $(SYSROOTDIR) ===="
	cd $(PACKAGESDIR) && \
		sudo $(SCRIPTDIR)/dpkg-unpack --force \
		--aptconf=$(BUILDDIR)/apt.conf $(PACKAGES1_INSTALL_DEBS)
	# Copy into sysroot the multi-arch debs
	cd $(PACKAGESDIR) && \
	    cp $(PACKAGES1_INSTALL_MADEBS) $(SYSROOTDIR)/tmp
	@ echo "==== Configure packages in $(SYSROOTDIR) ===="
	sudo $(SCRIPTDIR)/qemu-runscript $(QEMUBIN) $(SYSROOTDIR) sysroot-config 
	@ touch $@

#-------------------------------------------------------------------------------
#
# Local Variables:
# mode: makefile-gmake
# End:
