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

## 许可与致谢

遵循 [GPL-2.0](LICENSE)。EasyImages2.0 原作者：[Icret](https://github.com/icret)。
