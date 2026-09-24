# AI 订阅助手规格

> 版本：1.1｜日期：2026-09-23｜状态：方案设计，尚未实现。
> 依赖：[需求文档](../requirement.md)、[架构说明](../architecture.md)、[扩展规格总则](README.md)。

## 1. 目标与边界

AI 订阅助手通过自然语言查询和维护订阅，但模型永远不是数据库写入者。模型只能请求一组受控工具，应用在本地完成校验、预览、用户确认和事务提交。

### 1.1 支持能力

- 查询订阅、临期项目、费用预估、周期历史和已记录付款。
- 根据用户描述生成新建订阅草稿。
- 生成修改草稿，例如停用、恢复、调整价格、日期、分类或提醒。
- 生成删除计划，展示级联影响后由用户确认。
- 自定义多个 Provider，支持新增、编辑、删除、测试连接和选择默认 Provider。
- 每个对话可临时切换 Provider 与模型，不改变其他窗口。
- 对选定自然月生成“本地事实 + AI 解读”的月度分析，并与上月同币种数据比较。

### 1.2 非目标

- 不允许模型直接执行 SQL、操作 ModelContext、读写任意文件或调用任意 URL。
- 不允许模型自动扣款、自动续费、后台自主修改或在用户离开后继续执行写操作。
- 不把自然语言中的“已过期”自动解释为停用，也不猜测币种、金额、日期或计费类型。
- 首版不提供语音输入、图片识别、联网检索、MCP 插件或跨用户共享对话。
- Provider 不获得 iCloud 凭据、API Key、完整数据库文件或本地图片二进制。

## 2. 页面与设置

### 2.1 主界面

主侧边栏新增“AI 助手”页面，结构为：

```text
顶部：Provider / 模型选择｜新对话｜清空上下文
消息区：用户消息、助手回复、工具结果摘要、错误和重试
提案卡：变更前后对比｜影响范围｜确认执行 / 修改草稿 / 取消
输入区：多行输入｜发送｜停止生成
```

空态提供示例但不自动发送，例如“未来 30 天有哪些订阅到期？”、“帮我创建一条 Netflix 月度订阅草稿”。

读取结果中的订阅名称可打开现有共享详情。写入成功后发布一次全局数据变化，Dashboard、Timeline 和 Overview 使用相同的新快照。

### 2.2 独立设置项

Settings 新增独立“AI 助手”页面，不混入通用设置：

| 区域 | 配置 |
| --- | --- |
| 总开关 | 默认关闭；关闭时不显示发送入口、不发网络请求 |
| Provider 列表 | 新增、编辑、复制、删除、启用/停用、设为默认 |
| Provider 编辑 | 类型、名称、Base URL、API Key、模型 ID、额外请求头白名单 |
| 连接测试 | 显示 DNS/TLS/鉴权/模型不可用等分类结果，不回显密钥 |
| 数据共享 | 默认最小字段；是否允许发送备注和历史由用户单独选择 |
| 对话 | 是否保存本地历史、自动清理期限、立即清除全部对话 |
| 月度分析 | 关闭 / 仅提醒 / 自动生成、默认 Provider、报告保留期；默认仅提醒且不自动请求 Provider |

删除当前正在使用的 Provider 时，现有请求先取消；若仍有其他 Provider，要求重新选择，不能静默切换。

### 2.3 月度分析

AI 页面顶部提供“对话 / 月度分析”分段切换。月度分析不是一条隐藏的聊天提示，而是有固定事实口径、隐私预览和结果结构的独立流程：

```text
选择月份与 Provider
    ↓
本地生成确定性 MonthlyAnalysisFacts
    ↓
展示事实、缺失项和将发送字段
    ↓
用户点击“生成 AI 解读”
    ↓
Provider 返回带 fact ID 引用的结构化解读
    ↓
原生事实卡 + AI 洞察分区展示
```

