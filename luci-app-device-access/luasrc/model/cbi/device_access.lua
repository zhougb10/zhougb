--[[
LuCI model for Device Access Control
luci-app-device-access
]]--

local m, s, o

m = Map("device_access", translate("设备访问控制"),
    translate("按设备粒度控制局域网设备能否访问特定网站。") ..
    translate("规则通过 dnsmasq nftset + nftables 实现，支持基于域名的 allow/block。"))

-- 全局开关
s = m:section(TypedSection, "device", "device_rules",
    translate("全局开关"))
s.anonymous = true

o = s:option(Flag, "enabled", translate("启用"))
o.rmempty = false
o.default = "0"
o.description = translate("启用后系统启动时自动应用规则")

-- 规则列表
s = m:section(TypedSection, "rule", translate("访问规则"),
    translate("每条规则定义：哪个设备的流量、去哪个域名、允许还是禁止。"))
s.anonymous = true
s.addremove = true
s.template = "cbi/tblsection"

o = s:option(Flag, "enabled", translate("启用"))
o.default = "1"
o.rmempty = false

o = s:option(Value, "device_ip", translate("设备IP"))
o.datatype = "ipaddr"
o.rmempty = false
o.description = translate("局域网设备的 IP 地址，如 192.168.0.226")

o = s:option(Value, "domain", translate("域名"))
o.rmempty = false
o.description = translate("要控制的域名，如 facebook.com 或 *.facebook.com")

o = s:option(ListValue, "action", translate("动作"))
o:value("block", translate("禁止访问"))
o:value("allow", translate("允许访问"))
o.default = "block"

o = s:option(Value, "description", translate("备注"))
o.rmempty = true

-- 操作按钮
s = m:section(TypedSection, "device", "device_rules")
s.anonymous = true

o = s:option(Button, "_apply")
o.inputtitle = translate("应用规则")
o.inputstyle = "apply"
o.write = function()
    luci.sys.call("/usr/share/device-access/apply.sh 2>&1 >/dev/null")
end

o = s:option(Button, "_stop")
o.inputtitle = translate("停止/清理")
o.inputstyle = "reset"
o.write = function()
    luci.sys.call("/usr/share/device-access/cleanup.sh 2>&1 >/dev/null")
end

return m