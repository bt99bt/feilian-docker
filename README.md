# 飞连 Docker + 本机 SOCKS5

在 Linux 容器中运行飞连客户端，将 VPN 线路通过本机 SOCKS5 提供给 Clash/Mihomo。镜像支持 `linux/arm64` 和 `linux/amd64`：Apple 芯片 Mac 使用 ARM64，x86 Windows Docker Desktop 使用 AMD64。宿主机无需安装飞连。

**验证状态：**ARM64 已在 Mac Docker Desktop 中扫码登录、连接 VPN，并通过 SOCKS5 访问 `odin.botaneeai.com` 返回 HTTP 200。AMD64 已构建并完成基础检查，尚未在 Windows 上验证登录、TUN 和 VPN 链路。飞连官方未声明支持容器部署。

## 启动

先启动 Docker Desktop。Windows 需使用 **Linux containers** 模式。进入本目录后运行：

```sh
docker compose up -d --build
docker compose ps
docker compose exec -T feilian clash-config
```

Compose 会按当前机器架构构建对应镜像。构建时从飞连官网下载 Linux v3.2.16 安装包并校验 SHA-256；不会在宿主机安装飞连。仓库不包含飞连安装包、已构建镜像或登录状态。已有本地镜像时，后续启动可改用 `docker compose up -d --no-build`。

容器启动日志会打印可复制的 Clash/Mihomo 配置。第三条命令可随时单独输出配置；将 `proxies` 和 `rules` 下的条目分别合并到现有配置，规则放在 `MATCH` 等兜底规则之前。SOCKS5 只监听宿主机 `127.0.0.1:1080`，仅支持 TCP CONNECT。

打开 [飞连操作页面](http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=scale)，完成企业激活、扫码登录并连接 VPN。VPN 网卡及路由就绪后，SOCKS5 才会启动。登录数据保存在 Docker 卷中；容器重启后若会话过期，需要重新登录。

## 验证线路

Mac/Linux：

```sh
curl --socks5-hostname 127.0.0.1:1080 -I -L --max-time 15 https://odin.botaneeai.com/
```

Windows PowerShell：

```powershell
curl.exe --socks5-hostname 127.0.0.1:1080 -I -L --max-time 15 https://odin.botaneeai.com/
```

`--socks5-hostname` 让代理端解析域名。连接正常时预期最终返回 HTTP 200。其他企业域名需要自行添加 Clash 规则。

## 排查与停止

```sh
docker compose ps
docker compose logs --tail=100 feilian
docker compose exec -T feilian ip -br addr
docker compose down
```

`docker compose down` 保留登录数据卷；`docker compose down -v` 会删除该卷。若容器没有 `/dev/net/tun` 或权限不足，Docker 的 Linux 环境无法提供 VPN 所需 TUN 设备。若自动识别 VPN 网卡出错，可在本地 `.env` 中设置 `VPN_INTERFACE=实际网卡名`，再重建容器；不要设为 `eth0`。端口只绑定本机回环地址，其他设备无法直接使用。