- 可选择任意有付款或变更数据的自然月；当前月明确标记“截至今天”，不能冒充完整月报。
- 默认月份为最近一个已结束的自然月。
- AI 总开关启用后，月度模式默认为“仅提醒”：每月应用首次进入前台时提示“可生成上月分析”，不会在后台自动调用 Provider。
- 用户可明确选择“自动生成”。它只在应用位于前台、上一个自然月已经结束、默认 Provider 可用且聚合共享授权仍有效时运行；不会为了月报唤醒已退出的应用。
- 自动生成按 `datasetID + month + factsVersion` 幂等，每月最多自动成功生成一次。后续补录或修改使报告过时时只显示“数据已变化”，不循环自动重生成。
- 自动模式固定使用聚合共享级别，不能后台发送订阅名称或逐项变化。Provider、host、模型或共享 schema 变化后暂停自动生成，并要求重新确认。
- 手动生成按上述流程逐次展示共享预览；开启自动模式时先展示并保存“每月向哪个 host 发送哪些聚合字段”的授权，之后仅在授权未变化时免除逐月确认。
- 本地事实即使 Provider 未配置或请求失败也可查看。
- “重新生成”创建新版本，不覆盖旧报告；用户可单独删除某份或清除全部本地报告。
- 报告中的订阅名称可打开共享详情；已删除记录展示生成时短名称，但不提供失效操作。
- 报告固定分为“本月事实、与上月比较、订阅变化、需要关注、AI 建议”。没有证据的分区显示数据不足，不要求模型补齐内容。
- “AI 建议”只能提出检查、取消评估或补录建议；需要改变订阅时必须另行生成普通 `AIChangeProposal`，月报本身没有写权限。

## 3. Provider 模型

### 3.1 支持类型

首版定义三种 adapter：

1. `OpenAICompatibleProvider`：自定义 HTTPS Base URL、模型 ID，使用 Responses/Chat Completions 兼容协议之一。
2. `AnthropicProvider`：Anthropic Messages API 语义。
3. `GeminiProvider`：Google Gemini generateContent 语义。

自定义 Provider 不是任意脚本。它必须选择一个受支持协议 adapter；用户只能配置端点、模型、鉴权和白名单请求头。Provider adapter 负责把统一消息、流式事件和工具调用映射为厂商协议。

### 3.2 Provider 数据

`ai_providers`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | UUID | 稳定 ID |
| displayName | String | 用户名称，去除首尾空白，不要求全局唯一 |
| kindRaw | String | openAICompatible / anthropic / gemini |
| baseURL | String | 仅 HTTPS；Debug 可显式允许 localhost |
| modelID | String | 手动输入或连接测试后选择 |
| credentialReference | String | Keychain 引用，不是密钥正文 |
| customHeadersData | Data | 仅允许非敏感白名单键；敏感值放 Keychain |
| isEnabled | Bool | 是否可用于新请求 |
| revision | Int64 | 多窗口编辑冲突检测 |
| createdAt / updatedAt | Date | 审计时间 |

API Key 和敏感 header 保存到 Keychain，使用仅本应用可访问的 access group；不进入 SwiftData、UserDefaults、iCloud 同步、`.periodicdata` 数据包或日志。删除 Provider 时同时删除对应 Keychain 项；失败则保留可重试清理状态。

### 3.3 URL 与网络限制

- Release 仅允许 `https`；拒绝 URL 中的用户名、密码、fragment 和非 HTTP(S) scheme。
- 默认禁止重定向到不同 host；如 Provider 必须重定向，连接测试中展示并要求用户确认最终 host。
- 自定义请求头禁止覆盖 `Host`、`Content-Length`、连接管理和系统生成的鉴权头。
- 请求超时、最大响应体、最大上下文和最大工具轮次有明确上限。
- 网络层只访问当前 Provider 的已验证 host；模型不能通过工具参数改变目的地址。

## 4. 数据共享与隐私

### 4.1 默认最小上下文

默认只发送完成请求所需字段：名称、分类、管理状态、计费类型、周期、日期、金额和币种。以下内容默认不发送：

- 私人备注全文；
- 本地图片、文件路径和缓存引用；
- 付款备注；
- 其他对话、设置、设备信息和日志；
- API Key、iCloud 状态和数据集文件。

