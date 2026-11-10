# 飞连 Docker + 本机 SOCKS5

在 Linux 容器中运行飞连客户端，将 VPN 线路通过本机 SOCKS5 提供给 Clash/Mihomo。镜像支持 `linux/arm64` 和 `linux/amd64`：Apple 芯片 Mac 使用 ARM64，x86 Windows Docker Desktop 使用 AMD64。宿主机无需安装飞连。

**验证状态：**ARM64 已在 Mac Docker Desktop 中扫码登录、连接 VPN，并通过 SOCKS5 访问 `odin.botaneeai.com` 返回 HTTP 200。AMD64 已构建并完成基础检查，尚未在 Windows 上验证登录、TUN 和 VPN 链路。飞连官方未声明支持容器部署。

## 启动

先启动 Docker。Mac/Windows 使用 Docker Desktop，Windows 需切换到 **Linux containers** 模式。在本目录运行：

```sh
docker compose up -d
docker compose ps
docker compose exec -T feilian clash-config
```

Compose 默认从公开的 GHCR 包拉取 `ghcr.io/bt99bt/feilian-docker:latest`，无需登录，也不会在本地构建。建议在本地 `.env` 中设置 `FEILIAN_IMAGE=ghcr.io/bt99bt/feilian-docker:0.1.0`，由自己决定何时升级；也可填 `@sha256:...` 固定到发布清单的摘要。`docker compose up -d` 每次都会检查并拉取所选镜像。

容器启动日志会打印可复制的 Clash/Mihomo 配置。第三条命令可随时单独输出配置；将 `proxies` 和 `rules` 下的条目分别合并到现有配置，规则放在 `MATCH` 等兜底规则之前。SOCKS5 只监听宿主机 `127.0.0.1:1080`，仅支持 TCP CONNECT。

打开 [飞连操作页面](http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=scale)，完成企业激活、扫码登录并连接 VPN。VPN 网卡及路由就绪后，SOCKS5 才会启动。登录数据保存在 Docker 卷中；容器重启后若会话过期，需要重新登录。

## 验证线路

Mac/Linux：

```sh
curl --socks5-hostname 127.0.0.1:1080 -I -L --max-time 15 https://odin.botaneeai.com/
curl --socks5-hostname 127.0.0.1:1080 -I -L --max-time 15 https://www.botaneeai.com/
```

Windows PowerShell：

```powershell
curl.exe --socks5-hostname 127.0.0.1:1080 -I -L --max-time 15 https://odin.botaneeai.com/
curl.exe --socks5-hostname 127.0.0.1:1080 -I -L --max-time 15 https://www.botaneeai.com/
```

`--socks5-hostname` 让代理端解析域名。连接正常时预期最终返回 HTTP 200。Clash 示例规则覆盖 `botaneeai.com` 及其子域名；访问网站请使用 `https://www.botaneeai.com/`，裸域名 `botaneeai.com` 当前没有 DNS 记录。其他企业域名需要自行添加 Clash 规则。

## 分享给别人

分享本仓库链接即可；对方只需下载 `compose.yaml`，运行 `docker compose up -d`，再按上文打开飞连操作页面完成自己的企业激活和扫码登录。Docker 的 Linux 环境必须提供 `/dev/net/tun`。登录数据保存在对方自己的 Docker 卷中，不在镜像或 Compose 文件里。

## 排查与停止

```sh
docker compose ps
docker compose logs --tail=100 feilian
docker compose exec -T feilian ip -br addr
docker compose down
```

`docker compose down` 保留登录数据卷；`docker compose down -v` 会删除该卷。若容器没有 `/dev/net/tun` 或权限不足，Docker 的 Linux 环境无法提供 VPN 所需 TUN 设备。若自动识别 VPN 网卡出错，可在本地 `.env` 中设置 `VPN_INTERFACE=实际网卡名`，再重建容器；不要设为 `eth0`。端口只绑定本机回环地址，其他设备无法直接使用。

## 镜像发布

[Container 工作流](.github/workflows/container.yml) 在 PR 和 `main` 推送时检查脚本语法并构建 `linux/amd64`、`linux/arm64`，不推送镜像。只有推送 `vMAJOR.MINOR.PATCH` 标签时才使用仓库的 `GITHUB_TOKEN` 发布到 GHCR，无需另存发布密钥。构建时从飞连官网下载 Linux v3.2.16 安装包并校验 SHA-256；仓库不包含飞连安装包、已构建镜像或登录状态。工作流生成 `MAJOR.MINOR.PATCH`、`sha-<短提交号>` 和 `latest` 标签，附带 SBOM、构建来源信息，并检查发布清单包含两个架构。镜像版本表示本仓库的封装版本，飞连客户端版本见 Dockerfile；二者独立更新。

首次发布示例：先把变更合入 `main` 并确认 Container 检查通过，再在该提交上执行：

```sh
git tag v0.1.0
git push origin v0.1.0
gh run list --workflow container.yml --limit 5
docker buildx imagetools inspect ghcr.io/bt99bt/feilian-docker:0.1.0
```

后续发布递增本仓库版本号，不要将新内容重新推送到已有版本标签。镜像包公开供匿名拉取；GitHub Actions 仍用仓库的 `GITHUB_TOKEN` 发布新版本。
