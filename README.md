# HE Tunnel Broker Manager

一个用于管理 Hurricane Electric Tunnel Broker IPv6 隧道的一键式交互管理工具。安装后输入 `he` 即可进入完整菜单，支持创建、删除、修改、状态查看、出口 IPv6 检测、连通性测试、DNS、MTU、IPv6 防火墙、systemd 开机自启、`/48` 到 `/64` 子网生成和脚本更新。

> 目标风格：类似 3x-ui、realm.sh、LiteNet 的交互式管理面板，而不是单次执行的一次性 Bash 脚本。

## 项目结构

```text
he-tunnel-manager/
├── install.sh
├── uninstall.sh
├── he.sh
├── config/
│   ├── config.example.conf
│   └── manager.example.conf
├── systemd/
│   └── he-tunnel.service
├── README.md
└── LICENSE
```

## 安装方式

一键安装：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ccqwertyui/he-tunnel-manager/main/install.sh)
```

备用安装方式：

```bash
wget -O install.sh https://raw.githubusercontent.com/ccqwertyui/he-tunnel-manager/main/install.sh
bash install.sh
```

安装完成后，系统会创建 `he` 命令，后续直接输入 `he` 即可进入交互式管理面板。

## 使用方式

安装完成后执行：

```bash
he
```

进入交互式菜单：

```text
=================================
HE Tunnel Broker Manager
=================================

当前隧道状态：已连接 / 未连接
当前出口模式：Routed /48
当前出口 IPv6：2001:470:f8e6:1::1
当前 MTU：1280
开机自启：已启用 / 未启用

1. 创建 HE 隧道
2. 删除 HE 隧道
3. 修改 HE 隧道
4. 查看隧道状态 / 当前配置
5. 查看出口 IPv6
6. 测试连通性
7. DNS 设置
8. MTU 设置
9. IPv6 防火墙
10. 开机自启管理
11. /48 IPv6 生成器
12. 更新脚本
13. 退出
```

## 创建隧道流程

选择 `1. 创建 HE 隧道` 后，脚本会逐项引导输入，不会一次性要求填写全部参数。输入框采用单行格式，直接在提示后输入即可：

```text
请输入 Tunnel Server IPv4：216.218.221.6
请输入 Tunnel Client IPv4：91.233.10.68
请输入 Tunnel Server IPv6：2001:470:18:171::1
请输入 Tunnel Client IPv6：2001:470:18:171::2
请输入 Routed /64：2001:470:19:170::/64
请输入 Routed /48：2001:470:f8e6::/48

请选择 IPv6 出口模式：

1. Routed /64
2. Routed /48（推荐，默认）

请输入（当前/默认：Routed /48）：2

请选择 DNS：

1. HE DNS
2. Cloudflare DNS
3. Google DNS

请输入（当前/默认：Cloudflare）：2
请输入 MTU（默认：1280）：1280
是否启用开机自启？（Y/N，默认：Y）：Y
```

> 注意：`Tunnel Server IPv6` 和 `Tunnel Client IPv6` 如果在 HE 页面上显示为 `2001:470:18:171::1/64`、`2001:470:18:171::2/64`，填写时只填 IPv6 地址本身，不要带 `/64`。`Routed /64` 和 `Routed /48` 是路由前缀，需要保留 `/64`、`/48`。

最后会显示配置确认：

```text
=================================
配置确认
=================================

Tunnel Server IPv4：216.218.221.6
Tunnel Client IPv4：91.233.10.68
Tunnel Server IPv6：2001:470:18:171::1
Tunnel Client IPv6：2001:470:18:171::2
Routed /64：2001:470:19:170::/64
Routed /48：2001:470:f8e6::/48
出口模式：Routed /48
出口 IPv6：2001:470:f8e6:1::1
DNS：Cloudflare
MTU：1280
开机自启：Yes