请求需要备注或历史时，工具先返回“需要额外授权”的本地结果；UI 展示将发送的字段和目标 Provider，用户可以仅本次允许或拒绝。权限不得由模型自行升级。

### 4.2 对话保存

- 默认保存于设备本地，用户可改为“关闭窗口即删除”。
- 对话正文不进入 iCloud 同步；未来若支持必须单独设计和授权。
- 工具结果只保存用于理解回复的摘要，不复制整库快照。
- 清除对话为本地可确认操作，不删除订阅数据。

每次发送前在输入区附近显示当前 Provider host。首次向新 host 发送时展示隐私确认。

### 4.3 月度分析共享范围

月度分析默认只向 Provider 发送聚合事实：月份、币种代码、付款合计、付款笔数、续费及变更数量、分类聚合、临期数量和本地计算的同币种环比。默认不发送订阅名称、备注、付款备注、事件字段差异或单笔金额。

用户可在生成前选择“包含订阅名称与逐项变化”，仅对本次报告授权。预览必须列出记录数量、字段种类、Provider 名称和 host。即使授权逐项数据，仍不发送备注正文、UndoEnvelope、图片、文件路径、对话或密钥。

保存的报告记录以下来源信息：报告月份、事实快照摘要、生成时间、Provider ID、模型 ID、共享级别和输出版本；不复制 API Key。报告默认设备本地保存，和 AI 对话一样不进入 iCloud、`.periodicdata` 或变更记录正文。

用户可以设置报告保留 3、6、12 个月或永久，默认 12 个月。到期清理只删除 AI 报告，不删除付款、订阅或 ChangeEvent，也不生成业务变更事件。

## 5. 对话与请求状态

`AIConversationStore` 是每窗口 Feature 状态，持有消息、选中 Provider、请求 generation、待确认提案和取消句柄。Provider 配置与 Keychain 服务为 App 级依赖。

请求状态：

```text
idle → preparing → awaitingNetwork → streaming
     → awaitingToolResult → streaming
     → proposedChange → executing → completed
     → cancelled / failed
```

- 新消息取消当前尚未提交的生成请求，旧流式响应不得追加到新对话。
- 最多允许有限轮工具调用；检测重复工具调用并终止循环。
- 切换 Provider 不重放旧请求；重试创建新的 request ID。
- 应用进入后台可取消生成；已经确认的本地数据库事务要么完成，要么回滚。

## 6. 受控工具设计

### 6.1 读取工具

| 工具 | 输入 | 输出 |
| --- | --- | --- |
| `search_subscriptions` | 名称、状态、分类、计费类型、币种、分页 | 精简列表和稳定 ID |
| `get_subscription` | subscriptionID、字段范围 | 当前 revision 的详情 |
| `get_upcoming` | 7/15/30 天 | 与产品规则一致的临期列表 |
| `get_forecast` | 可选币种、分类 | 分币种月均和年化，不跨币种合计 |
| `get_periods` | subscriptionID、年份范围 | 周期历史，不伪装成付款 |
| `get_payments` | subscriptionID、日期范围 | 实际付款快照 |
| `get_lifecycle_plan` | subscriptionID | 续费意图、试用与取消计划的精简状态 |
| `get_change_events` | subscriptionID、月份、来源、分页 | 不含敏感正文的结构化活动摘要 |
| `get_monthly_analysis_facts` | 月份、共享级别 | 本地权威月度事实及 fact IDs |

读取工具通过现有 Query Service，使用分页和结果上限。超限时返回继续查询 token，不把全库自动塞入上下文。

月度分析工具只能读取已经生成并绑定 dataset revision 的事实快照，模型不能通过工具参数扩大到其他月份或更高共享级别。事实快照包含：

- 选定月与上月按付款币种分别汇总的实际支出和笔数；
- 当月续费、首次付款、补录付款及零元付款数量；
- 按变更记录统计的新建、停用、恢复、价格变化、试用转换和取消计划变化；
- 报告生成时未来 30 天临期及生命周期待处理数量；
- 按分类和币种分组的金额，不跨币种合计；
- 数据缺口，例如变更记录尚未覆盖完整月份。

