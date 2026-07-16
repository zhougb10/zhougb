#!/bin/sh
# Device Access Control - 规则应用引擎
# 读取 UCI 规则，生成 dnsmasq nftset 配置，创建 nftables 规则

set -e

NIKKI_TABLE="inet nikki"
DAC_TABLE="inet device_access"
FW4_TABLE="inet fw4"
DAC_RULES_DIR="/tmp/device-access"
DAC_DNSMASQ_CONF="/tmp/device-access/dnsmasq.conf"
DAC_NFTABLES_SCRIPT="/tmp/device-access/nftables.rules"
DAC_NFTABLES_SET="/tmp/device-access/nftables_set"

# 收集所有规则
rules=""
rule_count=0

# 遍历 UCI 规则
config_cb() {
    local type="$1"
    local name="$2"
    if [ "$type" = "rule" ]; then
        local enabled device_ip domain action desc
        config_get enabled "$name" "enabled" 0
        [ "$enabled" != "1" ] && return

        config_get device_ip "$name" "device_ip" ""
        config_get domain "$name" "domain" ""
        config_get action "$name" "action" "block"

        [ -z "$device_ip" ] && return
        [ -z "$domain" ] && return

        # 移除通配符前缀 (*.)
        domain="${domain#\*.}"

        # 生成唯一的 nftset 名称
        set_name="dac_$(echo "${device_ip}_${domain}" | md5sum | cut -c1-12)"

        rule_count=$((rule_count + 1))
        rules="$rules
${device_ip}|${domain}|${action}|${set_name}"
    fi
}

# 读取 UCI 配置
. /lib/functions.sh
config_load device_access

config_get_bool enabled device_rules enabled 0
if [ "$enabled" != "1" ]; then
    echo "device_access: 未启用，跳过"
    exit 0
fi

config_foreach config_cb rule

if [ $rule_count -eq 0 ]; then
    echo "device_access: 没有启用的规则"
    exit 0
fi

# 创建临时目录
mkdir -p "$DAC_RULES_DIR"

# === 1. 生成 dnsmasq nftset 配置 ===
# dnsmasq 解析域名后自动将 IP 加入 nftables set
: > "$DAC_DNSMASQ_CONF"

echo "$rules" | while IFS='|' read -r device_ip domain action set_name; do
    [ -z "$device_ip" ] && continue

    if [ "$action" = "block" ]; then
        # Block: 域名解析的 IP 加入 block set
        # 格式: nftset=/domain/4#inet#device_access#set_name
        echo "nftset=/${domain}/4#inet#device_access#${set_name}_v4" >> "$DAC_DNSMASQ_CONF"
        echo "nftset=/${domain}/6#inet#device_access#${set_name}_v6" >> "$DAC_DNSMASQ_CONF"
    else
        # Allow: 域名解析的 IP 加入 allow set
        echo "nftset=/${domain}/4#inet#device_access#${set_name}_allow_v4" >> "$DAC_DNSMASQ_CONF"
        echo "nftset=/${domain}/6#inet#device_access#${set_name}_allow_v6" >> "$DAC_DNSMASQ_CONF"
    fi
done

# === 2. 生成 nftables 规则 ===
: > "$DAC_NFTABLES_SCRIPT"

cat >> "$DAC_NFTABLES_SCRIPT" << 'NFTEOF'
# Device Access Control - nftables 规则
# 由 apply.sh 自动生成，不要手动编辑

delete table inet device_access 2>/dev/null || true
table inet device_access {
    # 集合将在下方动态定义
NFTEOF

echo "$rules" | while IFS='|' read -r device_ip domain action set_name; do
    [ -z "$device_ip" ] && continue

    if [ "$action" = "block" ]; then
        cat >> "$DAC_NFTABLES_SCRIPT" << SETEOF

    # Block: ${device_ip} -> ${domain}
    set ${set_name}_v4 {
        type ipv4_addr
        flags dynamic,interval,timeout
        auto-merge
        timeout 12h
    }
    set ${set_name}_v6 {
        type ipv6_addr
        flags dynamic,interval,timeout
        auto-merge
        timeout 12h
    }
SETEOF
    else
        cat >> "$DAC_NFTABLES_SCRIPT" << SETEOF

    # Allow: ${device_ip} -> ${domain}
    set ${set_name}_allow_v4 {
        type ipv4_addr
        flags dynamic,interval,timeout
        auto-merge
        timeout 12h
    }
    set ${set_name}_allow_v6 {
        type ipv6_addr
        flags dynamic,interval,timeout
        auto-merge
        timeout 12h
    }
SETEOF
    fi
done

# === 3. 添加规则链 ===
cat >> "$DAC_NFTABLES_SCRIPT" << 'CHAINEOF'

    chain forward_block {
        type filter hook forward priority filter + 1; policy accept;
CHAINEOF

echo "$rules" | while IFS='|' read -r device_ip domain action set_name; do
    [ -z "$device_ip" ] && continue

    if [ "$action" = "block" ]; then
        cat >> "$DAC_NFTABLES_SCRIPT" << RULEEOF
        ip saddr ${device_ip} ip daddr @${set_name}_v4 drop comment "block:${device_ip}->${domain}"
        ip6 saddr ${device_ip} ip6 daddr @${set_name}_v6 drop comment "block:${device_ip}->${domain}"
RULEEOF
    fi
done

cat >> "$DAC_NFTABLES_SCRIPT" << 'CHAINEOF'
    }

    chain forward_allow {
        type filter hook forward priority filter + 2; policy accept;
CHAINEOF

echo "$rules" | while IFS='|' read -r device_ip domain action set_name; do
    [ -z "$device_ip" ] && continue

    if [ "$action" = "allow" ]; then
        cat >> "$DAC_NFTABLES_SCRIPT" << RULEEOF
        ip saddr ${device_ip} ip daddr @${set_name}_allow_v4 accept comment "allow:${device_ip}->${domain}"
        ip6 saddr ${device_ip} ip6 daddr @${set_name}_allow_v6 accept comment "allow:${device_ip}->${domain}"
RULEEOF
    fi
done

echo "    }
}" >> "$DAC_NFTABLES_SCRIPT"

# === 4. 应用规则 ===

# 检查 dnsmasq 是否支持 nftset
if ! dnsmasq --version 2>/dev/null | grep -q nftset; then
    echo "ERROR: dnsmasq 不支持 nftset，请安装 dnsmasq-full" >&2
    exit 1
fi

# 应用 nftables 规则
nft -f "$DAC_NFTABLES_SCRIPT" 2>&1 | logger -t device-access

# 配置 dnsmasq 加载 nftset 配置
# 创建 include 目录
mkdir -p /tmp/dnsmasq.d
cp "$DAC_DNSMASQ_CONF" /tmp/dnsmasq.d/device-access-nftset.conf

# 重启 dnsmasq 以加载新配置
/etc/init.d/dnsmasq reload 2>/dev/null || /etc/init.d/dnsmasq restart 2>/dev/null

logger -t device-access "已应用 ${rule_count} 条规则"
echo "device_access: 已应用 ${rule_count} 条规则"