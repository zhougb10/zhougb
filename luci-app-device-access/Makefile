#
# Copyright (C) 2026 zhougb10
#
# This is free software, licensed under the GPL v2.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-device-access
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_LICENSE:=GPL-2.0
PKG_MAINTAINER:=zhougb10 <zhougb10@users.noreply.github.com>

LUCI_TITLE:=Device Access Control - Per-device domain access control
LUCI_DESCRIPTION:=Control whether a LAN device can access specific websites using dnsmasq nftset + nftables
LUCI_DEPENDS:=+dnsmasq-full +nftables +luci-base
LUCI_PKGARCH:=all

include $(INCLUDE_DIR)/package.mk
include ../../luci.mk

define Package/luci-app-device-access/conffiles
/etc/config/device_access
endef

define Build/Configure
endef

define Build/Compile
endef

$(eval $(call BuildPackage,luci-app-device-access))