历史月的实际付款和变更使用其真实业务日期或事件时间；“未来 30 天”和当前费用预估属于生成时快照，必须单独标注，不能伪装成历史月末状态。

ChangeEvent 仅覆盖功能启用后的真实事务。报告月份早于 `historyCoverageStart` 或跨越活动历史清理边界时，变更趋势必须标为“不完整”，不得根据当前订阅快照反推当月新增、调价或停用次数；付款聚合仍可按现存 PaymentRecord 的业务日期独立计算。

### 6.2 写入工具

模型侧只可调用“准备提案”工具：

- `propose_create_subscription`
- `propose_update_subscription`
- `propose_set_management_state`
- `propose_renewal`
- `propose_delete_subscriptions`
- `propose_add_period`
- `propose_add_payment`
- `propose_set_renewal_intent`
- `propose_trial_transition`
- `propose_cancellation_transition`

这些工具返回 `AIChangeProposal`，不写数据库。提案包含：

| 字段 | 说明 |
| --- | --- |
| proposalID | 本地随机 ID，不交由模型指定 |
| kind | 穷举的变更类型 |
| summary | 面向用户的简要说明 |
| before / after | 字段级对比；新建没有 before |
| affectedIDs | 实际记录 ID |
| expectedRevisions | 生成提案时读取的版本 |
| cascadeImpact | 删除涉及的周期、付款和图片数量 |
| validationWarnings | 重叠周期、可能重复、日期未知等 |
| expiresAt | 防止长期保存的旧提案执行 |

### 6.3 确认与执行

- 每个写提案必须在原生确认卡中由用户明确点击，聊天中的“好的”“继续”等文本不能代替按钮确认。
- 更新和删除在执行前重新读取 revision；变化后标记提案过期并展示最新差异。
- 新建必须让用户确认名称、计费类型、金额和币种；周期型还需合法周期，日期可按现有规则为空。
- 删除继续调用正式删除预览和级联事务；AI 不获得额外删除能力。
- 多条变更默认逐条选择；用户确认批量执行时使用单一计划和明确原子性。
- 成功回执只包含实际提交结果；模型生成的文字不能冒充成功。
- 生命周期提案必须使用正式状态机；“不想用了”不能直接推断为停用、删除或 confirmed 取消。
- AI 没有执行 UndoEnvelope 的工具；只能生成打开活动页或建议撤销的提案，由用户在原生界面确认。

## 7. 领域校验

所有模型参数视为不可信输入，在本地域重新解析：

- 金额只接受十进制字符串和明确币种，转换为最小货币单位；拒绝负数、溢出和超精度。
- 日期只接受 `YYYY-MM-DD` Gregorian 日期；“下个月”“年底”等先在提案中解析并展示具体日期。
- recurring 必须使用受支持周期；lifetime 清空到期、周期和提醒，但必须在对比中展示。
- 停用与过期保持不同语义；模型不得把派生状态写入管理状态。
- 普通编辑不自动生成周期或付款；需要历史时生成单独提案。
- 不跨币种求总额，不自动换汇。
- 工具参数中的名称、备注和 Provider 文本不能被解释为新的工具指令。

## 8. Prompt injection 与工具安全

- 系统提示只定义产品语义，真正权限由本地工具注册表决定。
- 工具参数采用 Codable 结构和穷举枚举；未知字段拒绝或忽略时记录诊断。
- 模型无法看到未注册工具，也无法构造任意 selector、URL、SQL、路径或命令。
- 从订阅备注读取的文本始终标记为用户数据，不提升为系统指令。
- 工具结果包含 request ID、conversation ID 和 generation；旧请求结果不能应用到新对话。
- 达到工具轮次、结果条数或 token 上限后停止并向用户说明，不自动扩大数据范围。

## 9. 服务接口

