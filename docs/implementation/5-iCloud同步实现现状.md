# iCloud 同步实现现状

> 更新时间：2026-10-04
> 分支：`codex/icloud-sync`
> 基线：`main` / `e10d631`
> 结论：核心同步基础设施和本地可验证链路已经实现，但尚未完成真实 CloudKit 容器双机联调及全部数据恢复流程，当前不能视为生产完成。

## 1. 当前定位

这次实现采用显式 `CKSyncEngine` 适配层，不使用 SwiftData 自动 CloudKit 同步。SwiftData 继续作为本地持久化接口，CloudKit 只负责传输经过版本化、可重试和可冲突处理的记录。

默认构建仍然是本地模式：

- 不包含 CloudKit entitlement。
- `PeriodicICloudContainerIdentifier` 为空。
- 不会创建 `CKContainer`，也不会访问 CloudKit。
- 设置页可以展示 iCloud 同步入口，但启用时会明确提示当前构建未配置 iCloud 能力。

只有使用付费 Apple Developer Team、真实 iCloud container 和开发签名构建后，才会创建 CloudKit 适配器并允许启用同步。

## 2. 已实现能力

### 2.1 数据集与写入边界

- 增加稳定的 `DatasetDescriptor`、设备标识和数据集元数据。
- 通过 `DatasetAccessCoordinator` 串行化业务写入，并提供维护锁和全局 `storeRevision`。
- 数据导入、业务 Store 和同步应用远端变更共用同一数据集写入边界。
- 数据库打开或元数据损坏时保留原始错误，不通过清库或内存库静默恢复。
- SwiftData schema 已升级到 `AppSchemaV9`，包含同步 mutation、远端 inbox、记录状态和冲突记录。

### 2.2 本地变更日志与恢复

- 业务写入和 `sync_mutations` journal 在同一 SwiftData 事务中提交。
- 每条同步记录保存稳定 ID、revision、修改设备、tombstone 和服务端 system fields。
- 上传前将连续 mutation 合并为一个完整记录，同时保留首个 base revision 和实际字段变更集合。
- mutation 支持 pending、uploading、acknowledged 和 conflicted 状态，进程退出后可以继续。
- 远端记录先写入 durable inbox，再应用到业务模型，应用中断后可以重放。

### 2.3 CloudKit 传输

- 使用用户私有 CloudKit database。
- 使用名为 `Periodic` 的 custom zone。
- 使用 `CKSyncEngine` 保存和恢复同步状态。
- 支持创建 zone、拉取变化、上传本地 mutation、服务端版本冲突和 partial failure 分类。
- 本地写入完成后会唤醒同步引擎；启动、回到前台和手动操作也可以触发同步。
- 启用前可以只读统计云端记录数和图片字节数，不下载图片正文，也不修改本地数据。
- 云端 record types：
  - `PeriodicSubscription`
  - `PeriodicSubscriptionPeriod`
  - `PeriodicSubscriptionPayment`
  - `PeriodicServiceTemplate`
  - `PeriodicTemplateCategory`
  - `PeriodicBuiltinCategoryAssignment`
  - `PeriodicIconAsset`

### 2.4 当前同步范围

| 数据 | 当前状态 | 说明 |
| --- | --- | --- |
| 订阅 | 已实现 | 包含基本资料、管理状态、计费设置和图标引用 |
| 订阅周期 | 已实现 | 作为独立历史事实同步 |
| 付款 | 已实现 | 金额、币种、日期和附件引用同步 |
| 用户模板 | 已实现 | 内置模板本体不上传 |
| 自定义分类 | 已实现 | 使用稳定 UUID |
| 内置模板分类覆盖 | 已实现 | 只同步用户覆盖关系 |
| 本地图标和付款附件 | 已实现 | 通过统一 icon asset 记录传输 |
| 设备偏好和窗口状态 | 不同步 | 保持设备本地 |
| 通知授权和请求 | 不同步 | 属于设备本地系统状态 |

试用计划、取消计划、业务 change events 和部分业务设置仍在产品规格的目标范围内，但这次提交没有将它们接入 CloudKit record type，不能将其描述为已同步。

### 2.5 合并与冲突

