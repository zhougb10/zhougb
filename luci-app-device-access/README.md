# luci-app-device-access

**设备访问控制** — 按设备粒度控制局域网设备能否访问特定网站或应用。

![version](https://img.shields.io/badge/version-2.0.0-brightgreen)
![license](https://img.shields.io/badge/license-GPLv2-blue)

## 功能

- ✅ **内置常用应用域名库** — 60+ 个应用/网站，覆盖社交、视频、购物、音乐、游戏、新闻、生活等
- ✅ **小程序域名覆盖** — 微信等应用自动包含小程序相关域名（如 `servicewechat.com`）
- ✅ **按设备 IP 控制** — 指定设备禁止或允许访问某个应用
- ✅ **自定义域名** — 内置库未覆盖时可手动输入域名，支持逗号分隔多个
- ✅ **动态 IP 解析** — 基于 dnsmasq nftset，域名解析到 IP 后自动加入 nftables 集合
- ✅ **两种动作** — 禁止访问（block）和 允许访问（allow）

## 内置应用库分类

| 分类 | 示例应用 |
|------|---------|
| 社交 | 微信本体（聊天/朋友圈/支付）、微信小程序（单独控制）、QQ、微博、钉钉、企业微信、小红书、Facebook、Twitter/X、Instagram、WhatsApp、Telegram |
| 视频 | 抖音、快手、哔哩哔哩、YouTube、爱奇艺、腾讯视频、优酷、西瓜视频、虎牙、斗鱼、芒果TV、Netflix |
| 购物 | 淘宝、天猫、京东、拼多多、唯品会、苏宁、美团、饿了么、得物 |
| 音乐 | 网易云音乐、QQ音乐、酷狗、酷我、喜马拉雅、全民K歌 |
| 游戏 | 王者荣耀、原神、和平精英、4399、7k7k、Steam、Epic、UU加速器 |
| 新闻 | 今日头条、知乎、百度、新浪、腾讯新闻 |
| 生活 | 大众点评、滴滴出行、高德地图、百度地图、携程、飞猪 |
| 金融 | 支付宝、银联、平安 |
| 工具 | 百度网盘、阿里云盘、迅雷、TeamViewer、ToDesk |
| 招聘 | BOSS直聘、智联、前程无忧、猎聘 |

## 工作原理

```
设备 → DNS 查询 (dnsmasq) → 解析域名 → nftset 自动将 IP 加入集合
                                                      ↓
设备 → 访问网站 → 路由器转发 (nftables) → 匹配源 IP + 目标 IP 集合 → 丢弃/放行
```

1. 用户在 LuCI 界面添加规则（设备 IP + 选择应用 或 自定义域名 + 动作）
2. 规则引擎查找应用对应的全部域名，生成 dnsmasq nftset 配置
3. dnsmasq 解析每个域名时自动将 IP 地址加入 nftables 集合
4. nftables 根据源 IP 和目标 IP 集合执行丢弃（block）或放行（allow）

## 依赖

- `dnsmasq-full`（需支持 nftset 编译选项）
- `nftables`
- `luci-base`

## 安装

```bash
# 从 ipk 安装
opkg install luci-app-device-access_2.0.0_all.ipk

# 或编译安装
make package/luci-app-device-access/compile V=s
```

## 使用

### Web 界面

1. 登录路由器 LuCI → **服务 → 设备访问控制**
2. 开启 **启用** 开关
3. 添加规则：
   - **设备IP**：如 `192.168.0.226`
   - **应用/网站**：从下拉框选择内置应用（如「社交 → 微信」）
   - 或选「自定义域名」，手动填写域名（逗号分隔多个）
   - **动作**：禁止访问 / 允许访问
4. 点击 **保存&应用**，然后点 **应用规则**

### 命令行

```bash
# 使用内置应用
uci set device_access.device_rules.enabled=1
uci add device_access rule
uci set device_access.@rule[-1].device_ip='192.168.0.226'
uci set device_access.@rule[-1].app='douyin'
uci set device_access.@rule[-1].action='block'
uci set device_access.@rule[-1].enabled='1'
uci commit device_access
/etc/init.d/device_access restart

# 自定义域名
uci add device_access rule
uci set device_access.@rule[-1].device_ip='192.168.0.50'
uci set device_access.@rule[-1].app=''
uci set device_access.@rule[-1].domain='github.com,stackoverflow.com'
uci set device_access.@rule[-1].action='allow'
uci set device_access.@rule[-1].enabled='1'
uci commit device_access
/etc/init.d/device_access restart
```

## 典型场景：能用微信但禁止小程序

微信已拆分为两个独立条目，可以分别控制：

```bash
# 只禁止某设备使用微信小程序，微信聊天/支付正常
uci add device_access rule
uci set device_access.@rule[-1].device_ip='192.168.0.226'
uci set device_access.@rule[-1].app='wechat_mini'
uci set device_access.@rule[-1].action='block'
uci set device_access.@rule[-1].enabled='1'
uci commit device_access
/etc/init.d/device_access restart
```

| 选项 | app 值 | 覆盖域名 | 效果 |
|------|--------|---------|------|
| 微信本体 | `wechat` | weixin.qq.com, wx.qq.com, res.wx.qq.com 等 | 聊天/朋友圈/支付 |
| 微信小程序 | `wechat_mini` | servicewechat.com | 小程序加载/运行 |

## 自定义域名库

域名库文件位于 `/usr/share/device-access/websites.list`，格式：

```
分类|唯一标识|显示名称|域名1,域名2,域名3
```

可自行添加或修改，重启 `device-access` 服务后生效。

## 许可证

GPL v2

## 作者

zhougb10