```swift
protocol AIProviderService: Sendable {
    func providers() async throws -> [AIProviderDTO]
    func save(_ input: AIProviderInput) async throws
    func delete(id: UUID, expectedRevision: Int64) async throws
    func testConnection(id: UUID) async -> ProviderConnectionReport
}

protocol AIConversationService: Sendable {
    func stream(
        request: AIConversationRequest
    ) -> AsyncThrowingStream<AIConversationEvent, Error>
}

protocol AISubscriptionToolService: Sendable {
    func executeRead(_ request: AIReadToolRequest) async throws -> AIReadToolResult
    func prepare(_ request: AIWriteToolRequest) async throws -> AIChangeProposal
    func executeConfirmed(
        proposalID: UUID,
        confirmationToken: AIConfirmationToken
    ) async throws -> AIChangeReceipt
}
```

Provider adapter 只处理协议转换；它不依赖 Store。工具服务只调用领域 Service；它不依赖具体 Provider。View 负责显示流、提案和用户意图，不承载 JSON schema、鉴权或数据库事务。

```swift
struct MonthlyAnalysisFacts: Sendable {
    let reportingMonth: LocalMonth
    let generatedAt: Date
    let datasetRevision: Int64
    let factsVersion: Int
    let facts: [MonthlyFact]
    let warnings: [MonthlyAnalysisWarning]
}

protocol AIMonthlyAnalysisService: Sendable {
    func prepare(
        month: LocalMonth,
        sharing: MonthlyAnalysisSharing
    ) async throws -> MonthlyAnalysisPreview
    func generate(
        previewID: UUID,
        providerID: UUID
    ) -> AsyncThrowingStream<MonthlyAnalysisEvent, Error>
    func reports(month: LocalMonth?) async throws -> [MonthlyAnalysisReport]
    func deleteReport(id: UUID) async throws
}
```

每个 `MonthlyFact` 有稳定 fact ID、类型、币种或日期维度及本地格式化所需原值。模型输出使用版本化结构，并为每条洞察列出 `referencedFactIDs`。未知 fact ID、越权字段或格式错误不能进入正式报告。

原生事实卡是金额和计数的权威展示；AI 文本明确标记为“AI 解读”。模型在正文中生成的未引用数字不替代本地事实，也不能驱动筛选、提醒或写操作。

## 10. 错误处理

| 错误 | 用户结果 |
| --- | --- |
| Provider 未配置/已禁用 | 打开 AI 设置或切换 Provider |
| API Key 缺失 | 聚焦对应 Provider 的密钥字段 |
| TLS/网络失败 | 保留输入并允许重试，不清空对话 |
| 401/403 | 提示检查密钥，不记录响应中的敏感正文 |
| 429 | 尊重 retry-after，不自动无限重试 |
| 模型不存在 | 选择或填写其他模型 ID |
| 响应格式错误 | 保留已完成文本，将工具调用标为失败 |
| 工具参数无效 | 不执行，向模型返回结构化校验错误一次 |
| revision 冲突 | 保留提案，展示最新值并允许重新生成 |
| Provider 删除 | 取消关联请求，保留本地对话正文 |
| 月度事实过期 | 数据 revision 变化后要求重新生成预览，不把旧事实发送给 Provider |
| 月度解读失败 | 保留本地事实与共享选择，允许重试或切换 Provider |

流式响应可部分显示，但只有完整、通过解析的工具调用才能进入提案阶段。

## 11. 可访问性与交互

- 新 token 到达时不逐字抢占 VoiceOver；一段完成后再播报摘要。
- “停止生成”“确认执行”“取消提案”等按钮有明确标签和键盘操作。
- 提案差异不只靠颜色，使用“原值/新值”和字段名称。
- Reduce Motion 下不使用逐字动画；长回复支持选择、复制和滚动位置保持。
- 删除和批量操作的危险按钮使用系统 destructive role，并与普通发送按钮分离。
- 月度分析的本地事实与 AI 解读使用不同标题和可访问性分组，不能只靠颜色区分。
- 图表或环比箭头同时提供币种、原值、比较月份和文字趋势；金额隐藏设置不影响事实计算，但在屏幕与 VoiceOver 中都隐藏展示。

