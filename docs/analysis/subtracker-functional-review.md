# SubTracker 与 Periodic 基础功能源码对照

> 日期：2026-10-08｜性质：静态分析与产品建议，不是已批准的需求变更。
>
> SubTracker 基线：[`d82de3e7e8188067128c39877bdb745d0f6d58ab`](https://github.com/Smile-QWQ/SubTracker/tree/d82de3e7e8188067128c39877bdb745d0f6d58ab)，提交日期 2026-10-01。
>
> Periodic 基线：`262eb66`，分析开始时工作区干净。本轮只新增分析文档，不修改应用代码。

## 1. 结论与检查边界

Periodic 最需要先补齐的是普通手动续费、全库实际支出统计和概况数量下钻。这三项已有产品需求，当前源码没有形成对应的完整入口。官网与管理链接、自定义标签、未来续费支出预览是较有价值的新增能力；试用与取消计划已有独立设计，可以在基础闭环完成后继续落地。

本轮按照页面入口、API 路由、服务计算、持久化模型和相关测试核对业务模块，覆盖 SubTracker 注册的全部 14 个路由模块，以及对应的订阅、付款、统计、预算、日历、提醒、通知、图标、附件、备份、外部迁移、汇率、AI、账号、设置和版本检查能力。Periodic 则按同一业务能力检查 View、Feature、Service、Store、Domain、Schema、需求及测试。

入口依据：[SubTracker API 装配](https://github.com/Smile-QWQ/SubTracker/blob/d82de3e7e8188067128c39877bdb745d0f6d58ab/apps/api/src/app.ts)、[Web 页面路由](https://github.com/Smile-QWQ/SubTracker/blob/d82de3e7e8188067128c39877bdb745d0f6d58ab/apps/web/src/router/index.ts)、[Periodic 导航](../../Periodic/Models/AppDestination.swift)和[依赖装配](../../Periodic/Services/AppServices.swift)。

这是业务模块层面的完整静态走查，不是逐行安全审计，也不是应用运行验收。本轮没有安装 SubTracker 依赖、启动其服务或执行两侧测试；测试证据表示阅读了测试约束，不表示测试已通过。没有新增或运行 UI 测试。

## 2. 对前次分析的更正

1. **Periodic 的续费能力不能笼统写成“已覆盖”。** 当前实现是已到期自动续费项目的人工确认；普通手动续费、提前续费、无日期及停用项目续费仍有缺口。
2. **SubTracker 的历史支出并非按原始付款币种汇总。** `summarizePayments` 读取保存的 `baseCurrency` 与 `convertedAmount`。例如 USD 10 按 7.2 记入 CNY 的记录，在历史统计中贡献 CNY 72，而不是 USD 10。改变当前汇率不会重新折算这笔记录。
3. **SubTracker 的预算比较对象是当前价格的月均/年化预估。** 它没有用付款历史作为月/年预算使用额。
4. **SubTracker 的“买断总投入”来自终生订阅当前价格。** 它不要求存在付款记录，不能作为 Periodic 的“累计实际付款”口径。
5. **试用与取消计划是 Periodic 自己的已有设计，不是 SubTracker 已实现而 Periodic 缺失的专门模型。** SubTracker 的取消操作主要是修改 `status=cancelled`，未看到独立试用计划、取消截止日或续费意图状态机。

上述第 2 项由[历史统计实现](https://github.com/Smile-QWQ/SubTracker/blob/d82de3e7e8188067128c39877bdb745d0f6d58ab/apps/api/src/services/payment-history.service.ts#L114)和[集成测试](https://github.com/Smile-QWQ/SubTracker/blob/d82de3e7e8188067128c39877bdb745d0f6d58ab/apps/api/tests/integration/payment-history-routes.test.ts#L126)共同确认。第 3、4 项见[统计计算](https://github.com/Smile-QWQ/SubTracker/blob/d82de3e7e8188067128c39877bdb745d0f6d58ab/apps/api/src/services/statistics.service.ts#L201)。

## 3. 逐模块功能对照

| 能力 | SubTracker 实际实现 | Periodic 当前实现 | 判断 |
| --- | --- | --- | --- |
| 新建、编辑、复制 | 表单创建/更新；复制为新建草稿；首次付款需显式选择 | 共享表单、独立草稿、复制新 UUID；不复制历史 | 基础能力已有，继续保持取消无写入及报价与实付分离 |
| 停用、暂停、恢复 | active / paused / cancelled / expired；暂停、取消直接改状态；修改过期日期可恢复 active | active / inactive 管理状态；过期由日期派生；支持批量停用/恢复 | 不必机械增加 paused/cancelled。上游暂停没有冻结服务日期的独立算法 |
| 删除与批量操作 | 支持批量续费、状态调整和删除；批量按项目执行并返回部分失败；active 项目禁止直接删除 | 批量停用/恢复/删除；删除先预览周期、付款数量并校验 revision | 已有维护能力。批量续费可以后置，不能照搬上游的部分成功语义 |
| 普通手动续费 | active/expired 周期项目有续费入口；保存付款并延长日期；无自动续费开关和到期日门槛 | 仅自动续费项目到期后可确认；普通周期项目无相同入口 | **现有需求缺口，优先补齐** |
| 自动续费 | 后台扫描，自动延长周期并生成 source=automatic 的付款 | 服务商自动续费是风险/待办标记，仍须用户确认 | Periodic 的人工确认符合定位，不新增后台自动记账 |
| 计费周期 | 正整数数量 × 日/周/月/季度/年 | 当前订阅限 1/3/6/12 月；历史可以显式维护覆盖日期 | 灵活周期是新增范围；先验证每 N 月需求，日/周费用口径另行定义 |
| 终生购买 | 排除续费、提醒和周期预估；保留内部日期/周期占位；总投入汇总当前价格 | 无当前到期日和周期；独立终生历史展示；实付须有付款 | 核心能力已覆盖，保留更明确的领域不变量 |
| 周期历史 | 无独立周期实体，主要依赖付款覆盖区间 | 独立周期实体、历史报价和拼车快照，可独立于付款维护 | Periodic 已有更清楚的历史事实边界 |
| 付款历史 | 全库列表、日期/来源/订阅等筛选、分页、补录/编辑/删除、revision 冲突 | 单订阅详情的付款维护、关联周期及有序消费截图 | 写入已覆盖；全库查询与汇总尚需补齐 |
| 搜索与筛选 | 搜索名称/description；状态及多标签筛选，多标签使用 AND | 搜索名称；管理状态、到期状态、服务类型、计费类型、币种等筛选 | 结构化筛选已有；标签和备注搜索可补。上游搜索并非搜索全部 notes |
| 分类与标签 | 多标签、颜色、图标、排序、数量和独立管理 | 订阅固定服务类型；模板有独立自定义分类 | 模板分类不能代替订阅标签；建议另设订阅标签能力 |
| 排序 | 名称/金额/到期日及持久化拖拽顺序；拖拽受筛选、分页等条件限制 | 表格字段排序、分组和列配置；未看到订阅手工顺序模型 | 手工排序可后置；不要以“缺排序”描述当前产品 |
| 官网与管理入口 | `websiteUrl` 校验、保存，详情可打开 | 无订阅官网或管理 URL 字段 | 建议低成本补充。单独续费/取消管理 URL 是进一步的产品建议 |
| 当前费用概览 | 基准货币换算、月均/年化、Top 10、标签分布、状态和自动续费占比 | 原币种月均/年化、分类年化、概况和贡献订阅；部分摘要参考汇率换算 | 主概览已有；费用排行属于增量，不必堆满首页 |
| 实际支出统计 | 以保存的记账币种/折算金额统计总额、年内金额、月趋势和订阅排行，可下钻 | 无全库实际支出统计入口；有单条付款明细 | **现有需求缺口，按原始付款币种实现** |
| 概况下钻 | 日历、临期表及排行等提供定位或明细交互 | 分类可展开贡献项、图标可打开详情、待续费可打开提醒；有效/过期数量卡片无 action | **STAT-06 的数量卡片下钻尚未完整实现** |
| 未来费用与日历 | 从下一续费日期重复生成计划事件；12 月预测、90 天逐日分布、月/日金额汇总 | 时间轴锚定当前到期事实，不重复推演未来续费 | 建议增加只读的未来续费金额预览；不把推演事件写进真实历史 |
| 预算 | 月/年预估预算、80% 预警、标签预算；多标签费用等分 | 无预算持久化和页面 | 可后置，先明确预算衡量实付还是价格预估 |
| 提醒计划 | 提前/当天/逾期多个节点，默认继承和单条覆盖、规则预览 | 单节点编辑；兼容旧多节点数据；日期调整、持久去重、补发、容量优先级 | 先补调度预览；多节点、逾期属于明确的范围扩展 |
| 通知渠道与诊断 | Webhook、邮件和多个推送渠道；通道测试、扫描诊断、逐通道去重和合并发送 | UserNotifications、授权指引、调度状态/重试和持久应用内提醒列表 | 保持原生本地通知；可参考诊断透明度，无须复制网络渠道 |
| 图标 | 本地上传/复用、URL 导入、站点及搜索引擎找图标，多格式 | 离线模板图标、本地 PNG/JPEG、主动 Apple 图标搜索、本地缓存 | 基础已够用；通用 URL、SVG/GIF 不是当前必需项 |
| 附件 | 附件绑定订阅，可上传或 URL 导入，最多 20 张；不是付款凭证关系 | 附件绑定付款，多图有序去重、Quick Look、引用清理 | 当前消费截图更精确；若需要授权凭证，另定义订阅级附件 |
| 原生备份 | ZIP 检查/预览、追加或替换、图片、设置、历史；资源限制与文件补偿 | `.periodicdata` 校验、UUID 冲突预览/合并、图片和历史；目标摘要过期校验 | 核心备份已实现；整体替换恢复被产品明确排除，不能列为漏实现 |
| 外部迁移 | Wallos JSON/SQLite/ZIP，映射状态、周期、标签、图片，预览后导入 | 仅原生数据包；CSV、复制导入和筛选导出明确排除 | 有用户迁移需求再做专用适配器；不默认支持所有格式 |
| 汇率与换算器 | 汇率缓存、24 小时刷新、旧缓存回退、独立货币换算器 | Frankfurter 缓存/刷新、常用币种、摘要近似换算；无独立换算器 | 不缺汇率能力；独立换算器优先级较低，付款原币种不变 |
| 试用与取消计划 | 没有专门计划模型；取消操作改 status | 已有续费意图、试用/取消计划规格，除自动续费确认外尚未落地 | 自身已有设计待实现，不是上游功能照搬项 |
| 变更记录与撤销 | 未看到独立 ChangeEvent/UndoEnvelope 等能力 | 有独立规格，未实现 | 有价值但属于后续安全维护能力 |
| AI | 文本/图片识别回填草稿，图片可经视觉或 OCR；统计摘要、Provider 协议及诊断 | 未实现，有独立规格且范围不同 | 属于独立网络扩展，不作为基础功能补齐 |
| 登录与会话 | 单一自托管账号、密码、记住登录、限流、验证码找回 | 无账号，系统用户下的本地应用 | 不补账号系统 |
| 语言、主题、设置 | 简体中文/英文、系统/浅色/深色；独立时区、基准货币等 | 同样有语言/外观；系统本地日历日、窗口/视图和货币偏好 | 主要基础能力已覆盖；不复制服务器时区设置替代本地日期规则 |
| 版本与部署 | GitHub release 检查，Docker/HTTP 服务部署 | 本地源码构建和运行；无应用内更新器 | 属于分发能力，不影响本轮订阅业务闭环 |
| 原生特有能力 | 没有对应 macOS 菜单栏、原生模板管理和拼车领域模型 | 菜单栏速览、离线/自建模板、拼车身份/成员/价格及周期快照 | 已有优势；不因对标 Web 应用削弱这些能力 |

## 4. 应先补齐的现有需求

### 4.1 普通手动续费

源码链路：详情头部的 `renewalActions` 只在 `automaticallyRenews=true` 时展示；`SubscriptionRenewalRule.preview` 同时要求 active、recurring、自动续费开启、有到期日、今天不早于到期日；Store 只有复用该规则的 `confirmAutomaticRenewal`。手工新增历史周期只新增历史并提升 revision，不等于更新当前周期的完整续费操作。

依据：[详情按钮](../../Periodic/Views/SubscriptionDetail/SubscriptionDetailHeaderView.swift)、[续费领域规则](../../Periodic/Models/SubscriptionRenewal.swift)、[存储事务](../../Periodic/Stores/SubscriptionStore.swift)、[现有 RENEW-01～05](../requirement.md)。上游对照：[手动续费服务](https://github.com/Smile-QWQ/SubTracker/blob/d82de3e7e8188067128c39877bdb745d0f6d58ab/apps/api/src/services/subscription.service.ts#L74)及[UI 可续费条件](https://github.com/Smile-QWQ/SubTracker/blob/d82de3e7e8188067128c39877bdb745d0f6d58ab/apps/web/src/utils/subscription-table.ts#L28)。

建议复用已有的周期、付款、revision 和文件处理边界，增加表达“用户手动续费”的领域规则及事务入口，不通过临时打开自动续费开关实现。

最小完成标准：

- 自动续费未开启的周期项目有续费入口，允许提前续费。
- 已过期、无到期日、停用项目按现有 RENEW-02 规则预填；停用项目保存后显式恢复使用中。
- 新周期日期、实付、付款日可确认及修改，周期与付款关联。
- 保存当前日期、周期历史和实付是同一项事务；失败回滚，重复提交不重复记账。
- 当次报价与实付可不同，未来价格/币种不被实付隐式覆盖。
- 终生项目在 UI 和领域接口均拒绝续费。

现有自动续费测试已经验证报价/实付分离和重复提交，但它不能证明普通手动续费可用。新增回归应覆盖提前、过期、无日期、停用、月末、闰年、冲突及失败回滚。

### 4.2 全库实际支出汇总与明细

`DashboardView.dashboardContent` 仅组装概况、预估费用、订阅列表和分类年化；`SubscriptionAnalytics` 只接收订阅列表项，没有付款输入；`SubscriptionStore.fetchPayments` 以单条订阅 ID 查询。付款数据存在，但没有完整的全库聚合和展示链路。

依据：[首页](../../Periodic/Views/Dashboard/DashboardView.swift)、[订阅分析](../../Periodic/Models/SubscriptionAnalytics.swift)、[付款读取](../../Periodic/Stores/SubscriptionStore.swift)及需求 COST-05～06、STAT-05～07。

建议先落地现有范围：本月、本年、自选日期范围，按每笔付款自身币种汇总金额和笔数，点击查看该范围、币种的付款明细。月度趋势和订阅支出排行放在后续增量，不阻塞基本汇总上线。

例如 CNY 100 与 USD 10 应显示两个合计，不能因当前汇率或新基准货币变成一笔历史合计。终生、停用、过期订阅的既有实付都应保留；没有付款记录显示“尚无付款记录”。

最小回归：币种精度、零元、汇总后舍入与溢出；付款日期首尾包含、跨月跨年和时区；价格/状态/类型变更不改历史；付款新增、修改、删除后合计及明细一起刷新。读取失败不能展示伪造的零金额。

### 4.3 概况数量下钻

当前 `SummaryMetricCard` 支持可选 action，但首页“当前有效”“已过期”未传 action，“待续费”才提供提醒中心入口。分类已经可展开贡献项目，不能笼统称整个首页没有下钻。

依据：[卡片组件](../../Periodic/Views/Dashboard/SummaryMetricCard.swift)和[首页概况](../../Periodic/Views/Dashboard/DashboardView.swift)，对照 STAT-06。

建议数量卡片打开本次统计范围的独立列表，沿用已有详情入口，避免修改时间轴或表格会话筛选。列表随数据变化同步刷新；核对“当前有效”是否包含终生，不能沿用只显示周期项目的“正在订阅”列表代替。

## 5. 值得新增的基础能力

| 建议 | 最小范围及实际用途 | 前置条件与边界 |
| --- | --- | --- |
| 官网、管理链接 | 订阅详情可打开官网或用户填写的账单/取消页面，使提醒后的操作有落点 | 上游只有 websiteUrl；单独管理链接属于新增建议。保存前校验 HTTP(S)，打开外部浏览器；不抓取页面或猜测取消结果 |
| 订阅标签 | 同一项目可标记“工作报销”“家庭”“低频使用”，支持管理及多标签筛选 | 保留固定服务类型，标签与模板分类分开；明确 AND/OR 筛选语义、删除标签只移除关系、复制及数据包迁移 |
| 搜索增强 | 在名称外按明确规则检索订阅备注及后续标签 | 上游 name/description 搜索值得参考，但不等于已有 notes 搜索。付款备注搜索属于全库付款功能，另走付款查询 |
| 未来续费支出预览 | 未来 30/90 天按币种列出可能续费金额、日期及项目，识别某月集中年付 | 保持真实到期事实与推演计划事件分离；到期日和付款日不是同一事实；过期、准备取消、无日期的处理需先定义 |
| 费用排行 | 同币种月均预估排行和同币种实付排行分别展示 | 复用已有汇总，不把不同口径放进同一个“花费排行”；避免默认跨币种比较 |
| 提醒调度预览 | 保存前显示将在哪天几点提醒、是否因授权或容量尚未调度 | 先复用当前单节点计划和调度状态；不承诺系统实际送达。自动续费的提前提醒是否并存要更新明确规则 |
| 多节点/逾期提醒 | 需要时允许提前、当天、逾期少量节点 | 当前 NOTIFY-02 明确不提供多时间点列表，属于范围变更；沿用相对日、去重和容量策略，不复制上游文本规则输入 |
| 月/年预算 | 在明确币种下对实付或当前价格预估设置上限并显示剩余/超额 | 优先选定一个比较口径；标签预算后置，多标签不得自动等分费用而不告知用户 |
| 灵活周期 | 覆盖每两月、两年等真实场景 | 每 N 月可先评估；日/周另定义月均/年化算法，不能直接抄固定 30 天或 4.345 周系数当精确账单 |
| 手工顺序或置顶 | 项目较多时把重要订阅放在前面 | 根据真实使用场景选择最小能力；筛选/分组下排序边界、多窗口冲突和备份需明确；不急于增加两个排序系统 |

独立月历、通用在线图标搜索、货币换算器、订阅级凭证附件可以作为后续体验选项。它们不是当前管理闭环的必要条件，不应占用手动续费和实付统计的优先级。

## 6. 已有方案与产品定位

### 6.1 试用、取消计划及续费意图

继续使用[既有生命周期规格](../extensions/5-试用取消计划与续费意图规格.md)，无需另造与管理状态混用的 paused/trial/cancelled 枚举。

优先场景是：试用即将结束、取消操作有截止日、服务商仍设置自动续费但用户准备取消。计划取消到期前仍可有效，用户确认提交或生效不等于已付款，也不能把订阅立即停用。模型、提醒和首页待处理入口一起完成，并同步数据包。

### 6.2 变更记录与撤销

[既有撤销规格](../extensions/6-变更记录与安全撤销规格.md)适合降低误删、误改和错误导入成本。它不是 SubTracker 对照出的独有功能，也不是本轮必须先建设的全应用框架。应按真实事务分步实现，继续校验 revision，并保留恢复所需的图片引用。

### 6.3 不进入基础补齐的项目

- 账号登录、Web 会话、验证码找回、HTTP 服务、Docker 部署：属于自托管产品基础设施，Periodic 保持本地个人应用。
- 远程推送、SMTP、Webhook、Apprise：增加外部账号、维护和数据传输，当前原生通知与应用内提醒中心已形成合适边界。
- AI：上游是文本/图片识别及当前预估统计摘要；Periodic 既有规格是受控工具、草稿/预览及用户确认，首版还明确排除图片识别。它们不是相同功能，应作为独立扩展重新评估范围。
- 整体替换恢复、CSV、筛选导出：当前需求明确排除。可以提出范围变更，不能当作已经承诺但漏实现的基础功能。
- 银行联动、自动扣款、后台自动生成付款：继续排除；服务商自动续费开关不是授权软件生成财务事实。
- iCloud：独立设计尚未实现，不由本轮参考项目对比直接触发权限或存储变更。

## 7. 不应直接照搬的上游实现

| 上游行为与源码 | 对 Periodic 的影响 |
| --- | --- |
| [后台自动续费](https://github.com/Smile-QWQ/SubTracker/blob/d82de3e7e8188067128c39877bdb745d0f6d58ab/apps/api/src/services/subscription.service.ts#L101)调用同一付款创建事务 | 这不是银行或服务商扣款确认；只能借鉴周期推算，不能直接产生 Periodic 的实付 |
| [历史汇总](https://github.com/Smile-QWQ/SubTracker/blob/d82de3e7e8188067128c39877bdb745d0f6d58ab/apps/api/src/services/payment-history.service.ts#L140)读取 baseCurrency/convertedAmount，并统一按 100 倍整数累计 | Periodic 应按付款原币种及该币种精度计算；JPY、KWD 不能一律按两位小数处理 |
| [统计预算](https://github.com/Smile-QWQ/SubTracker/blob/d82de3e7e8188067128c39877bdb745d0f6d58ab/apps/api/src/services/statistics.service.ts#L309)使用 monthlyEstimatedBase/yearlyEstimatedBase | 对应订阅价格预算，而非实际付款预算；界面必须正确命名 |
| [多标签预估](https://github.com/Smile-QWQ/SubTracker/blob/d82de3e7e8188067128c39877bdb745d0f6d58ab/apps/api/src/services/statistics.service.ts#L248)将月均费用等分 | 分类标签通常不是分摊比例，不能擅自解释成各标签的财务贡献 |
| [终生总投入](https://github.com/Smile-QWQ/SubTracker/blob/d82de3e7e8188067128c39877bdb745d0f6d58ab/apps/api/src/services/statistics.service.ts#L201)求和订阅当前 amount | 报价不是付款证明，不新增相同口径的“累计实付”卡片 |
| [预测事件](https://github.com/Smile-QWQ/SubTracker/blob/d82de3e7e8188067128c39877bdb745d0f6d58ab/apps/api/src/services/projected-renewal.service.ts#L31)继续投影 active/expired 项目 | 过期不表示一定继续购买；预测应明确假设，不能伪造历史或确定付款义务 |
| [批量操作](https://github.com/Smile-QWQ/SubTracker/blob/d82de3e7e8188067128c39877bdb745d0f6d58ab/apps/api/src/routes/subscriptions.ts#L138)逐项执行后返回成功/失败数量 | Periodic 已有的复合写入原子性要求不能因对标而放松 |
| [Wallos 导入](https://github.com/Smile-QWQ/SubTracker/blob/d82de3e7e8188067128c39877bdb745d0f6d58ab/apps/api/src/services/wallos-import.service.ts#L982)在导入过程中分别写标签、订阅、关联和排序；日期映射可能推进自动续费 | 若新增迁移，应采用本地可审阅预览、明确映射与事务/文件补偿；保留用户确认边界 |
| [模型](https://github.com/Smile-QWQ/SubTracker/blob/d82de3e7e8188067128c39877bdb745d0f6d58ab/apps/api/prisma/schema.prisma)使用 Float 金额和持久化 expired 状态 | 保留 Periodic 的最小货币单位/Decimal、管理状态与日期派生状态分离 |
| [剩余价值估计](https://github.com/Smile-QWQ/SubTracker/blob/d82de3e7e8188067128c39877bdb745d0f6d58ab/apps/api/src/services/subscription-value.service.ts)按周期和金额比例折算 | 不代表可退余额或可转售价值；未定义退费规则前无需新增“剩余价值”财务指标 |

这些是对可借鉴能力的语义边界分析，不表示已经对上游做了完整缺陷、安全或性能审计。

## 8. 模块与测试证据索引

SubTracker 下列路径均对应本报告固定提交；这些测试本轮只阅读，未执行。

| 模块 | 主要实现路径 | 核对的测试约束 |
| --- | --- | --- |
| 订阅与生命周期 | `routes/subscriptions.ts`、`subscription.service.ts`、Web `subscription-table.ts`、`subscription-renewal.ts` | 单条/批量实付覆盖、终生拒绝续费、active 删除限制、过期恢复、自动补期上限、复制走创建 |
| 付款与统计 | `payment-history.service.ts`、`routes/payment-history.ts`、`PaymentHistoryPanel.vue` | 补录不推进日期、编辑/删除 revision、历史汇率保留、记账币种分组、日期边界、稳定分页、首次付款可选 |
| 价格、预测和预算 | `statistics.service.ts`、`projected-renewal.service.ts`、`BudgetPage.vue`、`StatisticsPage.vue` | Top 10、终生排除周期预估、暂停排除预算、周付多事件、过期可投影、暂停/取消不投影 |
| 标签、搜索和顺序 | `routes/tags.ts`、`tag.service.ts`、`subscription-order.service.ts`、`SubscriptionsPage.vue` | 多标签 AND、标签管理、顺序读写、筛选/分页后的定位及选择 |
| 日历和首页 | `routes/calendar.ts`、`CalendarPage.vue`、`DashboardPage.vue`、`UpcomingRenewalActions.vue` | 快捷续费使用共同流程、跨页面定位订阅、月份/逐日事件和金额 |
| 提醒与通道 | `reminder-rules.service.ts`、`notification.service.ts`、`notification-merge.service.ts`、`channel-notification.service.ts`、`webhook.service.ts`、`apprise-notification.service.ts` | 提醒格式校验、同日错过时刻补发、隔日不补旧节点、合并/独立发送、不同通道只重试未发送项 |
| 图标和附件 | `logo.service.ts`、`subscription-images.service.ts`、`remote-image.ts` | 内容识别与限制、远程图片处理、待提交附件、取消清理、跨订阅引用拒绝、回滚、备份资源关联 |
| 原生备份 | `subtracker-backup.service.ts`、`backup-files.service.ts`、`streaming-zip.ts`、`SubtrackerBackupModal.vue` | 预览会话绑定、过期/取消清理、提交前再验证、超限、CRC、轻量备份、缺资源确认、追加/替换、文件补偿 |
| Wallos 迁移 | `wallos-import.service.ts`、`routes/imports.ts`、`WallosImportModal.vue` | 周期/状态/提醒映射、源时区、JSON/SQLite/ZIP 预览、标签去重及批量写入 |
| 汇率、偏好和语言 | `exchange-rate.service.ts`、`settings.service.ts`、`routes/settings.ts`、`routes/app.ts`、`SettingsPage.vue` | 设置读取/保存、语言、时区、主题及换算器交互；汇率缓存刷新/回退由服务实现核对 |
| AI | `ai.service.ts`、`ai-provider.service.ts`、`ai-summary.service.ts`、`routes/ai.ts`、`SubscriptionAiModal.vue` | 协议编码、结构化输出降级、OCR、超时/错误、模型列表、摘要缓存及来源变化后过期、语言变化 |
| 账号和分发 | `auth.service.ts`、`forgot-password.service.ts`、`routes/auth.ts`、`version-update.service.ts`、`routes/version.ts` | 凭据/会话、重置密码、通知渠道与显式找回开关、登录路由、版本展示 |

Periodic 主要核对了以下测试：

- [SubscriptionDomainTests](../../Tests/PeriodicTests/SubscriptionDomainTests.swift)：日期/金额、自动续费确认、补发/去重/容量、持久化与终生回填。
- [SubscriptionAnalyticsTests](../../Tests/PeriodicTests/SubscriptionAnalyticsTests.swift)：状态与临期边界、原币种预估、分类换算、提醒子集、全库统计与筛选、多窗口刷新。
- [SubscriptionPaymentTests](../../Tests/PeriodicTests/SubscriptionPaymentTests.swift)：实付独立、周期关联、多截图、删除解除关联、未来付款拒绝、事务边界。
- [SubscriptionMaintenanceTests](../../Tests/PeriodicTests/SubscriptionMaintenanceTests.swift)：自定义提醒、兼容多节点、复制、删除预览、冲突和显式迁移。
- [DataExchangeTests](../../Tests/PeriodicTests/DataExchangeTests.swift)：旧格式读取、图片往返、幂等合并、过期预览和失败文件补偿。
- [MoneyTests](../../Tests/PeriodicTests/MoneyTests.swift)、[WindowSessionTests](../../Tests/PeriodicTests/WindowSessionTests.swift)、[MenuBarSnapshotTests](../../Tests/PeriodicTests/MenuBarSnapshotTests.swift)：完整金额解析、币种精度、管理/到期独立和共享快照规则。
- 拼车领域、周期编辑及展示测试：身份价格、当期快照、历史不被当前配置覆盖、并发与草稿隔离。

## 9. 建议实施顺序

| 阶段 | 工作 | 分类 |
| --- | --- | --- |
| 1 | 普通手动续费；本月/本年/自选范围的原币种实付汇总及明细；有效/过期数量下钻 | 已有需求补齐 |
| 2 | 官网/管理链接；订阅标签与搜索增强；当前提醒调度预览 | 新范围建议，先明确模型和验收 |
| 3 | 沿既有规格实现续费意图、试用和取消计划，并串联提醒与待处理入口 | 已有扩展设计落地 |
| 4 | 未来续费金额预览、费用趋势/排行、预算、灵活周期及排序体验 | 按真实场景增量建设 |
| 独立评估 | 撤销、外部迁移、整体恢复、AI、iCloud 和分发更新 | 不夹带进基础补齐 |

每个阶段都应保持最小货币单位、原币种历史、Gregorian 本地日历日、独立草稿、revision、事务和文件补偿规则。新增持久化字段须同步显式 Schema 迁移及 `.periodicdata`，不能只增加一个 UI 输入框；现有业务变化须同步对应需求和单元回归，沿项目现有脚本完成验证。
