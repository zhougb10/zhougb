--[[
LuCI model for Device Access Control
luci-app-device-access v2.0
内置常用网站/应用域名库 + 自定义域名支持
]]--

local m, s, o
local sys = require "luci.sys"
local util = require "luci.util"
local fs = require "nixio.fs"

-- 加载内置网站库
local websites = {}
local websites_file = "/usr/share/device-access/websites.list"

if fs.access(websites_file) then
    for line in io.lines(websites_file) do
        if line and not line:match("^#") and line ~= "" then
            local category, key, name, domains = line:match("^([^|]+)|([^|]+)|([^|]+)|(.+)")
            if category and key and name and domains then
                if not websites[category] then
                    websites[category] = {}
                end
                websites[category][key] = {
                    name = name,
                    domains = domains
                }
            end
        end
    end
end

m = Map("device_access", translate("设备访问控制"),
    translate("按设备粒度控制局域网设备能否访问特定网站或应用。") ..
    translate("内置常用应用域名库，直接选择即可；也可自定义域名。"))

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
    translate("每条规则定义：哪个设备、控制哪个应用/网站、允许还是禁止。") ..
    translate("选择内置应用会自动覆盖对应的所有相关域名。") ..
    translate("微信已拆分为「微信本体」和「微信小程序」两项，可分别控制——例如只禁止小程序但保留聊天。"))
s.addremove = true
s.anonymous = true
s.template = "cbi/tblsection"

o = s:option(Flag, "enabled", translate("启用"))
o.default = "1"
o.rmempty = false

o = s:option(Value, "device_ip", translate("设备IP"))
o.datatype = "ipaddr"
o.rmempty = false
o.description = translate("局域网设备 IP，如 192.168.0.226")

-- 应用/网站选择（下拉框）
o = s:option(ListValue, "app", translate("应用/网站"))
o:value("", translate("-- 自定义域名 --"))
o.description = translate("选择内置应用，系统自动匹配所有相关域名。选「自定义」则手动填写域名。") ..
    translate("微信已拆分：选「微信本体」控制聊天/朋友圈/支付；选「微信小程序」单独控制小程序加载。")

-- 按分类输出选项
local category_order = {
    "社交", "视频", "购物", "音乐", "游戏",
    "新闻", "生活", "金融", "工具", "招聘", "下载"
}

for _, cat in ipairs(category_order) do
    if websites[cat] then
        local keys = {}
        for k in pairs(websites[cat]) do
            table.insert(keys, k)
        end
        table.sort(keys)
        for _, k in ipairs(keys) do
            o:value(k, cat .. " → " .. websites[cat][k].name)
        end
    end
end

-- 自定义域名输入
o = s:option(Value, "domain", translate("域名"))
o.description = translate("选内置应用时留空即可。自定义模式填写域名，多个用英文逗号分隔。")
o.rmempty = false
o:depends("app", "")

-- 动作
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