## 12. 测试与验收

### 12.1 自动化测试

- 各 Provider adapter 的请求、流式分片、工具调用、错误映射和取消。
- URL 验证、重定向、header 白名单和 Keychain 保存/删除失败。
- 金额精度、日期、终生/周期不变量、revision 冲突和提案过期。
- Prompt injection 样本不能调用未注册工具、绕过确认或读取额外字段。
- 旧 generation 的流和工具结果不能覆盖新对话。
- 删除提案的级联数量与正式删除预览完全一致。
- Provider CRUD 的多窗口 revision 冲突。
- 月度实际支出按业务日期、币种和首尾包含规则聚合，环比不跨币种。
- 当前月“截至今天”、历史月事实和生成时未来快照具有正确标签。
- 变更历史不完整时展示数据缺口，不从当前记录反推过去状态。
- 聚合共享不包含名称和单笔金额；逐项共享仍不包含备注、UndoEnvelope 和密钥。
- dataset revision 变化使旧月度预览失效，旧流式结果不覆盖新报告。
- 模型引用未知 fact ID、输出越权字段或虚构写操作时拒绝正式保存。

网络单元测试使用自定义 URLProtocol 或 adapter stub，不访问真实 Provider。真实连接仅在手动集成测试中使用测试密钥。

### 12.2 验收标准

- **AI-01**：默认关闭，不配置 Provider 时不产生 AI 网络请求。
- **AI-02**：Settings 有独立“AI 助手”项，可新增、编辑、删除、测试并选择默认 Provider。
- **AI-03**：API Key 只存在 Keychain，不进入数据库、备份、同步和日志。
- **AI-04**：查询结果与现有日期、金额、状态及统计规则一致。
- **AI-05**：任何新增、修改、续费、付款或删除都先形成本地提案并通过原生按钮确认。
- **AI-06**：revision 变化后旧提案不能执行。
- **AI-07**：删除提案显示完整级联影响，取消不产生写入。
- **AI-08**：用户可停止流式请求，旧响应不会污染后续对话。
- **AI-09**：Provider 失败保留输入和草稿，不以成功文案伪装失败。
- **AI-10**：默认不发送备注、图片、密钥、文件路径或全库数据。
- **AI-11**：恶意备注或模型输出不能绕过工具白名单和确认门槛。
- **AI-12**：写入成功后所有窗口通过统一数据事件刷新。
- **AI-13**：月度分析的金额、数量和环比由本地规则生成，AI 不承担权威计算。
- **AI-14**：不同币种分别分析，不能换汇或生成跨币种总金额。
- **AI-15**：默认只发送聚合事实；包含名称和逐项变化必须按报告单独授权。
- **AI-16**：Provider 不可用时仍能查看本地月度事实，失败不保存为成功报告。
- **AI-17**：新月份提醒不会自动发起网络请求，生成前始终展示 Provider host 和共享范围。
- **AI-18**：AI 洞察引用有效 fact ID，并与原生权威事实明确区分。
- **AI-19**：自动模式每月只为上一个完整自然月生成一次，应用退出时不会后台运行。
- **AI-20**：自动月报只发送已授权聚合事实；Provider、host、模型或共享 schema 变化后暂停并重新确认。

## 13. 分阶段落地

1. Provider 数据模型、Keychain 服务、独立设置页和连接测试。
2. 统一 Provider adapter、流式对话 UI、取消及 generation 防护。
3. 只读工具：搜索、详情、临期和费用查询。
4. 新建与修改提案，复用现有编辑校验和 revision。
5. 续费、周期、付款、删除及批量提案。
6. 月度本地事实、变更事件聚合、共享预览和结构化 AI 解读。
7. 隐私授权、攻击性测试、可访问性和手动 Provider 兼容矩阵。

写工具必须晚于正式业务 Service 完成；不得为了 AI 先实现一套绕过主应用规则的平行 CRUD。
