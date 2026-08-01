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
完成后，在 fc-devops 中同步 FC 函数清单，再把 `go-demo-order` 和 `go-demo-user`
分别绑定到对应的服务部署配置。

## 推送到 GitHub

先在 GitHub 创建一个不带 README、`.gitignore` 和 License 的空仓库 `go-demo`，然后执行：

```bash
cd /Users/isrina129/Codes/gocode/src/github.com/isrina129/go-demo
git remote add origin git@github.com:isrina129/go-demo.git
git push -u origin main
```

## GitHub 仓库配置

Workflow 不保存阿里云 AccessKey，也不需要配置 fc-devops API 地址。fc-devops 在触发构建时会把一次性的
`credentials_url` 和短期 `artifact_token` 作为 `workflow_dispatch` 输入传入。后端的
`ARTIFACT_PUBLIC_API_BASE_URL` 必须是 GitHub Actions 可以访问的 HTTPS 地址；本地联调可使用
ngrok 等隧道，不能填写 localhost。

GitHub App 最小仓库权限：

```text
Actions: Read and write
Contents: Read-only
Metadata: Read-only
```

## fc-devops 服务配置

授权并绑定仓库、同步 GitHub Workflow 后，创建两个服务部署配置：

| 字段 | Order | User |
|---|---|---|
| 配置名称 | `订单服务` | `用户服务` |
| GitHub Workflow | `deploy-order.yml` | `deploy-user.yml` |
| Tag 规则 | `order/v*` | `user/v*` |
| 部署模式 | `CUSTOM_RUNTIME_ZIP` | `CUSTOM_RUNTIME_ZIP` |
| 目标函数 | `go-demo-order` | `go-demo-user` |
| OSS Bucket | 制品 Bucket | 制品 Bucket |
| OSS Prefix | 业务自定义前缀，可留空使用默认值 | 业务自定义前缀，可留空使用默认值 |

源码目录和打包命令都由各自 Workflow 管理，服务部署配置不再包含 `source_path`、Dockerfile、
构建上下文、Workflow Ref 或独立的 Deployment Target。

## 创建候选 Tag

```bash
git tag order/v1.0.0
git tag user/v1.0.0
git push origin order/v1.0.0 user/v1.0.0
```

Tag push 不会自动构建或部署。进入 fc-devops 的“构建制品”，选择服务部署配置和对应 Tag 后发起构建。

fc-devops 会向选中服务的 workflow 传入：

```text
artifact_id
artifact_token
artifact_type
git_tag
commit_sha
credentials_url
```

Workflow 使用 `fc-devops-artifact-{artifact_id}` 作为 `run-name`，固定检出 `commit_sha`，自行完成测试和打包，
再使用短期 Token 从 `credentials_url` 换取 STS 并将 ZIP 直接上传 OSS。对象名由平台生成：
`{前缀}/{工作流名称}/{Tag}/{Tag}_{UTC时间戳}.zip`。

Workflow 不发送完成回调。fc-devops 的 jobs 进程每 15 秒轮询 GitHub Actions；确认运行成功后，再通过
OSS `HeadObject` 校验对象，最终把制品标记为“可用”。构建成功只产生不可变制品，不会立即修改函数。

## 从制品创建函数版本

进入目标函数的“版本管理”，选择属于该函数且状态为“可用”的制品，填写 `v1.0.0` 形式的版本名称并创建。
平台先用制品更新函数的 `LATEST`，待函数恢复 Active 后发布阿里云 FC 数字版本，同时保存版本名称、Tag、
Commit SHA 和制品关联。创建版本不会自动切换别名；`PROD` 与 `STAGING` 在别名管理中分别操作，互不影响。