确认创建？（Y/N，默认：Y）：Y
```

确认后才会写入配置并创建隧道。

## 配置文件

所有隧道参数会保存到：

```text
/etc/he-tunnel/config.conf
```

示例：

```bash
SERVER_IPV4=
CLIENT_IPV4=
SERVER_IPV6=
CLIENT_IPV6=
ROUTED64=
ROUTED48=
EXIT_MODE=48
DNS=Cloudflare
MTU=1280
AUTOSTART=0
FIREWALL=0
```

菜单中的 `4. 查看隧道状态 / 当前配置` 会直接读取这个配置文件并显示当前状态。

## 常用命令

```bash
he                 # 进入交互式管理面板
he --apply         # 根据 /etc/he-tunnel/config.conf 创建/重建隧道
he --down          # 删除当前 he-ipv6 隧道接口
he --restart       # 删除并重建隧道
he --status        # 查看状态与配置
he --update        # 更新脚本
he --version       # 查看版本
```

## systemd 开机自启

安装脚本会安装 systemd 服务：

```text
/etc/systemd/system/he-tunnel.service
```

服务内容会调用：

```bash
/usr/local/bin/he --apply
```

启用开机自启：

```bash
systemctl enable he-tunnel.service
```

也可以在 `he` 菜单中选择 `10. 开机自启管理`。

## DNS

支持三组选项：

- HE DNS：`2001:470:20::2`、`74.82.42.42`
- Cloudflare DNS：`2606:4700:4700::1111`、`2606:4700:4700::1001`
- Google DNS：`2001:4860:4860::8888`、`2001:4860:4860::8844`

如果系统支持 `resolvectl` 或 `systemd-resolve`，脚本会尝试把 DNS 应用到隧道接口。如果系统不支持，会保存配置但不会强行覆盖 `/etc/resolv.conf`，避免破坏系统解析配置。

## IPv6 防火墙

`9. IPv6 防火墙` 提供基础入站保护。开启后会创建 `HE_TUNNEL_MANAGER` 链，并仅作用于 `he-ipv6` 隧道接口的入站流量：

- 允许已建立连接
- 允许 ICMPv6
- 允许 SSH 22 端口
- 丢弃其余从 `he-ipv6` 进入的入站流量

注意：如果你的 SSH 端口不是 22，请先自行调整规则，避免误拦截管理入口。

## /48 IPv6 生成器

如果 HE 分配了 Routed `/48`，可以使用菜单 `11. /48 IPv6 生成器` 批量生成多个 `/64` 子网，方便给 3x-ui、容器、虚拟机或其他服务分配独立 IPv6 段。

使用方法：

```text
请选择：11

请输入 Routed /48：2001:470:f8e6::/48
生成多少个 /64？默认：10：5
起始子网 ID（十六进制，默认 0）：1

生成结果：

2001:470:f8e6:1::/64
2001:470:f8e6:2::/64
2001:470:f8e6:3::/64
2001:470:f8e6:4::/64
2001:470:f8e6:5::/64
```

参数说明：

- `Routed /48`：填写 HE 后台给你的 `/48`，例如 `2001:470:f8e6::/48`。
- `生成多少个 /64`：要生成几个子网，默认生成 10 个。
- `起始子网 ID`：从第几个 `/64` 开始生成，使用十六进制。例如输入 `1`，第一个结果就是 `2001:470:f8e6:1::/64`；输入 `10`，第一个结果就是 `2001:470:f8e6:10::/64`。

默认出口模式使用 Routed `/48` 时，脚本会优先使用第一个业务出口地址：

```text
2001:470:f8e6:1::1/64
```

后续你可以继续把同一个 `/48` 里的其他 `/64`，例如 `2001:470:f8e6:2::/64`、`2001:470:f8e6:3::/64`，分配给 3x-ui、Docker、LXC、虚拟机或其他业务使用。

## 更新脚本

菜单 `12. 更新脚本` 会优先尝试：

```bash
git pull
```

如果安装目录不是 Git 仓库，则会从 `RAW_BASE` 重新下载最新版文件。`RAW_BASE` 位于：

```text
/etc/he-tunnel/manager.conf
```

## 卸载

```bash
/opt/he-tunnel-manager/uninstall.sh
```

完全删除配置：

```bash
/opt/he-tunnel-manager/uninstall.sh --purge
```

## 依赖

推荐系统：

- Debian 11/12
- Ubuntu 20.04/22.04/24.04
- CentOS Stream / Rocky / AlmaLinux
- 其他支持 `bash`、`iproute2`、`systemd` 的 Linux 发行版

需要的核心组件：

- `bash`
- `iproute2`
- `curl` 或 `wget`
- `iputils-ping`
- `iptables/ip6tables`
- `systemd`（用于开机自启）

## 注意事项

1. HE Tunnel Broker 需要 IPv4 协议 41（SIT/6in4）可达。
2. 如果服务器在 NAT 后面，需确认 HE 后台的 Client IPv4 与实际出口 IPv4 匹配。
3. 云厂商安全组、防火墙、机房 ACL 可能会阻止协议 41。
4. `MTU` 默认使用 `1280`，如果你的链路稳定，可以自行测试更高值，例如 `1480`。
5. 创建隧道会修改系统 IPv6 默认路由，请在生产环境操作前确认已有网络策略。


## IPv6 出口模式

本项目区分 Tunnel Client IPv6 与业务出口 IPv6。Tunnel Client IPv6 只用于 HE 隧道通信；实际公网出口使用 Routed /64 或 Routed /48 自动生成的 IPv6。默认出口模式为 Routed /48，会自动使用 `Routed /48` 的第一个 `/64`，例如 `2001:470:f8e6::/48` 会生成 `2001:470:f8e6:1::1/64` 并执行：

```bash
ip -6 route replace default dev he-ipv6 src <出口IPv6>
```

配置文件会保存：

```bash
EXIT_MODE=48
```

可在“修改 HE 隧道”菜单中切换 Routed /64 或 Routed /48 出口模式。