- 基于 base revision 和 changed fields 合并，不依赖设备时钟做最后写入覆盖。
- 同一记录修改不同字段时可自动合并并重建本地待上传 mutation。
- 金额与币种、计费类型与周期等字段按原子字段组检测冲突。
- 相同图片 ID 对应不同内容哈希时产生冲突。
- 删除与离线修改冲突不会自动复活记录。
- 持久化冲突页面支持非删除冲突的“保留此 Mac”和“使用 iCloud”。

当前尚不支持删除与修改冲突的“保留为新副本”，所以这类冲突只能显示和阻止危险覆盖，不能在冲突页直接完成恢复。

### 2.6 图片事务

- 图片使用 SHA-256、格式和字节数校验。
- 下载内容先进入 staging，验证可解码性和元数据后再原子移动到正式目录。
- SwiftData 提交失败时回滚新文件；提交成功前不会删除旧文件。
- 业务记录先到而图片未到时，远端变更保持待应用，不写入悬空引用。
- 图片 tombstone 会先解除业务引用，再删除受管文件。
- 支持应用重启后重新取得已有 staging 文件。

### 2.7 启用、停用和账号保护

- 启用前展示“此 Mac / iCloud”数据摘要。
- 启用时先生成本地 `.periodicdata` 安全快照，再 bootstrap 现有记录并启动同步。
- 停止同步目前只实现“停止并保留此 Mac 数据”，不会删除云端副本。
- Apple ID 使用不可逆账号指纹绑定到当前数据集。
- 运行中或应用重启后检测到 Apple ID 变化时会冻结同步，避免两个账号的数据被自动混合。

### 2.8 设置界面与本地化

- 设置页显示同步阶段、待上传、待应用、冲突、最近成功时间和安全快照。
- 支持立即同步、停止并保留本机数据、查看冲突和在 Finder 中显示安全快照。
- 新增界面和主要错误已提供英文 localization。

## 3. 尚未完成的功能

以下项目是上线前必须继续完成的产品能力：

1. “使用 iCloud 替换此 Mac”：
   - 下载到独立候选数据库。
   - 校验记录、关系、图片和 schema。
   - 验证通过后原子切换活动数据集。
   - 任何失败都继续使用原数据库。
2. Apple ID 变化后的恢复操作：
   - 保留本地数据。
   - 导出数据。
   - 明确切换到当前 Apple ID，并重新绑定数据集。
3. 删除与修改冲突的“保留为新副本”。
4. 停止同步时对 iCloud 副本的处理选项和确认流程。
5. 稳定 `apple-icon:` 引用字符串不变、但底层图片内容变化时的重新入队检测。
6. 全面检查图片和付款附件的孤儿清理路径。
7. 网络抖动、CloudKit 限流、空间不足、token 失效、长时间离线和崩溃恢复压力测试。
8. 真实双 Mac 最终收敛验证和 production schema 部署。

## 4. 外部配置要求

### 4.1 Apple 账号要求

- 应用最终用户只需要普通 Apple ID，并在系统设置中登录 iCloud。
- 配置和签名 CloudKit 开发构建的开发者，需要：
  - 付费 Apple Developer Program 会员；或
  - 已加入一个付费开发团队，并拥有创建或使用 iCloud container 的权限。
- 免费 Personal Team 不能为这套实现配置所需的 CloudKit container entitlement。

### 4.2 当前构建默认值

`Configurations/Base.xcconfig` 当前故意保持：

```xcconfig
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY = -
DEVELOPMENT_TEAM =
PERIODIC_CODE_SIGN_ENTITLEMENTS = Configurations/Periodic.entitlements
PERIODIC_ICLOUD_CONTAINER_IDENTIFIER =
```

因此普通仓库构建不会意外连接某个开发者的私有 CloudKit 容器。

### 4.3 真实 CloudKit 开发构建

需要在 Apple Developer 后台创建或选择 iCloud container，并为本地构建提供以下覆盖值：

