# iCloud 多端同步规格

> 版本：1.0｜日期：2026-09-23｜状态：方案设计，尚未实现。
> 依赖：[需求文档](../requirement.md)、[架构说明](../architecture.md)、[扩展规格总则](README.md)。

## 1. 目标与非目标

### 1.1 目标

- 用户可在自己的 Apple ID 私有 iCloud 空间中同步订阅、历史记录、付款、模板、分类及用户图片。
- 同一 Apple ID 下的多台 Mac 最终收敛到一致数据，并能明确显示同步状态和冲突。
- 离线时可继续读取和编辑；恢复联网后自动上传本地变更。
- 启用、停用、首次迁移和退出 iCloud 都不丢失本地数据，并提供可预览、可取消的流程。
- 不创建 Periodic 账号，不建设自有服务器，不共享用户数据库。

### 1.2 非目标

- 不支持跨 Apple ID 分享、家庭共享数据库、团队协作或 Web 端。
- 不承诺实时同步；CloudKit 推送不可用时允许在启动、回前台和用户刷新时补同步。
- 不同步窗口布局、当前筛选、侧边栏显隐、草稿、未发送 AI 对话和系统通知请求。
- 首版不提供选择单条记录同步，也不支持同时打开多个独立云数据集。
- 不使用 CSV 或 `.periodicdata` 文件作为日常同步协议；文件数据包只用于首次迁移前的安全快照和用户主动迁移。

## 2. 用户体验

### 2.1 设置入口

Settings 新增独立的“iCloud 同步”页面：

| 项目 | 行为 |
| --- | --- |
| iCloud 状态 | 显示可用、未登录、受限制、空间不足或暂时不可用 |
| 同步开关 | 默认关闭；开启前先检查账号与容器可用性 |
| 数据摘要 | 本地订阅、历史、付款、模板、图片数量及估算大小 |
| 最近同步 | 最近成功时间、待上传数量、待下载数量、最近错误 |
| 立即同步 | 触发一次拉取与推送，不阻塞本地浏览 |
| 冲突 | 有待处理冲突时显示数量和处理入口 |
| 停止同步 | 保留此 Mac 数据或移除此 Mac 云数据副本，必须二次确认 |

设置页不把“已登录 iCloud”描述为“已同步”；只有容器完成首次合并并保存检查点后才显示同步完成。

### 2.2 首次启用

```text
检查 iCloud 可用性
    ↓
只读扫描本地数据与云端元数据
    ↓
展示迁移预览：仅本地 / 仅云端 / 同 ID / 可能冲突 / 图片大小
    ↓
用户选择：合并到 iCloud / 使用云端替换此 Mac / 取消
    ↓
创建本地安全快照
    ↓
执行迁移并校验数量、引用和校验和
    ↓
切换活动数据集，发布一次全局数据变更
```

- “合并到 iCloud”按稳定 UUID 合并；名称相同不是同一记录。
- “使用云端替换此 Mac”必须先生成 `.periodicdata` 本地安全备份，并在候选数据库中完成验证后切换，不能直接删除或逐条覆盖原库。
- 迁移失败保持原活动库，保留安全快照和可重试计划。
- 首次迁移期间所有业务写入进入维护锁；普通浏览可继续使用迁移前快照。

### 2.3 日常状态

主窗口仅在需要用户行动时显示状态：离线待同步、账号退出、冲突、空间不足或持续失败。正常同步不弹成功提示。菜单栏或设置页可查看详细状态。

## 3. 同步范围

| 数据 | 是否同步 | 说明 |
| --- | --- | --- |
| subscriptions | 是 | 当前资料、管理状态、图标引用、revision 元数据 |
| subscription_periods | 是 | 历史事实，不由当前设置重建 |
| payments | 是 | 金额、币种和日期快照保持不变 |
| trial_plans / cancellation_plans | 是 | 生命周期计划使用独立 revision 和 tombstone |
| change_events | 是 | 轻量、只追加的业务变更历史；按 event ID 去重 |
| service_templates | 是 | 用户模板；内置目录仍由应用版本提供 |
| template_categories | 是 | 自定义分类及模板归属 |
| builtin category assignments | 是 | 仅同步用户覆盖，不复制内置模板 |
| icon_assets | 是 | 用户图片内容及元数据；内置图标不同步 |
| app_settings | 部分 | 业务设置可同步；设备外观、窗口和默认页面不同步 |
| notification authorization | 否 | 系统授权和待发送请求属于设备本地状态 |
| AI Provider / API Key | 否 | Provider 与密钥均为设备本地配置 |
| AI conversations | 默认否 | 由 AI 规格单独约束 |
| AI monthly reports | 否 | 报告正文和共享选择属于设备本地 AI 数据 |
| undo envelopes / local encryption key | 否 | 撤销载荷、设备密钥和窗口撤销栈不跨设备 |

## 4. 数据与标识设计

### 4.1 数据集

