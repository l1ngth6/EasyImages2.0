# EasyImages2.0 · PHP 8.4 Docker

> 上游项目：[icret/EasyImages2.0](https://github.com/icret/EasyImages2.0)
>
> EasyImage 是一款无需数据库的轻量图床，适用于个人图片托管。完整功能与使用说明请参阅[上游文档](https://icret.github.io/EasyImages2.0/#/)。

本 fork 主要维护 Docker 部署方案：提供 PHP 8.4 运行环境，使用 GitHub 原生 amd64、arm64 runner
构建并检查镜像，再发布到 GHCR；保留旧版 `ddsderek/easyimage` 的配置和图片挂载路径，便于更新现有部署。

## 部署入口

```bash
docker pull ghcr.io/l1ngth6/easyimages2.0:php8.4
```

- [Docker 部署、迁移与发布](Docker部署.md)
- [当前 fork](https://github.com/l1ngth6/EasyImages2.0)
- [上游项目与完整使用说明](https://github.com/icret/EasyImages2.0)

目录中的其余应用使用文档保留自上游，Docker 部署以本 fork 的部署说明为准。
PHP 与系统依赖的安全更新需要发布新的镜像修订版本。

遵循 [GPL-2.0](https://github.com/l1ngth6/EasyImages2.0/blob/master/LICENSE)。原作者：[Icret](https://github.com/icret)。
