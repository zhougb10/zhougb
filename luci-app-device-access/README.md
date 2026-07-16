# luci-app-device-access

**设备访问控制** — 按设备粒度控制局域网设备能否访问特定网站。

![screenshot](https://img.shields.io/badge/OpenWRT-LuCI-brightgreen)
![license](https://img.shields.io/badge/license-GPLv2-blue)

## 功能

- ✅ **Web 管理界面**（LuCI）— 服务 → 设备访问控制
- ✅ **按设备 IP 控制** — 指定 192.168.0.50 禁止访问 facebook.com
- ✅ **域名级别控制** — 支持 `example.com` 和 `*.example.com`
- ✅ **支持两种动作** — 禁止访问（block）和 允许访问（allow）
- ✅ **动态 IP 解析** — 基于 dnsmasq nftset，域名解析到 IP 后自动加入 nftables 集合
- ✅ **无需手动更新 IP** — dnsmasq 自动处理域名解析和 IP 更新
- ✅ **命令行接口** — `device-access` 命令管理规则

## 工作原理

```
设备 → DNS 查询 (dnsmasq) → 解析域名 → nftset 自动将 IP 加入集合
                                                      ↓
设备 → 访问网站 → 路由器转发 (nftables) → 匹配源 IP + 目标 IP 集合 → 丢弃/放行
```

1. 用户在 LuCI 界面添加规则（设备 IP + 域名 + 动作）
2. 规则引擎生成 dnsmasq nftset 配置
3. dnsmasq 解析域名时自动将 IP 地址加入 nftables 集合
4. nftables 根据源 IP 和目标 IP 集合执行丢弃（block）或放行（allow）

## 依赖

- `dnsmasq-full`（需支持 nftset 编译选项）
- `nftables`
- `luci-base`

## 安装

### 方法一：从发布包安装

```bash
opkg install luci-app-device-access_1.0.0_all.ipk
```

### 方法二：编译安装

```bash
# 将源码放入 OpenWRT SDK 的 package/ 目录
make package/luci-app-device-access/compile V=s
```

## 使用

### Web 界面

1. 登录路由器 LuCI 管理页面
2. 进入 **服务 → 设备访问控制**
3. 开启 **启用** 开关
4. 添加规则：设备 IP、域名、动作（禁止/允许）
5. 点击 **保存&应用**

### 命令行

```bash
# 添加规则（禁止某设备访问某网站）
device-access add 192.168.0.226 facebook.com block

# 允许某设备访问某网站
device-access add 192.168.0.50 github.com allow

# 列出所有规则
device-access list

# 删除规则
device-access del <rule-id>

# 应用规则
device-access apply

# 查看状态
device-access status
```

## 配置示例

```bash
# UCI 配置
uci set device_access.device_rules.enabled=1
uci add device_access rule
uci set device_access.@rule[-1].device_ip='192.168.0.226'
uci set device_access.@rule[-1].domain='facebook.com'
uci set device_access.@rule[-1].action='block'
uci set device_access.@rule[-1].enabled='1'
uci commit device_access
/etc/init.d/device_access restart
```

## 许可证

GPL v2

## 作者

zhougb10