新增 `DatasetDescriptor`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| datasetID | UUID | 数据集稳定标识；备份、迁移和同步计划绑定它 |
| storageKind | local / iCloud | 活动存储类型 |
| schemaVersion | Int | 逻辑模型版本 |
| cloudZoneName | String? | 私有自定义 zone 名称 |
| createdAt | Date | 创建时间 |
| lastSuccessfulSyncAt | Date? | 最近完整同步检查点 |

本地库与 iCloud 库使用不同文件 URL。应用启动时只根据已提交的 `DatasetDescriptor` 打开一个活动容器，禁止容器创建失败后静默回退到另一份库。

### 4.2 同步元数据

所有可同步根记录增加：

- `recordID`：沿用业务 UUID，不因设备变化重建。
- `revision`：每次业务事务增加，用于编辑草稿和本地并发检查。
- `modifiedAt`：提交时间戳，仅作冲突排序辅助，不作为唯一正确性依据。
- `modifiedByDeviceID`：随机设备安装 ID，不包含设备名称或 Apple ID。
- `isDeleted` / `deletedAt`：同步 tombstone；确认所有已知设备越过检查点后才能清理。

子记录使用自己的 UUID。关系以稳定 ID 表示并做完整性检查，不依赖数组顺序或名称。

ChangeEvent 是只追加审计记录，CloudKit 只负责按 event ID 传播和去重；它不能替代业务 record revision、tombstone 或下述同步 journal。撤销产生新的业务 mutation 和 revert event，不修改远端既有事件。UndoEnvelope 不属于同步根记录。

本地另设不参与云同步的 `sync_mutations` journal：

| 字段 | 说明 |
| --- | --- |
| mutationID | 本次变更稳定 UUID，用于重试幂等 |
| recordType / recordID | 目标记录 |
| baseRevision | 用户开始编辑时看到的版本 |
| changedFields | 实际修改字段集合，不用整行覆盖表达局部编辑 |
| relationshipChanges | 新增、解除和删除的关系 ID |
| operation | create / update / delete |
| state | pending / uploading / acknowledged / conflicted |

业务事务与 journal 写入必须同库原子提交。只有服务端确认或冲突被处理后才能删除 journal；应用崩溃后可按 mutationID 安全重试。字段级自动合并以 journal 的 `baseRevision + changedFields` 为依据，不能从两个最终快照或设备时钟猜测用户改了什么。

### 4.3 CloudKit 适配

- 使用用户私有 CloudKit database 和 Periodic 专用 custom zone。
- SwiftData 仍是本地持久化接口；CloudKit 细节封装在 `CloudSyncAdapter`，不得泄漏到 View。
- 是否采用 SwiftData 原生 CloudKit 配置，应在原型阶段验证 schema、唯一属性、删除和迁移限制；若无法满足显式冲突与 tombstone 规则，改用 CKRecord 适配层，不降低产品语义迁就框架。
- CloudKit production schema 必须通过独立发布流程部署，Debug 数据不得进入 production 容器。

## 5. 合并与冲突规则

### 5.1 自动合并

- 不同记录的新增、修改和删除可直接合并。
- 同一订阅的不同子记录可合并，例如设备 A 新增付款、设备 B 新增周期。
- 同一根记录若基于相同 base revision 修改不同字段，可按字段变更集自动合并。
- 自动合并后生成新 revision，并保留双方来源版本用于诊断。

### 5.2 必须人工处理的冲突

- 同一字段从同一 base revision 被两个设备改为不同值。
- 一端删除、另一端在删除前版本上修改。
- 币种与金额、计费类型与周期字段等必须成组校验的字段发生交叉修改。
- 图片文件内容相同 ID 但校验和不同。
- 分类已删除，而另一设备把模板移动到该分类。

冲突页面显示业务字段的“此 Mac / iCloud”对比，不展示 CKRecord 技术字段。用户可选择一侧、逐字段合并或保留两份；“保留两份”会为副本生成新 UUID，并明确哪些历史随副本复制。

### 5.3 删除

- 删除预览仍按现有规则列出订阅、周期、付款和图片影响。
- 本地确认后写 tombstone；其他设备收到后执行相同级联语义。
- 离线设备上的旧编辑不能复活已删除记录，只能提示“已在另一设备删除”，允许用户明确复制为新记录。

## 6. 图片同步

- 用户图片以 SHA-256 内容哈希去重；CloudKit Asset 与 `icon_assets` 元数据分离。
- 下载到临时文件后验证大小、PNG/JPEG 类型、可解码性和哈希，再原子移动到受管目录。
- 数据库提交引用成功前不删除旧文件；数据库失败时清理本次临时文件。
- 图片尚未下载时显示稳定占位和同步状态，不回源 Apple URL。
- 内置模板图标始终随应用打包，云端只保存资源名，不上传二进制。

## 7. 服务接口与状态

