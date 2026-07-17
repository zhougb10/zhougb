#!/bin/sh
# Device Access Control - 规则应用引擎 v2.0
# 读取 UCI 规则，支持内置应用域名库和自定义域名
# 生成 dnsmasq nftset 配置，创建 nftables 规则

set -e

DAC_TABLE="inet device_access"
DAC_RULES_DIR="/tmp/device-access"
DAC_DNSMASQ_CONF="/tmp/device-access/dnsmasq.conf"
DAC_NFTABLES_SCRIPT="/tmp/device-access/nftables.rules"
WEBSITES_LIST="/usr/share/device-access/websites.list"

# 从 websites.list 查找应用对应的域名
# $1 = app key, 输出逗号分隔的域名列表
get_app_domains() {
    local app_key="$1"
    [ -z "$app_key" ] && return 0
    [ ! -f "$WEBSITES_LIST" ] && return 0

    while IFS='|' read -r cat key name domains; do
        [ "$key" = "$app_key" ] && echo "$domains" && return 0
    done < "$WEBSITES_LIST"
}

# 收集所有规则（格式: device_ip|domain_list|action|set_key）
# 一个规则可能对应多个域名（内置应用），每个域名生成独立的 nftset
all_entries=""
entry_count=0

config_cb() {
    local type="$1"
    local name="$2"
    if [ "$type" = "rule" ]; then
        local enabled device_ip app domain action
        config_get enabled "$name" "enabled" 0
        [ "$enabled" != "1" ] && return

        config_get device_ip "$name" "device_ip" ""
        config_get app "$name" "app" ""
        config_get domain "$name" "domain" ""
        config_get action "$name" "action" "block"

        [ -z "$device_ip" ] && return

        # 确定域名列表
        local domains=""
        if [ -n "$app" ]; then
            # 内置应用：从 websites.list 查找
            domains=$(get_app_domains "$app")
        fi
        if [ -z "$domains" ]; then
            # 自定义域名
            domains="$domain"
        fi

        [ -z "$domains" ] && return

        # 按逗号拆分域名，每个域名生成一条 nftset 条目
        local old_ifs="$IFS"
        IFS=','
        for d in $domains; do
            # trim 空格
            d=$(echo "$d" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            [ -z "$d" ] && continue
            # 移除通配符前缀
            d="${d#\*.}"
            # 生成 set 名称
            set_name="dac_$(echo "${device_ip}_${d}" | md5sum | cut -c1-12)"
            entry_count=$((entry_count + 1))
            all_entries="$all_entries
${device_ip}|${d}|${action}|${set_name}"
        done
        IFS="$old_ifs"
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

if [ $entry_count -eq 0 ]; then
    echo "device_access: 没有启用的规则"
    exit 0
fi

# 创建临时目录
mkdir -p "$DAC_RULES_DIR"

# === 1. 生成 dnsmasq nftset 配置 ===
: > "$DAC_DNSMASQ_CONF"

echo "$all_entries" | while IFS='|' read -r device_ip domain action set_name; do
    [ -z "$device_ip" ] && continue

    if [ "$action" = "block" ]; then
        echo "nftset=/${domain}/4#inet#device_access#${set_name}_v4" >> "$DAC_DNSMASQ_CONF"
        echo "nftset=/${domain}/6#inet#device_access#${set_name}_v6" >> "$DAC_DNSMASQ_CONF"
    else
        echo "nftset=/${domain}/4#inet#device_access#${set_name}_allow_v4" >> "$DAC_DNSMASQ_CONF"
        echo "nftset=/${domain}/6#inet#device_access#${set_name}_allow_v6" >> "$DAC_DNSMASQ_CONF"
    fi
done

# === 2. 生成 nftables 规则 ===
: > "$DAC_NFTABLES_SCRIPT"

cat >> "$DAC_NFTABLES_SCRIPT" << 'NFTEOF'
delete table inet device_access 2>/dev/null || true
table inet device_access {
NFTEOF

# 集合定义
echo "$all_entries" | while IFS='|' read -r device_ip domain action set_name; do
    [ -z "$device_ip" ] && continue

    local_suffix=""
    if [ "$action" = "allow" ]; then
        local_suffix="_allow"
    fi

    cat >> "$DAC_NFTABLES_SCRIPT" << SETEOF

    # ${action}: ${device_ip} -> ${domain}
    set ${set_name}${local_suffix}_v4 {
        type ipv4_addr
        flags dynamic,interval,timeout
        auto-merge
        timeout 12h
    }
    set ${set_name}${local_suffix}_v6 {
        type ipv6_addr
        flags dynamic,interval,timeout
        auto-merge
        timeout 12h
    }
SETEOF
done

# block 链
cat >> "$DAC_NFTABLES_SCRIPT" << 'CHAINEOF'

    chain forward_block {
        type filter hook forward priority filter + 1; policy accept;
CHAINEOF

echo "$all_entries" | while IFS='|' read -r device_ip domain action set_name; do
    [ -z "$device_ip" ] && continue
    [ "$action" = "block" ] || continue
    cat >> "$DAC_NFTABLES_SCRIPT" << RULEEOF
        ip saddr ${device_ip} ip daddr @${set_name}_v4 drop comment "block:${device_ip}->${domain}"
        ip6 saddr ${device_ip} ip6 daddr @${set_name}_v6 drop comment "block:${device_ip}->${domain}"
RULEEOF
done

echo "    }
" >> "$DAC_NFTABLES_SCRIPT"

# allow 链
cat >> "$DAC_NFTABLES_SCRIPT" << 'CHAINEOF'
    chain forward_allow {
        type filter hook forward priority filter + 2; policy accept;
CHAINEOF

echo "$all_entries" | while IFS='|' read -r device_ip domain action set_name; do
    [ -z "$device_ip" ] && continue
    [ "$action" = "allow" ] || continue
    cat >> "$DAC_NFTABLES_SCRIPT" << RULEEOF
        ip saddr ${device_ip} ip daddr @${set_name}_allow_v4 accept comment "allow:${device_ip}->${domain}"
        ip6 saddr ${device_ip} ip6 daddr @${set_name}_allow_v6 accept comment "allow:${device_ip}->${domain}"
RULEEOF
done

echo "    }
}" >> "$DAC_NFTABLES_SCRIPT"

# === 3. 应用 ===

# 检查 dnsmasq 是否支持 nftset
if ! dnsmasq --version 2>/dev/null | grep -q nftset; then
    echo "ERROR: dnsmasq 不支持 nftset，请安装 dnsmasq-full" >&2
    exit 1
fi

# 应用 nftables 规则
nft -f "$DAC_NFTABLES_SCRIPT" 2>&1 | logger -t device-access

# 配置 dnsmasq 加载 nftset 配置
mkdir -p /tmp/dnsmasq.d
cp "$DAC_DNSMASQ_CONF" /tmp/dnsmasq.d/device-access-nftset.conf

# 重启 dnsmasq 以加载新配置
/etc/init.d/dnsmasq reload 2>/dev/null || /etc/init.d/dnsmasq restart 2>/dev/null

logger -t device-access "已应用 ${entry_count} 条域名规则"
echo "device_access: 已应用 ${entry_count} 条域名规则"