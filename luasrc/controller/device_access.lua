module("luci.controller.device_access", package.seeall)

function index()
    entry({"admin", "services", "device_access"}, cbi("device_access"), _("设备访问控制"), 90)
    entry({"admin", "services", "device_access", "apply"}, call("action_apply"), nil)
    entry({"admin", "services", "device_access", "stop"}, call("action_stop"), nil)
    entry({"admin", "services", "device_access", "status"}, call("action_status"), nil)
end

function action_apply()
    local uci = require("luci.model.uci").cursor()
    local enabled = uci:get("device_access", "device_rules", "enabled") or "0"

    if enabled == "1" then
        luci.sys.call("/usr/share/device-access/apply.sh 2>&1")
    end

    luci.http.redirect(luci.dispatcher.build_url("admin/services/device_access"))
end

function action_stop()
    luci.sys.call("/usr/share/device-access/cleanup.sh 2>&1")
    luci.http.redirect(luci.dispatcher.build_url("admin/services/device_access"))
end

function action_status()
    local uci = require("luci.model.uci").cursor()
    local enabled = uci:get("device_access", "device_rules", "enabled") or "0"

    local status = {}
    status.enabled = (enabled == "1")

    -- 检查 nftables 表是否存在
    local rv = luci.sys.call("nft list table inet device_access >/dev/null 2>&1")
    status.nftables_active = (rv == 0)

    -- 统计规则数
    local rules = {}
    uci:foreach("device_access", "rule", function(s)
        if s[".name"] then
            table.insert(rules, {
                id = s[".name"],
                device_ip = s.device_ip or "",
                domain = s.domain or "",
                action = s.action or "block",
                enabled = s.enabled or "0",
                description = s.description or ""
            })
        end
    end)
    status.rule_count = #rules
    status.rules = rules

    luci.http.prepare_content("application/json")
    luci.http.write_json(status)
end