```swift
protocol CloudSyncService: Sendable {
    func status() async -> CloudSyncStatus
    func previewEnablement(mode: CloudEnablementMode) async throws -> CloudEnablementPreview
    func enable(plan: CloudEnablementPlan) async throws -> CloudEnablementReceipt
    func syncNow(reason: CloudSyncReason) async -> CloudSyncReport
    func conflicts() async throws -> [CloudConflict]
    func resolve(_ resolution: CloudConflictResolution) async throws
    func previewDisablement(mode: CloudDisablementMode) async throws -> CloudDisablementPreview
    func disable(plan: CloudDisablementPlan) async throws
}
```

`CloudSyncCoordinator` 为 App 级单实例，串行处理同步请求并合并短时间内的重复触发。UI 只观察不可变状态快照，不直接持有 CKContainer、CKDatabase 或 ModelContext。

AI 助手或普通页面产生的已确认写入走同一业务 Service，因此以普通本地 mutation 进入同步队列；同步层不区分写入来自按钮、导入还是 AI，也不允许 AI 直接创建 CloudKit 记录。

状态必须可穷举：`disabled / checking / migrating / idle / syncing / offline / needsAccount / conflicted / failed`。失败保留底层原因供受控日志使用，并映射成用户可恢复的提示。

## 8. 安全、隐私和权限

- 仅申请 CloudKit 所需 entitlement，不申请公开数据库、共享数据库或额外文件权限。
- 设置页在开启前说明同步的数据类型、Apple ID 私有空间和停用后的保留策略。
- 日志只记录操作种类、数量、zone 和错误码；不记录名称、备注、金额、图片内容或 Apple ID。
- 不把 iCloud 可用性、容器标识或用户数据发送到自有服务。
- 完整备份导出仍需用户主动选择文件位置；iCloud 同步不是备份替代品。

## 9. 错误与恢复

| 场景 | 行为 |
| --- | --- |
| 未登录 iCloud | 保留本地数据，暂停同步，提供系统设置入口 |
| 网络离线 | 本地提交成功并排队；不反复弹窗 |
| iCloud 空间不足 | 停止上传新资产，文本变更按 CloudKit 结果处理并明确状态 |
| token 失效 | 从上次安全检查点重新拉取 zone，不清本地库 |
| schema 不兼容 | 阻止切换活动库，提示升级应用 |
| 图片失败 | 保留元数据和重试状态，不写损坏文件 |
| 部分批次失败 | 按 CKError partialFailure 分类重试，不把整批标记成功 |
| 账号切换 | 冻结原数据集并要求选择保留、导出或切换，禁止自动混合 Apple ID 数据 |

重试使用指数退避并尊重 CloudKit retry-after。用户点击“立即同步”可触发一次前台重试，但不能形成无限并发任务。

## 10. 测试与验收

### 10.1 自动化测试

- 两设备并发修改同字段、不同字段、父子记录和删除的合并矩阵。
- 离线新增、编辑、删除后恢复联网，最终数据及 revision 收敛。
- 首次启用三种结果：本地空、云端空、两端均有数据。
- 迁移中断、进程退出、空间不足、token 过期、partial failure 均保留正式数据。
- 图片重复、损坏、缺失、超限及数据库失败补偿。
- 非公历系统、跨时区和跨午夜不改变保存的年月日。
- 账号退出和切换不会把前一账号数据上传到后一账号。

CloudKit 集成测试使用独立开发容器和可替换 adapter；领域合并器必须能在无网络单元测试中覆盖。

### 10.2 验收标准

- **ICLOUD-01**：默认关闭且不产生 CloudKit 请求。
- **ICLOUD-02**：启用前展示本地/云端摘要和明确迁移选择。
- **ICLOUD-03**：任意迁移失败后原本地库仍可正常打开。
- **ICLOUD-04**：两台 Mac 离线编辑后恢复联网，非冲突变更自动收敛。
- **ICLOUD-05**：同字段冲突不被最后写入静默覆盖。
- **ICLOUD-06**：删除不会被离线旧版本自动复活。
- **ICLOUD-07**：付款和周期历史不从当前价格或日期重建。
- **ICLOUD-08**：用户图片校验后落盘，失败可重试且无半引用。
- **ICLOUD-09**：退出账号、空间不足和网络离线均有准确状态与恢复动作。
- **ICLOUD-10**：停止同步时可选择保留此 Mac 副本，并能再次启用。

## 11. 分阶段落地

1. 增加 `DatasetMetadataRecord`、持久化 `storeRevision`、统一写入协调器和维护锁；现有 `.periodicdata` 导入也改用该边界。
2. 实现 mutation journal、tombstone、纯领域合并器、图片 staging 与候选数据库安全切换；完成双本地库模拟测试。
3. 接入 CloudKit development container，仅同步订阅和历史，不开放 UI。
4. 完成首次迁移、状态页、冲突页和 tombstone 清理策略。
5. 接入付款、模板、分类和图片资产。
6. 完成账号切换、备份联动、压力测试和 production schema 部署。

每一阶段都应保持本地模式可独立运行；不得用“先打开 CloudKit 自动同步”代替迁移、冲突和恢复设计。
