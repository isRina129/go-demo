# go-demo

`go-demo` 是用于验证 fc-devops 的 Go Monorepo。仓库包含两个可以独立选择 Tag、独立构建和独立发布到阿里云函数计算的 Custom Runtime 服务。

## 目录

```text
services/
  order/                 Order API
  user/                  User API
internal/webapp/         两个服务复用的 Gin/Custom Runtime 启动代码
scripts/
  build-custom-runtime.sh
  publish-zip.sh
.github/workflows/
  deploy-order.yml
  deploy-user.yml
```

两个 ZIP 的根目录都只有可执行文件 `bootstrap`，进程默认监听 `0.0.0.0:9000`。可以通过 `PORT` 或 `FC_SERVER_PORT` 覆盖端口。

## 本地运行

```bash
make test

make run-order
curl http://localhost:9101/health
curl http://localhost:9101/api/v1/orders/1001

make run-user
curl http://localhost:9102/health
curl http://localhost:9102/api/v1/users/1001
```

构建 Linux amd64 Custom Runtime ZIP：

```bash
make package-all
unzip -l dist/order.zip
unzip -l dist/user.zip
```

## 初始化阿里云函数计算资源

根目录的 `s.yaml` 使用 Serverless Devs FC3 组件定义了 `go-demo-order` 和
`go-demo-user` 两个 Custom Runtime 函数。默认地域是 `cn-hangzhou`，部署前请按需修改
`vars.region`。HTTP 触发器使用匿名鉴权，适合本示例公开访问；生产环境应根据实际情况改为
函数鉴权或 JWT 鉴权。

配置 Serverless Devs 的阿里云访问凭证后，可以同时初始化两个函数：

```bash
s deploy -y
```

也可以独立部署：

```bash
s order deploy -y
s user deploy -y
```

每个资源的 `pre-deploy` 会调用对应的构建脚本，生成 Linux amd64 的 `bootstrap`。函数部署
完成后，把 `go-demo-order` 和 `go-demo-user` 分别登记到 fc-devops 的 FC 函数资源清单，
并绑定到对应的 Deployment Target。

## 推送到 GitHub

先在 GitHub 创建一个不带 README、`.gitignore` 和 License 的空仓库 `go-demo`，然后执行：

```bash
cd /Users/isrina129/Codes/gocode/src/github.com/isrina129/go-demo
git remote add origin git@github.com:isrina129/go-demo.git
git push -u origin main
```

## GitHub 仓库配置

在 GitHub 仓库的 `Settings → Secrets and variables → Actions → Variables` 添加：

```text
FC_DEVOPS_API_URL=https://fc-devops-api.example.com
```

这个地址必须能被 GitHub Actions 访问。本地联调时应填写映射到 `http://localhost:9000` 的 HTTPS 隧道地址，不要填写 localhost。

GitHub App 最小仓库权限：

```text
Actions: Read and write
Contents: Read-only
Metadata: Read-only
```

## fc-devops 服务配置

绑定仓库后创建两个 Deployment Unit：

| 字段 | Order | User |
|---|---|---|
| `service_key` | `order` | `user` |
| `name` | `Order API` | `User API` |
| `source_path` | `services/order` | `services/user` |
| `workflow_file` | `deploy-order.yml` | `deploy-user.yml` |
| `workflow_ref` | `main` | `main` |
| `tag_pattern` | `order/v*` | `user/v*` |
| `deployment_mode` | `CUSTOM_RUNTIME_ZIP` | `CUSTOM_RUNTIME_ZIP` |

每个服务分别绑定自己的 FC Deployment Target。OSS Bucket 和 Prefix 由 Deployment Target 配置，GitHub Actions 不保存阿里云 AccessKey。

## 创建候选 Tag

```bash
git tag order/v1.0.0
git tag user/v1.0.0
git push origin order/v1.0.0 user/v1.0.0
```

Tag push 不会自动部署。发布时进入 fc-devops，选择服务、部署目标和对应 Tag，再点击创建发布。

fc-devops 会向选中服务的 workflow 传入：

```text
release_id
service_key
git_tag
commit_sha
deployment_mode
artifact_token
source_path
```

其中前六项是平台必需输入，`source_path` 是当前示例 Workflow 声明的可选构建配置。
Workflow 使用标准 `run-name` 关联发布记录，固定 checkout `commit_sha`，构建 ZIP 后使用
`artifact_token` 从 fc-devops 获取 OSS 预签名地址并直接上传。Workflow 不再发送完成回调；
fc-devops 会在发布流程中主动轮询 GitHub Actions 状态，并通过 OSS `HeadObject` 发现和校验产物。
