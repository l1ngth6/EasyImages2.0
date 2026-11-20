# EasyImages2.0 · PHP 8.4 Docker

> 上游项目：[icret/EasyImages2.0](https://github.com/icret/EasyImages2.0)
>
> EasyImage 是一款无需数据库的轻量图床，适用于个人图片托管。完整功能与使用说明请参阅[上游文档](https://icret.github.io/EasyImages2.0/#/)。

## 本项目的用途

本 fork 主要维护 EasyImages2.0 的 Docker 部署方案：将 PHP 运行环境升级到 8.4，
通过 GitHub Actions 构建并发布可直接拉取的镜像，方便现有部署更新运行环境。
应用源码基于上游，应用功能与原作者贡献归属上游项目。

主要改动：

- 基于官方 PHP 8.4 镜像，打包 Nginx、PHP-FPM 和图片处理所需扩展。
- amd64、arm64 分别使用 GitHub 原生 runner 构建与检查，再合并发布到 GHCR。
- 保留旧版 `ddsderek/easyimage` 的配置、图片挂载路径，便于替换容器。
- 跟随上游 2.8.7 安全加固；启动时自动把旧版 SHA256 口令转换为 2.8.7 所需的 bcrypt，原密码可继续登录。
- 增加运行环境、持久化和访问限制检查，按版本标签发布镜像更新。

## 使用镜像

```bash
docker pull ghcr.io/l1ngth6/easyimages2.0:php8.4
```

镜像支持 `linux/amd64`、`linux/arm64`，也可使用 `latest` 或固定版本标签。
旧部署继续挂载 `./config:/app/web/config` 和 `./images/i:/app/web/i`。

- [部署、迁移与发布说明](docs/Docker部署.md)
- [Compose 示例](compose.yaml)
- [镜像包](https://github.com/l1ngth6/EasyImages2.0/pkgs/container/easyimages2.0)

PHP 与系统依赖的安全更新需要发布新的镜像修订版本；更新镜像后需自行重建容器。

## 版本说明

| 镜像版本 | 应用代码 | 主要变化 | 升级时手动操作 |
| --- | --- | --- | --- |
| `2.8.7-r5` | 上游 v2.8.7（`5f3e08b`） | 关闭 PHP-FPM 访问日志，健康检查和 PHP 请求不再刷屏 `docker logs` | 从 r4 升级：无；从更早版本升级：见下文 |
| `2.8.7-r4` | 上游 v2.8.7（`5f3e08b`） | 合并上游 2.8.7 安全加固；启动时自动转换旧口令 | **需要**，见下文 |
| `2.8.7-r1`～`r3` | 上游 `dcb9776`（2.8.7 正式版之前） | PHP 8.4 镜像与 GHCR 发布；r3 起 PHP 8.4.28 | — |

## 升级到 2.8.7-r4 及以上（需要手动处理）

适用于从 `2.8.7-r3` 及更早版本、或旧版 `ddsderek/easyimage` 升级。上游 2.8.7 的多项安全改动不向后兼容，
其中旧口令由镜像自动转换，其余几项需要手动确认。以下修改都即时生效，无需重启容器。

1. **备份**：先备份 `./config`；挂载了 `admin/logs` 的话一并备份。
2. **更新镜像**：

   ```bash
   docker compose pull && docker compose up -d
   ```

3. **查看启动日志**，按提示处理。没有 `easyimage-migrate:` 输出说明无需处理：

   ```bash
   docker compose logs easyimage | grep easyimage-migrate
   ```

   | 日志 | 含义 | 处理 |
   | --- | --- | --- |
   | `config.php: converted N legacy SHA256 password(s) to bcrypt` | 管理员旧口令已转为 bcrypt，原密码可以登录 | 第 4 步修改密码 |
   | `config.guest.php: converted ...` | 上传者旧口令已转换 | 通知上传者修改密码 |
   | `left example uploader 'guest' unconverted` | 旧版自带的示例上传者，密码公开，故意不转换 | 后台「上传者管理」删除 `guest` |
   | `config.php lacks settings ...: 项名` | 旧配置缺少新配置项，后台无法新增 | 编辑 `config/config.php`，在 `$config=Array` 下面那行 `(` 之后补上对应行 |
   | `...: left unchanged: 原因` | 该文件未转换，内容保持原样 | 按原因处理，或参考[手动方法](docs/Docker部署.md#升级到-287-的注意事项) |

   旧配置常缺的两项（值与出厂默认一致）：

   ```php
   	'trusted_proxy'=>'',
   	'token_suffix_ID'=>1,
   ```

   `trusted_proxy`：可信代理名单。反代与容器在同一 Docker 网络时留空即可；公网 CDN 或代理直接连接容器时，填写其出口 IP。
   `token_suffix_ID`：API 上传的文件名是否追加 `-TokenID`，`1` 与旧版行为一致。
   其他缺少的项可以从镜像内的出厂配置复制：

   ```bash
   docker compose exec easyimage grep -n "'项名'" /opt/easyimage-defaults/config/config.php
   ```

4. **登录并修改密码**：先用原密码登录，再到后台「管理员设置」修改密码。
   登录时提交的是密码的 SHA256，旧版的 Cookie、登录日志和路径穿越漏洞都可能泄露这串值；
   转换后它仍然有效，改密后才会失效。
5. **清理备份**：确认新密码能登录后，删除 `config/*.legacy-sha256.bak`。

升级后的其他变化：

- 登录状态改为服务端 Session，所有人需要重新登录；Session 保存在容器内，重建容器后也要重新登录。
- 旧的删除链接和源图保护（`hide.php`）链接全部失效，修改管理员密码也会使删除链接失效；普通图片直链不受影响。
- 访问者 IP 的判定与上游一致，用于 IP 黑白名单、游客上传限额和日志，规则见[部署说明](docs/Docker部署.md#反向代理与访问者-ip)。
- 上游的其他变化见[上游更新日志](docs/update.md)中 v2.8.7 的「升级注意」。

## 相对上游的修改

应用代码（PHP）与上游 v2.8.7（`5f3e08b`）一致，本 fork 只改容器、CI 和文档。

`2.8.7-r5`：

- 关闭 PHP-FPM 访问日志（官方 PHP 镜像默认会把每个 PHP 请求写入 `docker logs`），访问日志统一由 Nginx 按 `DEBUG` 输出。

`2.8.7-r4`：

- **旧口令自动转换**：上游 2.8.7 只接受 bcrypt，且不提供迁移。镜像启动时把 `config.php`、`config.guest.php`
  中的旧 SHA256 口令转为 bcrypt，原密码可以继续登录。
  - 只替换口令值，原文件备份为 `*.legacy-sha256.bak`（权限 600）。
  - 新文件验证通过后才替换原文件；失败时文件保持原样，容器照常启动。
  - 转换以 `PUID:PGID` 身份运行，跳过公开密码的示例账号，并提示缺少的配置项。
  - 可用 `EASYIMAGE_MIGRATE_LEGACY_PASSWORDS=false` 关闭。
- **Nginx 补齐上游 `.htaccess` 的等价规则**（上游规则只对 Apache 生效）：
  - `/i/`、`/public/` 拒绝上游列出的脚本扩展名。
  - `/i/` 下的响应添加 `X-Content-Type-Options: nosniff`，SVG 额外添加 `Content-Security-Policy: sandbox`。
- 访问者 IP 获取方式沿用上游，未做定制。
- 镜像检查新增旧口令转换、真实登录、重启不重复改写和安全响应头。

## 许可与致谢

遵循 [GPL-2.0](LICENSE)。EasyImages2.0 原作者：[Icret](https://github.com/icret)。
