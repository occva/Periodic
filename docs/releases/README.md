# 版本管理与发布

## 版本事实

- `Configurations/Base.xcconfig` 中 `MARKETING_VERSION = 1.0.0` 是展示版本；`CURRENT_PROJECT_VERSION = 1` 是更新排序使用的构建号。
- 每次正式发布必须递增构建号，即使展示版本的层级或编号发生变化，也不能复用旧构建号。
- 不改动 bundle identifier、SwiftData 迁移版本、正式数据库或资源目录。更新替换应用包，原本的数据库迁移入口继续负责打开用户数据。
- 1.0.0 是包含更新器的首个版本；此前从源码运行的 0.1.0 没有更新器，需要手动安装 DMG。

## 更新行为与职责

`AppUpdateConfiguration` 验证 HTTPS 发布源与 Ed25519 公钥，并禁止 Debug、XCTest、预览、内存数据库和样本模式启动正式更新器。`ApplicationRestartReadiness` 提供重启条件的纯规则。`AppUpdateService` 在 MainActor 封装 Sparkle，仅由 App 入口创建一次，菜单与更新设置复用同一实例。

手动检查使用 Sparkle 标准界面，显示没有新版本、网络错误、下载进度、更新说明和安装确认。下载后先校验更新签名再解包；更新 feed 也必须签名。用户确认安装后，由 Sparkle 安装并重启，不自行编写应用替换脚本。存在编辑 sheet 或系统模态窗口时保留安装回调，提示先保存或取消，关闭后继续；不会自动提交草稿。

`ApplicationTerminationGuard` 保护关闭弹窗后仍在执行的数据导入、读取与导出准备。操作开始时同步登记，成功或失败后均释放；更新同时等待全部操作和弹窗结束。签名 feed 验证失败不进行超时降级，发布私钥必须妥善备份。

默认关闭自动检查、自动下载安装和系统信息收集。用户可主动开启自动检查和自动下载安装；后者在退出应用时安装，手动确认安装则立即重启。Sparkle 自己保存更新偏好，业务设置不重复维护另一份状态。检查与下载仅访问 GitHub 发布服务，不附加订阅、付款或其他业务数据。

安装引导只在 DMG Finder 窗口展示：Periodic 在左，Applications 链接在右，背景上有拖拽提示和箭头。设置内不提供安装教程。`script/create_dmg.sh` 使用原生 AppKit 绘制背景，通过 Finder 保存窗口布局，不引入运行时依赖。打包机器需要运行图形会话，并允许终端控制 Finder。

## 依赖与沙盒

采用 Sparkle **2.10.0**，通过 Swift Package Manager 固定版本并提交 `Package.resolved`。这是版本更新专用依赖，不向业务模型或存储层暴露 SDK。相较于自写下载器和安装器，它提供更新签名、安装权限、失败处理及重启流程；维护成本包括定期评估 Sparkle 安全修复、校验嵌套签名和维护更新密钥。

已有网络客户端权限用于 HTTPS 请求。新增沙盒 mach lookup 例外仅允许 `<bundle identifier>-spks` 和 `<bundle identifier>-spki` 两个 Sparkle 安装器通信名称，同时启用框架内的 Installer XPC Service。没有启用 Downloader XPC、联网服务端、遥测或账号，也没有改变持久化文件权限。

框架的 MIT 许可及所含代码的许可说明在应用资源 `ThirdPartyNotices.txt` 中保留。

## 更新签名密钥

公钥保存在 `Configurations/Updates.xcconfig` 并进入应用 `SUPublicEDKey`。私钥保存在此 Mac 登录钥匙串的 Sparkle 账户 **Periodic**，不会进入仓库、日志、环境文件或 DMG。

首次配置在完成 Xcode 包解析后运行：

```bash
build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account Periodic
```

