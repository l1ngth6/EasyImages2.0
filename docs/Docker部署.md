# PHP 8.4 Docker 部署与发布

本 fork 提供 Nginx + PHP-FPM 单容器镜像，支持 `linux/amd64`、`linux/arm64`。
镜像使用当前仓库源码，基于官方 `php:8.4-fpm-bookworm`（底层是 Debian slim），
构建及启动均要求 PHP 为 8.4 系列、补丁版本至少为 8.4.27。

镜像地址：`ghcr.io/l1ngth6/easyimages2.0`。
只有发布工作流成功后，文档中的镜像标签才可拉取。

## 从旧镜像替换

保留原来的主机目录、端口和环境变量，只将旧服务的 `image` 改为：

```yaml
image: ghcr.io/l1ngth6/easyimages2.0:php8.4
```

原挂载方式保持不变：

```yaml
volumes:
  - './config:/app/web/config'
  - './images/i:/app/web/i'
```

先停止旧服务，再备份以上两个目录并保留旧镜像的完整名称或 digest。
如果要保留统计、上传和登录记录，还需要从旧容器备份 `/app/web/admin/logs`；
这部分数据不在上述两条挂载中。
自定义水印、字体等如保存在其他容器内路径，也需另行备份并继续挂载。
不要让新旧两个容器同时写入同一份数据。

替换后，在原 Compose 所在目录执行：

```bash
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=100
```

验证管理员登录、网页/API 上传、已有图片直链、缩略图、水印、压缩和删除。
旧配置不自动重写或升级；如果升级后的应用新增配置项，可通过后台检查并保存配置。
如果自定义过图片根目录（默认 `/i/`），还需为相应容器路径挂载数据并调整 Nginx 的 PHP 禁执行规则。

回滚时先停止新容器，恢复升级前的备份及旧镜像配置，再启动旧服务。
测试期间应用可能已经写入配置或数据，回滚应使用升级前备份。
不要运行 `docker compose down -v` 或清理旧镜像，直到完成验收。

## 新部署

仓库根目录的 `compose.yaml` 可用于新部署。在专用部署目录中保存该文件后启动：

```bash
docker compose pull
docker compose up -d
```

默认访问 `http://服务器地址:8080`，首次打开完成应用安装。
Compose 的相对路径以 Compose 文件所在目录为基准。
镜像会在空挂载目录中补充默认配置和图片目录占位文件；
不会覆盖已有文件、账号、Token、图片及 `install.lock`。
不支持用只读卷挂载配置或图片目录。

## 环境变量与持久化

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `TZ` | `Asia/Shanghai` | 系统时区，必须是有效 IANA 时区；应用内时区仍由后台配置决定 |
| `PUID` | `1000` | PHP/Nginx 工作进程对应的用户 ID，接受非负整数 |
| `PGID` | `1000` | 对应组 ID，接受非负整数 |
| `DEBUG` | `false` | 仅接受 `true` 或 `false`；开启后将访问日志输出到容器日志 |

原有显式 UID/GID（包括 `0`）继续支持；新部署建议使用非零 ID。
启动时会将 `/app/web/config`、`/app/web/i`、`/app/web/admin/logs`、`/logs`
的所有权调整到指定 UID/GID，保留原有权限模式，不递归修改应用源码权限。
所以替换容器前也应记录原数据目录的所有权；只读文件系统或特殊存储的权限限制会令启动失败。

| 容器目录 | 用途 |
| --- | --- |
| `/app/web/config` | 配置、账号、API Token 和安装锁，必须持久化 |
| `/app/web/i` | 默认上传目录，必须持久化 |
| `/app/web/admin/logs` | 可选持久化：应用统计、上传、登录等记录 |
| `/logs` | 可选持久化：DEBUG 关闭时的 Nginx 访问日志 |

PHP 及进程错误始终进入 `docker logs`。即使应用尝试打开 `display_errors`，
FPM 也会强制关闭 HTTP 响应中的错误输出，避免污染 JSON 和图片响应。

文件上传及 PHP 内存上限为 512M，POST/Nginx 请求体上限为 520M；
应用后台自身的文件大小、数量限制继续生效。
健康检查通过 Nginx 请求 PHP-FPM，`/healthz` 只允许容器内回环地址访问。
容器只公开 HTTP 端口 `80`；HTTPS 可由现有反向代理提供。

## GitHub Actions 与 GHCR

1. 在 fork 的 **Actions** 页面启用工作流。仓库工作流必须有发布 Packages 的权限；
   发布任务已声明 `contents: read` 和 `packages: write`，认证使用内置 `GITHUB_TOKEN`，无需额外 PAT。
2. 将改动提交到仓库。PR 和 `master` 提交只检查、不发布；
   检查在 GitHub 托管 runner 中构建 amd64 镜像并运行临时数据检查，不要求本机安装 Docker 或 PHP。
3. 为要发布的提交创建标签并推送，例如：

   ```bash
   git tag docker-v2.8.7-r1
   git push origin docker-v2.8.7-r1
   ```

   标签必须满足 `docker-v主版本.次版本.补丁版本-r构建修订号`，修订号从 `1` 开始。
   推送已存在的普通上游版本标签不会触发镜像发布，也无需创建 GitHub Release。
4. 发布任务通过 Buildx/QEMU 构建 amd64、arm64 候选镜像，
   拉取各自的精确 digest 做轻量检查。两者全部通过后才发布多架构版本标签和别名。
   失败的构建可能留下无正式标签的候选包版本，但不会更新正式标签。
5. 首次发布后，在个人主页 **Packages → easyimages2.0 → Package settings → Change visibility**
   将包设置为 **Public**，才能匿名拉取。公开 GitHub 仓库不代表 GHCR 包自动公开。
   如果同名包已存在，确认其已关联本仓库并允许本仓库 Actions 写入。

上述例子产生：

```text
ghcr.io/l1ngth6/easyimages2.0:2.8.7-r1
ghcr.io/l1ngth6/easyimages2.0:php8.4
ghcr.io/l1ngth6/easyimages2.0:latest
```

发布目标实际由 `github.repository` 转为小写生成；以后再次 fork 时会自动使用新 owner/repo，
此时需同步修改自己的 Compose 镜像地址。
`php8.4` 和 `latest` 指向最近成功发布的版本；固定部署可使用完整版本标签或 digest。
请按版本顺序发布，不重新推送旧版本来更新别名。

每次发布强制拉取 PHP 基础镜像，并刷新 APT 安装层以获取当前系统依赖更新。
由于没有定时构建，PHP/系统依赖安全补丁不会自动进入已发布镜像；
需要推送新的修订号，例如 `docker-v2.8.7-r2`。
发布完成后服务器仍需手动拉取、重建容器；工作流不会访问或部署服务器。

## 验证范围与本地环境

GitHub Actions 检查 PHP 语法、8.4 最低补丁版本、扩展、GD 格式支持、Nginx/FPM 配置、
健康检查、空目录初始化、已有文件保留、UID/GID、重启、访问限制、JSON 响应和日志行为。
这些是合成数据的轻量检查，不能替代真实旧数据的功能回归。
所有测试容器和数据目录均在临时 runner 中创建，脚本退出时只清理自己的容器及临时目录。

默认不在本地拉取镜像、构建镜像、启动容器、创建卷或安装验证依赖。
如排障必须使用本地 Docker，提前说明用途与清理方式，不运行全局 prune，
不操作既有容器、卷或真实数据。

参考：[官方 PHP 镜像](https://hub.docker.com/_/php)、
[GitHub Container registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)。
