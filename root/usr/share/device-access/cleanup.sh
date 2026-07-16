#!/bin/sh
# Device Access Control - 清理规则

# 删除 nftables 表
nft delete table inet device_access 2>/dev/null || true

# 删除 dnsmasq 配置
rm -f /tmp/dnsmasq.d/device-access-nftset.conf

# 重启 dnsmasq
/etc/init.d/dnsmasq reload 2>/dev/null || true

logger -t device-access "规则已清理"