只查看既有公钥时加 `-p`。维护者须安全备份密钥，并在换机时使用 Sparkle 官方密钥导入/导出工具迁移；不要重新生成公钥来代替迁移，否则旧客户端无法验证新版本。

## 本地验证

```bash
./script/test.sh unit
./script/test.sh --release
./script/build_and_run.sh --verify
./script/release.sh --local
```

`--local` 构建仅包含 arm64 的 Release 应用并检查版本、更新配置、框架组件和代码签名，生成 `dist/1.0.0-local/Periodic-1.0.0-local.dmg`。它不会公证、生成公开 appcast 或发布 GitHub Release。可用于本地检查包结构与安装引导。

## 未公证版本打包与发布

1.0.0 无 Developer ID 凭据，使用临时代码签名分发，未经 Apple 公证。更新包和 feed 仍必须使用 Sparkle 私钥签名。这两类签名职责不同：Sparkle 签名验证更新来源，不替代 Apple 首次打开时的信任判断。

临时签名模式关闭 Hardened Runtime，并按从内到外的顺序为 Sparkle 辅助程序、XPC、框架和主应用统一临时签名，保留各自 entitlements 和 App Sandbox。避免主程序无团队签名、框架保留第三方团队签名造成启动或安装器通信失败。

前提：Sparkle 签名私钥与仓库公钥匹配；工作区干净，版本号和递增构建号已提交；发布时 HEAD 等于 GitHub `origin/main`。发布说明必须明确注明“未经 Apple 公证”。

```bash
# 生成正式包与签名 feed
./script/release.sh --unnotarized

# 完成校验后公开发布 v1.0.0
./script/release.sh --unnotarized --publish
```

首次打开被系统阻止时，用户确认下载来源后可手动运行 `xattr -rd com.apple.quarantine /Applications/Periodic.app`；权限不足时才加 `sudo`。此命令不改变签名或公证状态。应用与打包脚本不会执行隔离移除命令，也不要求关闭系统安全设置。

## 可选的 Developer ID 分发

有有效的 Developer ID Application 证书及私钥、Apple 团队 ID，以及 `xcrun notarytool store-credentials` 配置的凭据 profile 时，可使用公证流程。凭据只通过外部环境变量提供：

```bash
export DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)'
export APPLE_TEAM_ID='TEAMID'
export NOTARYTOOL_PROFILE='Periodic-notary'

# 只生成正式包，不发布
./script/release.sh

# 完成相同校验后公开发布 v1.0.0
./script/release.sh --publish
```

公证模式执行 archive/export，让 Xcode 对 Sparkle framework、Installer XPC 和嵌套工具重新签名，提交应用及 DMG 公证并 staple。两种公开分发模式都验证应用主程序仅包含 arm64、递归代码签名和更新密钥匹配，生成原生安装窗口，使用 Sparkle 官方工具生成、签名并校验 appcast 和实际更新包，检查版本、系统要求、下载地址及文件长度，生成 SHA256SUMS。Sparkle 自带的框架与辅助程序保留官方构建的架构，不拆改第三方二进制。

公开发布先验证上一正式版的签名 feed 并确认构建号递增，再上传 DMG、`appcast.xml` 和 `SHA256SUMS` 到草稿，全部上传完成后才设为最新正式 Release。使用仓库中对应版本的发布说明。更新地址固定为 GitHub 最新正式 Release 的 `appcast.xml` 资产，后续版本继续上传同名 feed。不会覆盖已发布版本，也不发布 `-local` 包。

## 验证边界

不新增或运行 UI 测试。配置与重启条件通过单元测试验证，发布元数据使用 Python 单元测试和实际包检查验证。完整的“旧正式版发现新版本 → 下载 → 安装 → 重启”需要两份递增构建号的有效更新签名包及可访问的签名 feed；首次发布前没有旧正式版本时，应在后续预发布验收环境中完成这一交互验证。未执行的公证、公开发布或端到端更新不能描述为已通过。