```xcconfig
CODE_SIGN_STYLE = Automatic
CODE_SIGN_IDENTITY = Apple Development
DEVELOPMENT_TEAM = <YOUR_TEAM_ID>
PERIODIC_CODE_SIGN_ENTITLEMENTS = Configurations/PeriodicCloudKit.entitlements
PERIODIC_ICLOUD_CONTAINER_IDENTIFIER = iCloud.<YOUR_CONTAINER_IDENTIFIER>
```

这些值可以作为 Xcode 用户自定义 Build Settings 或 `xcodebuild` 参数传入。当前仓库还没有接入被 Git 忽略的 `Developer.xcconfig`；不要把个人 Team ID、证书信息或私有 container identifier 提交到仓库。

配置后必须检查构建产物，而不是只看工程设置：

```bash
codesign -dvvv --entitlements :- /path/to/Periodic.app
plutil -p /path/to/Periodic.app/Contents/Info.plist
```

产物应同时满足：

- `com.apple.developer.icloud-services` 包含 `CloudKit`。
- `com.apple.developer.icloud-container-identifiers` 包含实际 container identifier。
- `PeriodicICloudContainerIdentifier` 与 entitlement 中的 container 一致。
- 使用 Apple Development 证书和对应 provisioning profile，不是 ad-hoc 签名。

### 4.4 CloudKit Dashboard

首次只应连接 development environment。完成真实数据写入、拉取、冲突和图片验证后，再从 CloudKit Dashboard 将 schema 部署到 production。当前没有完成 production schema 发布，不能直接把本分支用于正式分发。

## 5. 已有自动化覆盖

当前新增测试覆盖以下核心路径：

- 数据集描述、设备身份、维护锁、写入串行和 store revision。
- mutation journal、连续 revision、tombstone 和上传确认。
- 旧记录 bootstrap 和重启恢复。
- `CKRecord` 编解码、system fields 和只读 inventory。
- 同字段冲突、不同字段自动合并、原子字段组和删除冲突。
- 订阅、周期、付款、模板、分类、内置分类覆盖和图片的本地双库收敛。
- 远端 inbox 重放、父子记录乱序、缺少图片时延迟应用。
- 图片 staging、哈希校验、去重、重启恢复和事务回滚。
- Coordinator 只在传输真正回到 idle 后记录成功同步时间。

这些测试使用本地 Store、测试 transport 或 CloudKit record 编解码，不等价于真实 CloudKit 多设备集成测试。

## 6. 提交前验证

本分支提交前应执行：

```bash
./script/test.sh unit
./script/build_and_run.sh --verify
git diff --check
plutil -lint Configurations/PeriodicCloudKit.entitlements
plutil -lint Configurations/Info.plist
plutil -lint Periodic/Resources/en.lproj/Localizable.strings
```

本次提交前实际验证结果：

- `./script/test.sh unit`：通过。
  - 结果包：`build/TestResults/20261005-014038-62208.xcresult`。
- `./script/build_and_run.sh --verify`：通过。
  - 产物：`build/DerivedData/Build/Products/Debug/Periodic.app`。
- 默认产物使用 ad-hoc 本地开发签名。
- 默认产物只包含 App Sandbox、网络访问、用户选择文件和调试权限，不包含 CloudKit entitlement。
- 默认 `PeriodicICloudContainerIdentifier` 为空。
- entitlement、Info.plist 和英文 localization 语法有效。
- `git diff --check` 通过。

尚未执行的验证：

- Apple Development 证书和 provisioning profile 签名。
- 真实 development CloudKit container 连接。
- 两台 Mac 的上传、拉取、离线编辑和最终收敛。
- CloudKit production schema 部署。

## 7. 后续恢复工作建议

恢复本分支继续开发时，推荐按以下顺序推进：

1. 配置独立 development CloudKit container 和开发签名。
2. 完成单机真实容器的首次启用、上传、退出重启和重新拉取。
3. 使用两台 Mac 验证离线编辑、字段合并、删除、图片和账号退出。
4. 实现候选数据库及“使用 iCloud 替换此 Mac”原子切换。
5. 完成账号切换、删除冲突副本和停止同步的恢复 UX。
6. 补充压力与故障恢复测试。
7. 冻结 record schema 后部署 production schema，再进行分发签名验证。

在第 3 至第 6 步完成前，应继续把该能力标记为开发中，并保持默认构建不访问 CloudKit。
