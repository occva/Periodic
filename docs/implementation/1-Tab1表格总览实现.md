# 1. 表格视图与模板管理实现

> 版本：1.2｜日期：2026-09-22｜状态：待实现的详细设计。
> 产品依据：[需求文档](../requirement.md)。当前 Periodic 仍是基础框架，本文不表示业务代码已完成。

本模块覆盖订阅表格、快捷视图与分组、服务模板库、搜索筛选、详情、新增编辑、图标、周期续费、终生购买、付款历史及删除。按「需求 → 功能 → 数据库 → 表 → 字段 → 接口 → 实现 → 验收」展开，共享业务能力也在本文定义。

另外两个完整模块为 [2-Tab2时间线日历实现](2-Tab2时间线日历实现.md) 和 [3-Tab3统计仪表盘实现](3-Tab3统计仪表盘实现.md)。三个 Tab 使用同一数据库；文档按 Tab 组织，不按技术层继续拆文件。

## 1. 需求与模块边界

| 需求 | 功能落点 | 数据与接口 | 完成结果 |
| --- | --- | --- | --- |
| TABLE-01～09、NAV-05～08 | 表格、快捷视图、分组、组合筛选、排序、底栏 | subscriptions；`SubscriptionService.query` | 可查、可选、金额口径清楚 |
| CATALOG-01～06 | 内置/自建服务模板、预填、维护 | 本地目录 + service_templates；TemplateService | 选模板后确认表单，不自动产生订阅 |
| DATA-05～06、EDIT-05、RENEW-05 | 周期/终生类型、一次性价格 | billingKind + 可空 cycleMonths；维护及派生规则 | 终生不续费、不提醒、不折算费用 |
| DETAIL-01～08、PERIOD-01～07、NAV-09 | 共享详情、手动周期、按年历史 | subscription_periods + payments 可选关联；PeriodService | 默认当年；周期、报价、实付分别有据可查 |
| DATA-01～04、EDIT-01～04 | 共享表单、详情、图片、付款历史 | subscriptions / payments / icon_assets；维护服务 | 当前资料与历史快照互不覆盖 |
| RENEW-01～04 | 确认续费 | `previewRenewal`、`renew` | 一次提交更新周期并新增一笔付款 |
| LIFE-01～04 | 复制、停用、恢复、单条和批量删除 | `copyDraft`、`setState`、`previewDeletion`、`delete` | 删除影响明确，取消无写入 |
| RULE-01～04、COST-01～06 | 共享日期及费用规则 | `DateRules`、`CostCalculator` | 三个 Tab 使用相同计算口径 |
| TECH、NAV、UI、QA | 应用装配、多窗口、持久化、可访问性 | AppServices、WindowSession、StoreActor | 原生、离线优先；仅用户主动搜索品牌图标时请求 Apple |

### 1.1 页面归属

- 主窗口使用 `WindowGroup`，以 `NavigationSplitView` 侧边栏依次呈现 `dashboard` 首页、`timeline` 时间轴视图、`overview` 表格视图、`templates` 模板管理。
- 首页是默认入口；详情、新建、编辑、续费、付款维护均为共享内容，其他页面调用同一套组件。
- 偏好设置继续使用独立 `Settings` 场景。提醒设计写在 Tab2；设置、CSV、备份恢复设计写在 Tab3，这只是文档归属。
- 接口全部为本地 Swift 进程内调用，不设计 HTTP、账号、云端数据库或自动扣款。

### 1.2 状态归属

| 状态 | 持有者 | 持久性 |
| --- | --- | --- |
| 活动数据集、业务服务、数据库、变化事件 | AppServices | App 级唯一实例 |
| 当前 Tab、侧边栏、窗口尺寸 | 每窗口根视图 | SceneStorage / 系统窗口恢复；通用默认偏好见 Tab3 |
| 搜索和五种筛选 | `WindowSession.filter` | 窗口会话内共享给 Tab1、Tab2；计费类型为新增维度 |
| 临期范围 7/15/30 天 | `WindowSession.dueHorizonDays` | 默认 15，Tab2/Tab3 共享范围值，查询数据范围各自明确 |
| 服务库搜索/分类/来源 | TemplatePickerStore | 独立于已有记录筛选，关闭服务库后可重置 |
| 表格排序、多选 ID、当前弹窗 | OverviewStore / 窗口路由 | 会话状态 |
| 编辑草稿、字段错误、保存状态 | 当前表单 | 值类型；取消时丢弃 |
| 详情年份、历史子视图、局部滚动 | SubscriptionDetailStore | 每次打开默认当年，编辑返回保留；不写全局偏好或主页面筛选 |
| 外观、提醒、视图默认偏好 | SettingsStore | 同库 app_settings；外观可单向镜像至现有 AppStorage |

## 2. 功能与交互设计

### 2.1 表格布局

工具栏包含新建下拉（空白/从模板/CSV）、搜索、筛选、排序、分组、显示列、多选操作和设置入口。表格使用原生 `Table`，最小窗口内容尺寸 960 × 640 点，宽度不足允许水平滚动，工具栏使用系统溢出菜单。截图中缺失的列头仍须实现，错位和重复新建占位不复制。

| 顺序 | 列 | 来源与显示 | 交互 |
| --- | --- | --- | --- |
| 1 | 图标与名称 | 图片优先，失败回退 symbolName；名称单行截断 | 悬停完整名称；详情可读全文 |
| 2 | 管理状态 | 周期 active 显示订阅中；终生 active 显示使用中；inactive 显示已停用 | 不与到期状态合并 |
| 3 | 服务类型 | 固定分类中文名称 | 可筛选 |
| 4 | 到期日期 | 周期型 `YYYY/MM/DD`，未知“—”；终生“永久有效” | 没有具体日期的记录置后 |
| 5 | 剩余天数及比例 | 有符号整数；可选小型比例条；终生/未知“—” | 天数排序；比例不代替文字 |
| 6 | 到期状态 | 日期未知、已过期、今天到期、7 天内、30 天内、正常、永久有效 | 文字和状态图形配合颜色 |
| 7 | 计费方式 | 月度 / 季度 / 半年 / 年度 / 终生 | billingKind 决定是否有周期 |
| 8 | 周期/一次性金额与币种 | 默认如 `CNY 88.00`；可在设置切换为 `¥88.00（人民币）`；共享符号须追加币种名称消歧，如 `¥88（日元）`；终生价格标明一次性 | 价格不是付款记录 |
| 9 | 月均预估 | 周期价格 ÷ 周期月数；终生“—” | 不适用不显示零 |
| 10 | 年化预估 | 周期价格 × 12 ÷ 周期月数；终生“—” | 币种内有效数值排序，不适用置后 |
| 11 | 备注 | 多行内容摘要 | 悬停或详情读取完整内容 |

底栏展示「当前结果数 / 全库总数」、结果中的有效周期预估及互斥排除数量。先分 inactive，再分 active lifetime，再分 active recurring 的未知/过期/预估参与者，五项和等于结果数。各币种分别显示月均和年化；没有参与者显示“无参与预估的周期订阅”，免费有效周期型显示真实零预估。

### 2.2 搜索、筛选和排序

1. 搜索仅匹配名称：搜索词去除首尾空白，忽略大小写，保留用户名称内的其他字符；使用统一 Unicode 比较实现。
2. 筛选维度为管理状态、到期状态、服务类型、计费类型、币种。每个维度可选多值，维度内为“或”，维度间为“且”；空集合代表全部。日期未知只匹配无日期 recurring，永久有效只匹配 lifetime。
3. 默认按到期日升序，再按名称及 UUID 稳定排序；日期或天数降序时无日期仍置后。
4. 年化排序先按币种代码升序分组，再按该币种内未舍入年化值升降序，终生的 nil 在本币种组内始终置后，最后以名称及 UUID 打破相同值。单币种筛选时自然只剩一个组。
5. Tab2 复用搜索筛选条件，但保持自己的日期升序；Tab3 始终读取全库。
6. 搜索可约 150 ms 防抖。快速变更时取消旧任务，并以请求序号防止迟到响应覆盖新结果。
7. 结果刷新后，多选集与当前结果 ID 取交集；批量动作只处理仍可见的选择，不隐式操作被筛掉的项目。

概况的四类 summaryBucket 与底栏的五类 forecastBucket 分开：前者将 active lifetime 计入有效，后者单列其“不参与周期预估”数量。到期状态始终显示真实日期/终生性质，不被管理状态覆盖。

### 2.2.1 快捷视图、分组和列配置

| 快捷视图 | 对共享 filter 的显式操作 |
| --- | --- |
| 全部项目 | 清除全部搜索/筛选，分组及列配置保留 |
| 使用中 | managementStates={active}，保留计费类型/服务类型/币种/搜索，清除到期状态限制 |
| 已过期 | managementStates={active}、billingKinds={recurring}、expiryStatuses={expired}，其余保留 |
| 已停用 | managementStates={inactive}，清除到期状态限制，其余保留 |
| 终生 | billingKinds={lifetime}，清除到期状态限制，其余保留 |

所有条件以标签显示；快捷视图与条件不再一致时选中“自定义”，不能仍显示错误的“全部”。需要查所有过期（含停用）可手动取消 active 限制。

分组为 none/category/managementState。服务类型按固定分类顺序，管理状态按 active、inactive；组内沿用表格排序。分组头显示结果数、有效周期预估及各币种小计。折叠只是隐藏行，不排除底栏或“当前结果导出”；“全选当前结果”覆盖折叠行并明确总选择数量。`TableSnapshot` 返回平铺 rows 和 groups 的行 ID 映射，两者来自同一查询。

列 ID 使用稳定键，可显隐和调宽，名称列强制可见；提供恢复默认。UI 技术优先验证 Table 分组 API；若原生 Table 无法满足可访问的分组头，使用带共享列规格的分组容器，不能因技术选择丢失列对齐、键盘多选和横向滚动。分组/列配置写入 Tab3 视图偏好，查询事实不变。

### 2.3 详情与共享表单

单击名称链接、双击行或单选后 Return 打开详情；单击行空白区域只选择，修饰键多选不触发详情。右键保留直接编辑。详情复用下述结构，付款视图按付款日倒序、创建时间倒序、UUID 排序。

| 表单分区 | 字段与默认值 | 校验及保存含义 |
| --- | --- | --- |
| 基本信息 | 名称空、类型其他、状态订阅中 | 名称 trim 后非空；同名允许 |
| 计费与价格 | billingKind 默认 recurring；周期型月度、终生无周期；币种 CNY、金额为空 | 金额必填非负；终生标签改为一次性价格 |
| 有效期 | recurring 起止可空；lifetime 开始日可空、到期强制空 | 周期起止齐全 start ≤ end；终生显示永久有效 |
| 预估 | 月均、年化 | 周期草稿实时计算；不完整/终生显示“—” |
| 图标 | 内置 PNG/JPEG、Apple 图标或未设置 | 已设置的图标不可用时显示不可用状态，不替换成 SF Symbol；只有未设置图标时稳定选择一个 SF Symbol 占位 |
| 提醒与备注 | 周期单条提醒默认开启；终生固定关闭、隐藏时间提醒输入；备注空 | 周期还受全局开关和权限约束 |
| 首次付款（仅新建） | “同时登记首次付款”默认未勾选 | 勾选才显示并校验付款字段，和订阅同事务保存 |

首次付款日期默认今天，金额和币种可从当前价格预填但允许独立修改，覆盖周期默认使用当前起止日期，未知可空。取消勾选不提交隐藏草稿。普通编辑不生成付款记录。

普通新建/从模板新建在日期足够完整时，同事务写一条 initial 周期（recurring 起止齐全；lifetime 有开始日）；金额为当前报价快照。可选首次付款关联该条周期。日期不足时不制造周期，付款可以无周期关联。复制草稿显式带 historyPolicy=none，不复制或重建历史；CSV 同样不生成周期记录。

切换为终生时在草稿内清空 cycleMonths/expiry、关闭提醒，并展示影响提示；保存确认才改库，取消保留原记录。切回 recurring 草稿默认月度、expiry=nil、提醒开启，金额数值保留但标签改为周期价格，要求用户核对。仅合法保存改变类型，历史付款金额及覆盖日期不随类型变化；终生首次付款 periodEnd=nil。

表单使用独立 Draft，不直接绑定 SwiftData 实体。保存中禁用重复操作；失败保留输入并定位错误字段；取消或关闭有修改的 Sheet / 窗口先确认放弃。只保留一个根 Sheet，详情中的编辑用内部路由切换，避免连续叠加多个弹窗。

### 2.3.1 共享详情布局与打开行为

```text
大图标 + 名称 + 管理状态       编辑 / 设置当前周期 / 续费 / 更多 / 关闭
基础资料：当前价格、计费方式、开始/到期、服务类型、提醒、备注
只读指标：到期标签、剩余天数/比例、月均预估、年化预估
历史区年份栏：上一年 | 2026 年（默认当年）▼ | 下一年 | 当年 | 全部年份
历史子视图：周期记录 | 付款记录       手动添加周期 / 补录付款
周期表：次数 | 周期类型 | 开始 | 结束 | 本期价格 | 关联付款数 | 备注 | 操作
付款表：付款日 | 类型 | 实付/币种 | 覆盖日期 | 关联周期 | 备注 | 操作
历史摘要：本次匹配周期数 / 总周期数；所选年实付（按付款日、分币种）
```

截图用于内容层级，产品采用可缩放的原生 Sheet，内容可滚动、表头清晰。图片区可换图标，当前资料编辑通过共享表单；计算区不提供输入控件。截图“消费金额”改为“每周期价格/一次性价格”，另设“累计已记录实付”和“所选年已记录实付”，不能都称消费金额。

列表、日历点/标签、临期卡片、通知和统计记录详情均传同一 subscriptionID。关闭恢复来源页位置及条件，不因详情默认年份而改变时间轴范围。直接编辑菜单仍可跳到编辑子状态，保存或取消后回到原详情/来源。

### 2.3.2 年份切换与跨年归属

`HistoryYearSelection = currentYear / year(Int) / all`，默认 currentYear，以共享 Clock 的系统时区公历年解析。历史区两个子视图共用选择；顶部当前资料、状态与折算值始终按真实今天计算。

周期匹配选定年：普通/自定义周期 `startDay ≤ Dec31 && endDay ≥ Jan1`；终生记录只按 startDay 在该年内。付款匹配同订阅且 paymentDay 在该年内，与周期是否匹配无关。因此 2025-12-15～2026-01-14 的周期在两年都可见且显示完整日期，但 2025-12-15 的实付只计 2025；不按天数分摊报价或实付。

年份菜单包含当前年、周期实际覆盖年份和付款年份，支持上一年/下一年访问没有记录的年份，边界 1…9999；“全部”时上/下一年禁用，点当年或选具体年后恢复。超长区间的年份菜单虚拟化生成，不向数据库写每年副本。

默认 currentYear 跨元旦自动更新；手选 year(2025) 保持 2025。同次详情中切换历史子视图、编辑保存、刷新数据均保留年份，真正关闭再进入重置默认。年份切换期间若正在编辑则先处理未保存草稿，不默默丢弃输入。请求 generation 保证快速切年旧响应不覆盖新年。

当年无历史展示空态和“查看全部年份 / 添加周期”，不自动选最近有记录的旧年。新增保存到其他年时提供跳转提示，默认保留当前筛选。跨年周期只算一条全量周期；表内序号先在全量记录按 startDay/createdAt/UUID 升序生成，年份过滤与显示倒序后保留该序号。补录更早历史可能改变显示序号，操作始终使用 UUID。

| 样例（假设当前 2026 年） | 2026 年周期表 | 2026 年实付 |
| --- | --- | --- |
| 2025-12-15～2026-01-14，2025-12-15 付款 CNY 30 | 显示完整跨年周期 | 不计入，付款在 2025 年 |
| 2026-06-01～2027-05-31，只记录报价 CNY 99 | 显示完整跨年周期 | 没有付款，不增加支出 |
| 2024-05-01 取得终生，2024 年付款 CNY 199 | 不显示；切 2024/全部可见 | 不计入；顶部仍可显示永久有效 |
| 只有 2023 年周期/付款 | 当年空态，保留默认 2026 | 显示当年无付款，累计仍可查询 |

### 2.3.3 手动维护周期与当前设置的关系

手动周期表单包含类型、开始、结束、本期价格（可未知）、币种、备注，以及默认不勾选的“同时登记付款”。周期类型可以与当前订阅不同，例如旧年度、现在月度；预设类型只提供日期建议，用户手动改结束日后不强行重置。“自定义日期”是历史区间类型，不能自动成为当前价格折算周期。

普通/自定义开始结束必填且 start≤end；终生只填开始。默认结束建议为 start 加 1/3/6/12 月减一天，可改；按续费入口生成的建议仍遵守 Tab1 第 5.3 节。相邻段首尾都包含，重叠给提示并要求确认，允许记录服务赠送或重复购买，不擅自合并。未来周期可登记，勾选付款时 paymentDate 仍不得晚于今天。

手动新增/编辑只保存历史，不改主表格/主日历的当前周期及提醒。详情底部始终提供“添加记录”，空状态中也提供同一入口；点击后在表格中追加一条行内草稿。周期表支持双击行或使用操作列进入行内编辑；周期、开始、结束、金额和币种先写入独立草稿，用户明确保存后才作为一项事务提交，取消不产生写入，失败保留草稿。点击“应用到当前设置”另行预览：复制开始/结束及类型，预设周期带入对应 M，custom 需用户选择 1/3/6/12；lifetime 清周期/到期并关闭提醒。默认保留当前价格、币种和管理状态，可明确选择采用已知本期价格或恢复 active。周期型应用保留原提醒意图；从 lifetime 变 recurring 时仍默认保持 false，用户可主动开启。

应用成功只改 subscriptions 当前事实，发布变更并重新调度；不新增周期/付款，也不建立历史到当前的持续同步关系。后续修正/删除该历史行不再改当前事实。详情“设置当前周期”打开相同预览编辑流程，直接调整当前字段同样不自动补历史；如需要留历史，使用显式“添加周期记录”。

删除周期确认列明关联付款数，说明只删周期、解除关联，付款快照及当前日期保留；付款删除从付款视图另行确认。纠正周期价格不改实付；纠正付款不改周期报价。查看某周期关联付款时显示该周期全部已关联付款，并明确“全部付款年份”，不受当前年份隐藏跨年关联。

### 2.4 续费、复制和付款维护

**续费**只适用 recurring，先读取最新记录，预填付款日、实付、新周期及备注，允许用户调整。无论原管理状态如何，只要原到期日不早于今天，就以原到期日续接；保存后恢复为订阅中。lifetime 详情/右键隐藏续费，服务返回 unsupportedOperation 防止旧入口绕过。默认日期算法见第 5 节。

保存续费必须一次提交：新增 renewal 周期、创建关联付款、更新当前周期、设为 active、递增版本及回执。周期报价记录原当前价格，付款记录用户确认的实付；两者可不同，未来价格不受实付覆盖。保存成功三个页面均刷新，详情保留当前历史年份。

**复制**只产生一个预填新建草稿：新 UUID、名称追加“副本”、继承当前字段与可共享图标，首次付款默认未勾选，不复制历史。放弃草稿不会产生记录。

**补录 / 纠正 / 删除付款**从详情进入。付款日期不得晚于今天，金额非负，币种独立，起止日期同时存在时须有序。纠正不改变所属订阅及付款类型；续费类型仍必须保留完整覆盖周期。明确提示“此操作仅修改付款历史，不调整当前订阅周期”。

### 2.5 停用、恢复与删除

- 停用只改 managementState，保留价格、日期、图片、付款；成功后移出预估并取消提醒。
- 恢复只设 active：周期有效性继续由到期日判断，终生恢复使用中并算有效；均不自动产生付款。
- “选择已过期”选择当前结果中 `D < 0` 的条目，包含已停用但日期已过期的条目；后续仍展示影响预览。
- 单条与批量删除先列明订阅数、周期记录数和付款数再确认。预览后数据改变则重新预览，不使用旧计数提交。
- 删除订阅、所属周期和付款为同一事务；失败回滚。提交后取消通知，清理无订阅且无用户模板引用的图标；外部清理失败单独重试，不误报数据未删除。

### 2.6 页面状态与命令

`loading → loaded / emptyDatabase / emptyResult / failed`；已有数据刷新时保留内容并标记 refreshing；恢复或清空时全窗口进入 maintenance。

空库提供新建和导入，无匹配结果提供清除筛选。刷新失败保留旧显示但禁用依赖最新预览的危险提交。其他窗口删除了正在编辑的记录时保留错误说明，不能用旧草稿自动重建该 ID。

| 命令 | 产品接入后的快捷键 | 路由 |
| --- | --- | --- |
| 新建订阅 | Cmd+N | 当前活动主窗口；无窗口则先打开主窗口 |
| 新建窗口 | Cmd+Shift+N | 替代骨架当前 Cmd+N 的窗口动作 |
| 搜索 | Cmd+F | 当前表格或日历 |
| 设置 | Cmd+, | 独立 Settings |
| 保存表单 | Cmd+Return | 当前合法且未在保存的表单 |
| 取消 | Escape | 有未保存输入先确认 |

### 2.7 服务模板库：选择到创建的完整流程

入口统一为“新建 → 从模板”、空库添加服务、表格底部添加服务；根 Sheet 内从模板选择转到共享表单，返回保留模板查询。首屏使用原生侧边栏配置“全部模板 / 内置模板 / 我的模板 / 服务类型”，内容区提供独立搜索、按类型分组和空白新建。

卡片显示名称、图标、分类、可选已添加数量。已添加数量只统计稳定模板名称/别名匹配的提示性结果，不作为身份键、财务数据或去重依据；界面标注“同名项目 n 个”，不能宣称它们必然来自该模板。模板可以多次使用。

选择模板 → 复制名称/分类/图标/建议计费方式及价格到 Draft → 用户确认日期与真实价格 → 正常 create 事务。模板未设价格保持空，所有当前日期为空，首次付款未勾选，管理状态 active；lifetime 提醒=false，recurring 按默认 true。新增被现有筛选隐藏时保存成功后提示并提供查看入口。

内置目录随应用离线提供，名称可覆盖截图所示的影音、工具、生活与通讯服务，例如 Apple Music、Netflix、ChatGPT、Notion、Office 365、京东 Plus 等；不从截图假定现价、有效期或购买状态。元数据由 `BuiltinServiceCatalog.json` 维护，品牌图标保存在随应用打包的 `BuiltinTemplateIcons` 资源目录。内置内容只读，“复制为我的模板”后才能修改；首版不做在线市场、后台自动抓取和模板执行脚本。

品牌图标使用显式用户操作：只有用户在订阅或“我的模板”编辑器中点击“从 Apple 搜索”并提交关键词时，才向 Apple Search API 发送关键词与所选地区。选择结果缓存到应用沙盒；离线或缓存不可用时保留图标不可用状态，绝不冒充为另一个 SF Symbol。只有模板或订阅从未设置图标时，才按名称稳定选择一个 SF Symbol 占位。应用不自动为内置模板发起网络请求，也不把查询发送给第三方服务。

用户模板可新建、编辑、复制、删除；删除确认只说明将删除模板及可能孤立的图片，不触及已生成的订阅或付款。从订阅保存模板时先展示允许复制的字段，默认排除私密备注、管理状态、日期、付款、提醒；建议价格允许用户取消保存。模板更新不追溯覆盖已经填写的草稿；提交订阅使用草稿快照。

服务库空结果提供清除搜索及自建模板，目录读取失败提供重试和空白新建。内置目录版本更新不会重写用户模板、现有订阅或同名数据。模板图片复制给订阅时使用沙盒资产或系统符号：内置图片首次采用时登记为普通 icon_asset，使备份不依赖未来应用仍含该资源。

## 3. 数据库与表关系

### 3.1 存储及事务

采用 SwiftData 本地存储、`VersionedSchema`、显式 `SchemaMigrationPlan`，关闭 CloudKit。V1 为 `1.0.0`，迁移阶段初始为空。首次正式启动只创建空业务库和必要单例，不插入演示记录。

“表名”是逻辑名称，实际 SQLite 表结构由 SwiftData 管理，不手写 SQL 改其内部表。三个 Tab 共用以下实体，不各自复制数据库。

| 逻辑表 | 实体 | 关系 / 用途 | 字段定义 |
| --- | --- | --- | --- |
| subscriptions | SubscriptionRecord | 订阅当前事实；1 对多付款，可选引用图片 | 本文 4.2 |
| subscription_periods | SubscriptionPeriodRecord | 订阅的周期历史，1 对多可选关联付款 | 本文 4.7 |
| payments | PaymentRecord | 必须属于一条订阅；订阅删除 cascade | 本文 4.3 |
| icon_assets | IconAssetRecord | 一张图片可被多个订阅共享；删除关系 nullify | 本文 4.4 |
| service_templates | ServiceTemplateRecord | 用户自建模板；可选共享图片，生成订阅后无外键联动 | 本文 4.6 |
| app_settings | AppSettingsRecord | 唯一 main；外观、提醒、视图默认值 | Tab3 第 4 节；提醒子集见 Tab2 |
| store_metadata | StoreMetadataRecord | 唯一 main；数据集身份和版本 | 本文 4.5 |
| mutation_receipts | MutationReceiptRecord | 操作回执，避免同次续费重试产生多笔付款 | 本文 4.5 |

唯一主键使用 `@Attribute(.unique)`，创建前仍显式检查，不依赖冲突合并。订阅对周期和付款均设 cascade/inverse；周期对关联付款设 nullify，删除周期只解除关联。付款的 subscription 必填，periodRecord 可空且必须属于同一订阅。图片反向关系 nullify，不删除拥有者；内置服务目录不写用户表。

本方案尚未发布，初始 AppSchemaV1 注册上述八个实体，含 billingKind、周期历史及付款可选关联；文档版本 1.2 不表示已有生产 SchemaV1 被改写。实际发布后的变更须显式迁移。

索引设计：订阅 `expiryDay`、`managementStateRaw + expiryDay`、`categoryRaw`；付款 `paymentDay`；ID 以唯一索引查询。使用 macOS 26 SDK 支持的 `#Index`，折算金额与跨币种排序在 DTO 层执行。

周期增加 startDay/endDay 索引，按订阅关系限定后做年份交集查询；同一订阅历史数量较小时，可在一次值类型快照中筛选。年份为查询派生值，不存 year 列或每年副本。

### 3.2 唯一数据库入口

`StoreActor` 隔离 ModelContext，关闭 autosave。UI 只接收不可变 Sendable DTO，不跨 actor 传递 `@Model`。服务按依赖协议注入；值类型纯规则可独立测试。

读快照须在一次不挂起的 actor 操作中取齐订阅、所需付款与版本；不能分两次 await 拼接不同版本。写入流程：检查数据集及维护锁 → 查幂等回执 → 检查预期版本 → 校验 → 变更实体及版本/回执 → 一次 save。事务内无文件选择、通知授权或其他 await；失败 rollback。

每次成功写事务递增 storeRevision，相关订阅 revision 递增一次。付款或周期历史新增/纠正/删除也递增父订阅 revision，不自动改当前周期。一次续费同时修改三类记录，父 revision 只加一次；重放不加版本。DataChange 区分当前订阅字段与仅历史变更，历史变更刷新详情，只有当前日期/状态等变更才需重排提醒。

仅更改模板时只递增该模板 revision，不改已生成订阅的 revision；设置同理只更新设置版本。storeRevision 仍是覆盖全部用户数据的事务版本。

多窗口编辑检查记录 revision。版本冲突保留草稿，提供重新加载，不静默覆盖。批量删除、CSV 预览绑定整个 SnapshotVersion。普通查询响应同时校验 datasetID 与页面请求序号。

### 3.3 文件、迁移及恢复边界

正式接入时使用 `Application Support/Periodic/Datasets/<datasetID>/default.store`，图片放同目录 `Assets/`，由 `active-dataset.json` 指向当前数据集；Tab3 规定整体恢复切换流程。当前骨架只预留 `Periodic/default.store`，尚无业务记录；如发现非空未知旧库，应报错并保留，不自动覆盖。

图片先写为不可变文件，再在数据库事务中登记和引用，提交后回收旧孤立资源。数据库与文件、系统通知不是一个事务。备份期间保留资产读取租约，避免引用中的文件被并发清理。

数据库打开、迁移或完整性检查失败时展示错误与重试，保留原库，不静默清库或退回内存模式。测试容器、文件及图片与用户正式目录隔离。

## 4. 表与字段设计

### 4.1 公共类型

| 类型 | 存储 / API 表达 | 校验规则 |
| --- | --- | --- |
| LocalDate | DB 为 Int 日序号，1970-01-01 为 0；API 为值类型；交换文件为 ISO 日期字符串 | 公历 0001-01-01～9999-12-31；通过日历计算，不用秒数 ÷ 86400 |
| Money | amountMinor: Int64、currencyCode: String、scale: Int | 非负、无溢出；输入不可超出币种精度；0 与未填不同 |
| Currency | 大写 ISO 4217 代码及最小单位精度 | 随应用附带有明确精度的 ISO 目录；无效或无明确精度的代码报错，不猜成两位 |
| UUID | UUID；交换文件为标准字符串 | 唯一，不以名称充当主键 |
| 时间戳 | Date；JSON 为 ISO 8601 UTC 含毫秒 | 审计时间，不参与自然日减法 |
| revision | Int64，从 1 起 | 每次聚合变化加一，不能由用户编辑 |

币种目录必须覆盖 CNY/USD 的 2 位、JPY 的 0 位，以及 KWD 等 3 位情形，不能仅硬编码所有币种都为两位。记录保存 scale 快照，未来目录升级不改写已有历史，格式迁移必须显式处理。金额用最小单位保存、Decimal 计算、十进制字符串交换，不用 Double 保存事实。

### 4.2 subscriptions

| 字段 | Swift 类型 | 空值 / 默认 | 约束与来源 |
| --- | --- | --- | --- |
| id | UUID | 非空，新 UUID | 新建、复制、CSV、恢复；唯一 |
| name | String | 非空，无默认 | trim 后非空；保留 Unicode，允许同名 |
| symbolName | String | 非空，`app.dashed` | 无效符号显示时回退默认值 |
| iconAsset | IconAssetRecord? | nil | 已登记图片关系；DTO 输出 iconAssetID |
| categoryRaw | String | `other` | 固定 ServiceCategory |
| managementStateRaw | String | `active` | active / inactive；按计费类型决定中文状态 |
| billingKindRaw | String | `recurring` | recurring / lifetime；不能由空日期推断 |
| periodStartDay | Int? | nil | 周期开始日或终生取得/使用日；周期起止齐全 start ≤ end |
| expiryDay | Int? | nil | recurring 可空，当天有效；lifetime 必须 nil |
| cycleMonths | Int? | recurring 默认 1 | recurring 为 1/3/6/12；lifetime 必须 nil，不能用 0 |
| periodAmountMinor | Int64 | 必填，无默认 | 价格 ≥ 0；沿用内部字段名，lifetime 表示一次性价格；不等同实付 |
| currencyCode | String | CNY | 目录中的大写代码 |
| currencyScale | Int | 由币种目录决定 | 随价格保留，不独立编辑 |
| note | String | 空串 | 允许多行；API 清空映射为空串 |
| reminderEnabled | Bool | recurring=true、lifetime=false | lifetime 不允许 true |
| revision | Int64 | 1 | 当前字段或所属付款变更时递增 |
| createdAt | Date | 创建时间 | 普通编辑、CSV 不得修改 |
| updatedAt | Date | 提交时间 | 普通写入更新；恢复可保留原值 |
| payments | [PaymentRecord] | 空集合 | 反向关系；删除订阅级联删除 |
| periods | [SubscriptionPeriodRecord] | 空集合 | 反向关系；删除订阅级联删除，不按年份分库 |

ServiceCategory 稳定值：`workStudy` 工作学习、`tools` 工具产品、`media` 影音娱乐、`household` 家庭日常、`communication` 通讯服务、`food` 餐饮零食、`other` 其他。显示语言变化不得改变 rawValue。

### 4.3 payments

| 字段 | Swift 类型 | 空值 / 默认 | 约束与来源 |
| --- | --- | --- | --- |
| id | UUID | 非空，新 UUID | 一次成功操作只生成一次 |
| subscription | SubscriptionRecord | 必填 | 父订阅；DTO/备份输出 subscriptionID，不冗余存第二外键 |
| periodRecord | SubscriptionPeriodRecord? | nil | 同一订阅的一条周期，可无关联；DTO/备份为 periodRecordID |
| kindRaw | String | 操作决定 | initial 首次、renewal 续费、manual 补录；纠正不改变类型 |
| paymentDay | Int | 必填 | 实际付款日期 ≤ 提交时的今天 |
| amountMinor | Int64 | 必填 | 实付 ≥ 0；不是当前价格引用 |
| currencyCode | String | 必填 | 当次实付币种快照 |
| currencyScale | Int | 必填 | 当次币种精度快照 |
| periodStartDay | Int? | nil | renewal 必填；其他可未知 |
| periodEndDay | Int? | nil | renewal 必填；两者齐全时 start ≤ end |
| note | String | 空串 | 当次付款备注 |
| revision | Int64 | 1 | 纠正时递增 |
| createdAt | Date | 创建时间 | 审计字段 |
| updatedAt | Date | 最后提交时间 | 纠正时更新 |

### 4.4 icon_assets

| 字段 | 类型 | 约束 |
| --- | --- | --- |
| id | UUID | 唯一，替换图标产生新 ID |
| relativePath | String | `Assets/<id>.png`；相对数据集根，不含 `..` 或符号链接 |
| sha256 | String | 实际规范图片文件摘要，小写十六进制 |
| mimeType | String | image/png；上传 JPEG 规范化后存 PNG |
| byteCount | Int64 | > 0，与文件一致 |
| pixelWidth / pixelHeight | Int | > 0，与解码图像一致 |
| createdAt | Date | 首次持久化时刻 |
| subscriptions | [SubscriptionRecord] | inverse；有任一订阅引用时不得回收 |
| templates | [ServiceTemplateRecord] | inverse；有任一用户模板引用时不得回收 |

工程默认：源文件限 10 MiB、解码限 4000 万像素、规范图片最长边 512，不放大小图，去除无关元数据。这些是可调整的资源保护参数，修改时同步校验和测试，不改变产品图片来源范围。图片暂存返回 token，表单不保存外部绝对路径；取消后释放临时文件。

### 4.5 内部元数据

| 表 | 字段 | 类型及规则 |
| --- | --- | --- |
| store_metadata | id | String，固定 main，唯一 |
| store_metadata | datasetID | UUID，与当前目录及活动指针一致 |
| store_metadata | schemaVersion | String，1.0.0；实际迁移仍由 VersionedSchema 控制 |
| store_metadata | storeRevision | Int64，初始 0，每次成功业务或设置事务加一 |
| store_metadata | createdAt / updatedAt | Date，数据集建立与最后提交时间 |
| mutation_receipts | operationID | UUID，唯一，同一有效提交及其重试保持不变 |
| mutation_receipts | commandKind | String，如 subscription.renew |
| mutation_receipts | payloadDigest | String，规范化请求 SHA-256，包含目标、预期版本及参数 |
| mutation_receipts | resultData | Data，CommandReceiptEnvelope 的版本化 JSON；保存对应命令的完整返回值 |
| mutation_receipts | committedRevision | Int64，本次提交版本 |
| mutation_receipts | createdAt | Date，提交时间 |

回执与实体变更同事务保存。相同 operationID、相同内容返回旧结果；同 ID 不同内容报错。失败不写回执。V1 不自动淘汰回执；备份不携带回执，恢复产生新 datasetID，拒绝旧操作上下文。

CommandReceiptEnvelope 包含 version、resultKind、payload：订阅/周期/付款/模板命令保存 MutationResult，设置命令保存 SettingsSnapshot，CSV 保存 CSVImportResult。以命令类型解码，不能遗漏周期 ID 或导入计数；重放标识只影响响应，不改原提交结果。

### 4.6 service_templates 与内置目录

| 字段 | 类型 / 默认 | 约束与用途 |
| --- | --- | --- |
| id | UUID / 新 ID | 仅用户模板入表，唯一 |
| name | String / 无默认 | trim 后必填，同名允许；不能据此联动修改订阅 |
| aliasesData | Data / JSON `[]` | String 数组，trim、去空、去重，用于模板搜索 |
| categoryRaw | String / other | 固定服务类型 |
| symbolName | String / app.dashed | 图标回退 |
| iconAsset | IconAssetRecord? / nil | 与订阅共用资产管理；图片可共享 |
| suggestedBillingKindRaw | String / recurring | recurring / lifetime |
| suggestedCycleMonths | Int? / 1 | recurring 必须 1/3/6/12，lifetime 必须 nil |
| suggestedAmountMinor | Int64? / nil | 建议价格可未知；已知 ≥ 0，不把空填为 0 |
| currencyCode / currencyScale | String / Int，默认 CNY/2 | 建议币种及精度；与金额同规则 |
| revision | Int64 / 1 | 编辑冲突检测 |
| createdAt / updatedAt | Date | 用户模板审计字段 |

内置目录采用 `BuiltinServiceCatalogV1`：catalogVersion、entries；每项含稳定 `key`（如 builtin.netflix）、name、aliases、category、symbolName、可选 bundledIconName 及相同建议计费/金额字段。内置目录无用户 UUID/revision，不登记其未使用图片为用户资产。

统一 TemplateDTO 使用 TemplateKey = builtin(String) / user(UUID)、source、显示字段和可选 revision。选择时复制值，不在 subscriptions 追加必需模板外键；模板移除不破坏订阅。用户模板变化递增 storeRevision 并发布 templates 事件，相关资产登记与模板保存同事务，回执返回 templateIDs。

### 4.7 subscription_periods

| 字段 | Swift 类型 / 默认 | 约束 |
| --- | --- | --- |
| id | UUID / 新 ID | 唯一；同次续费/手动提交重试保持同一结果 ID |
| subscription | SubscriptionRecord / 必填 | 必须有父；不能在编辑时迁移到别的订阅 |
| sourceRaw | String / 操作确定 | initial / renewal / manual；不可在普通编辑中改写 |
| periodTypeRaw | String / monthly | monthly / quarterly / semiannual / annual / custom / lifetime，独立历史快照 |
| startDay | Int / 必填 | LocalDate，无时间戳；允许未来 |
| endDay | Int? / 表单确认 | lifetime 必须 nil；其余必填且 end≥start，包含结束日 |
| quotedAmountMinor | Int64? / nil | 本期记录价格，未知 nil、免费 0，≥0；不是实付 |
| currencyCode / currencyScale | String / Int，默认 CNY/2 | 即使价格未知也保留币种；遵循 CurrencyCatalog |
| note | String / 空串 | 当次备注，不从当前私人备注自动复制 |
| revision | Int64 / 1 | 纠正时递增 |
| createdAt / updatedAt | Date | 创建及最后修改时间 |
| payments | [PaymentRecord] / 空集合 | inverse，nullify；删除周期保留付款及其覆盖快照 |

month 映射为 monthly=1、quarterly=3、semiannual=6、annual=12，custom/lifetime 无固定月数；不重复持久化可推导的 cycleMonths。periodType 决定这条历史的呈现，不能拿 Subscription.billingKind/cycleMonths 回填。历史 type=lifetime 的记录可存在于当前 recurring 订阅中，反之亦然。

普通 initial/renewal 记录保存当次当前报价及已确认日期；manual 可以价格未知。历史来源并不限制纠正，但纠正不重算付款。没有 currentPeriod 外键：当前订阅事实与历史显式复制同步，不形成隐式持续联动。

## 5. 派生规则与金额精度

### 5.1 日期、状态及数量

`today` 由 Clock 提供当前时间点和系统时区，再取公历年月日。记录年月日不随时区变化。`D = expiry.dayNumber - today.dayNumber`。

| 输出 | 计算规则 |
| --- | --- |
| expiryStatus | 先 lifetime → perpetual；recurring 才按 nil→unknown、D<0→expired、0→today、1…7→within7Days、8…30→within30Days、其余 normal |
| isCurrentlyEffective | active 且（lifetime 或 recurring 有日期且 D≥0）；开始日在未来不增加限制 |
| isForecastEligible | active + recurring + 有日期 + D≥0；与有效数量区分 |
| summaryBucket | 先 inactive；再 lifetime→effective；再 unknown；再 expired；其他 effective，互斥四类 |
| forecastBucket | 先 inactive；再 lifetime；再 unknown；再 expired；其他 eligible，互斥五类 |
| remainingRatio | recurring 日期齐全时 clamp((D + 1) / (end - start + 1), 0, 1)，终生/缺日期 nil |

过期不会自动停用或自动推进日期。启动、回前台、唤醒、系统日期/时区改变及跨午夜触发重算；三个 Tab 使用同一 today，不各自截取不同的时间点。

临期共用 `DateRules.isUpcoming(record,today,horizonDays)`：horizonDays 只能 7/15/30，结果为 recurring + active + 有日期 + `0≤D≤horizonDays`。Tab2 先应用共享筛选再调用，Tab3 全库调用；永久有效不是一个无限大的 D。

### 5.2 金额

只对 recurring 计算：每周期金额 P、合法月数 M，单条年化 `P × (12 / M)`，月均 `年化 / 12`。M 均整除 12，可先精确汇总各币种符合 isForecastEligible 的年化金额，再除以 12。lifetime 月均/年化均返回 nil，禁止用一次性价格除以 12、用 0 月作除数或返回伪零。

用 Decimal 累加，显示时按币种 scale 以 `.plain` 四舍五入一次。不同币种独立分组。实际支出累加付款自身金额，采用相同的币种分组，但不应用当前有效性条件。

三条 CNY 88 年付：单条月均显示 7.33，合计为 22.00；半年 CNY 120 为月均 20、年化 240；季度 CNY 43.20 为月均 14.40、年化 172.80。CNY 0.001、JPY 1.5 为输入错误，不静默舍入。

### 5.3 续费日期

月加法先计算目标年月，再以 `min(原日, 目标月天数)` 取日；不能用固定 30/365 天代替。超出日期支持范围时返回字段错误。

调用续费预览和提交前验证 billingKind=recurring；lifetime 返回 unsupportedOperation，不进入本节算法。

| 条件 | 新开始日 | 新到期日 |
| --- | --- | --- |
| 原到期日 ≥ 今天 | 原到期日 + 1 天 | 原到期日 + M 月，月末钳制 |
| 原日期未知或 < 今天 | 今天 | 今天 + M 月，再减 1 天 |

2027-01-31 月付续费 → 2027-02-01～02-28；2028-01-31 → 02-01～02-29。已过期月付在 2026-09-22 续费 → 09-22～10-21。连续月末续费按当前保存日期继续计算，不额外推断“固定每月最后一天”。预览只是默认值，提交使用用户确认的新日期。

## 6. 接口设计

以下为接口契约，不是可直接编译的完整代码；表中列出的字段构成各命名请求/响应类型的定义。服务统一 `async throws`，规则函数同步且无 IO。

### 6.1 公共契约

```swift
struct SnapshotVersion: Sendable, Equatable {
    let datasetID: UUID
    let storeRevision: Int64
}
struct MutationContext: Sendable {
    let datasetID: UUID
    let operationID: UUID
}
struct MutationResult: Sendable {
    let version: SnapshotVersion
    let subscriptionIDs: [UUID]
    let periodIDs: [UUID]
    let paymentIDs: [UUID]
    let templateIDs: [UUID]
    let replayed: Bool
}
struct FieldIssue: Sendable {
    let path: String
    let code: String
    let message: String
}
```

`SubscriptionDTO` 对应 4.2：关系改 ID、日期改 LocalDate、金额改 Money，含 billingKind/cycleMonths?，不含 payments/periods 模型数组。`PaymentDTO` 对应 4.3，含 periodRecordID?；`PeriodDTO` 对应 4.7，含 subscriptionID、类型、起止、quotedMoney?、currency、revision 和审计时间。`SubscriptionDerived` 含 remainingDays?、expiryStatus、remainingRatio?、isCurrentlyEffective、isForecastEligible、summaryBucket、forecastBucket、monthlyEstimate?、annualEstimate?；终生折算 nil，周期折算为未舍入 Decimal。

`SharedSubscriptionFilter` = searchText + Set<ManagementState> + Set<ExpiryStatus> + Set<ServiceCategory> + Set<BillingKind> + Set<CurrencyCode>。`TableSort` = field(expiry/remainingDays/annualEstimate) + direction(ascending/descending)。`TableGrouping` = none/category/managementState。`DataChange` = version + changedKinds(subscriptions/periods/payments/templates/settings/assets) + affectedIDs + currentFieldChanges:Set<SubscriptionID>。最后一项只列当前事实发生变化的订阅，父 revision 因历史变化递增不等于当前事实改变。

### 6.2 表格和订阅服务

```swift
protocol SubscriptionService: Sendable {
    func query(_ request: TableQuery) async throws -> TableSnapshot
    func detail(_ query: SubscriptionDetailQuery) async throws -> SubscriptionDetail
    func copyDraft(id: UUID) async throws -> SubscriptionDraft
    func previewRenewal(id: UUID) async throws -> RenewalPreview
    func create(_ request: CreateSubscription, context: MutationContext) async throws -> MutationResult
    func update(_ request: UpdateSubscription, context: MutationContext) async throws -> MutationResult
    func renew(_ request: RenewSubscription, context: MutationContext) async throws -> MutationResult
    func setState(_ request: SetSubscriptionState, context: MutationContext) async throws -> MutationResult
    func previewDeletion(ids: Set<UUID>) async throws -> DeletionPlan
    func delete(_ plan: DeletionPlan, context: MutationContext) async throws -> MutationResult
}
```

| 类型 | 必填内容 / 返回内容 | 契约 |
| --- | --- | --- |
| TableQuery | filter、sort、grouping、today | today 来自共享 Clock；不读另一窗口筛选 |
| TableSnapshot | version、asOfDay、rows、groups、matchedCount、totalCount、bucketCounts、forecastCounts、effectiveTotalsByCurrency | 所有计数和底栏来自同一快照；费用仅 isForecastEligible |
| TableGroup | key、title、rowIDs、count、forecastCounts、totalsByCurrency | 固定分组次序；折叠不改 rows 或统计 |
| SubscriptionDetailQuery | subscriptionID、yearSelection(currentYear/year/all)、today | 缺省 UI 传 currentYear，today 由共享 Clock 校验，不继承主轴年份 |
| SubscriptionDetail | version、subscription、derived、resolvedYear?、availableYears、periodRows、paymentRows、matchedPeriodCount、allPeriodCount、matchedPaymentCount、allTimePaymentCount、selectedYearSpending、allTimeSpending | 同一快照，resolvedYear=nil 表示全部，此时两种支出汇总一致、UI 标签为全部年份；计数区分无记录与零元记录 |
| PeriodRow | PeriodDTO + ordinal、crossesYear、linkedPaymentCount | ordinal 在全量周期中先计算，非主键；关联付款数为全部年份 |
| SubscriptionDraft | name、symbolName、iconChoice、category、managementState、billingKind、periodStart?、expiry?、cycleMonths?、amountText、currency、note、reminderEnabled | 金额为空不代表 0；终生字段组合强约束 |
| IconChoice | existing(assetID) / staged(token) / none | staged 需来自当前 IconService；none 表示移除图片，保留后备符号 |
| SubscriptionValues | Draft 对应的全部已校验字段；amountText+currency 转为 Money，保留 iconChoice | 只包含可编辑事实，不包含审计时间、revision 或派生金额 |
| InitialPaymentValues | paymentDate、Money、periodStart?、periodEnd?、note | kind 由创建服务固定为 initial；不能独立指定父 ID |
| CreateSubscription | 新 id、合法 SubscriptionValues、initialPayment?、historyPolicy | normal 在完整日期时产生 initial 周期；copy=none 不造历史；initialPayment=nil 不产生付款 |
| UpdateSubscription | id、expectedRevision、完整 SubscriptionValues | 更新当前资料；不自动新增/更改周期历史或付款 |
| RenewalPreview | version、subscriptionID、expectedRevision、RenewalDraft | 草稿含 paymentDate、money、新起止日、note，今天只捕获一次 |
| RenewSubscription | id、expectedRevision、paymentDate、paidMoney、newStart、newExpiry、note | 不包含修改未来价格字段；新日期必填 |
| SetSubscriptionState | id、expectedRevision、state | 仅修改管理状态 |
| DeletionPlan | planID、version、ids、subscriptionCount、periodCount、paymentCount、unreferencedAssetCount | 服务保留计划并核对版本；明确级联删除周期与付款 |

新建及续费在服务内生成所需周期/付款 ID，同事务保存关系与回执。historyPolicy 由新建来源路由决定，不让复制自动造历史。保存请求固定 operationID，重试原 ID，改内容换新 ID；先查回执再查 revision，避免成功后的重试被旧版本误拒绝。

新建草稿另带只读来源 metadata：creationOrigin=blank/template/copy、historyPolicy=normal/none；copyDraft 设置 copy/none，模板设置 template/normal，空白设置 blank/normal。它们不属于可编辑 SubscriptionValues，也不持久化到订阅或 CSV；切换普通字段不丢失来源。

收到旧操作回执时可确认该次保存成功，但页面不能用较旧版本覆盖已经展示的新快照；随后按最新版本重新查询。交易型服务内的 today 必须由共享 Clock 在提交时重新校验，不能把表单打开时捕获的旧日期用于跨日后的付款合法性判断。

### 6.3 付款与图片接口

```swift
protocol PaymentService: Sendable {
    func list(_ query: PaymentListQuery) async throws -> PaymentListSnapshot
    func add(_ request: AddPayment, context: MutationContext) async throws -> MutationResult
    func update(_ request: UpdatePayment, context: MutationContext) async throws -> MutationResult
    func delete(_ request: DeletePayment, context: MutationContext) async throws -> MutationResult
}
protocol IconService: Sendable {
    func stage(source: AuthorizedFile) async throws -> StagedIcon
    func discard(token: UUID) async
    func thumbnail(assetID: UUID) async throws -> IconThumbnail
}
```

| 类型 | 字段 / 行为 |
| --- | --- |
| PaymentListQuery | subscription(id,yearSelection) / linkedToPeriod(id)；后者明确读取该周期全部年份付款 |
| PaymentListSnapshot | version、subscriptionID、subscriptionRevision、queryScope、PaymentDTO 数组 |
| PaymentValues | paymentDate、Money、periodStart?、periodEnd?、note；适用第 4.3 节校验 |
| AddPayment | subscriptionID、periodRecordID?、expectedSubscriptionRevision、PaymentValues；强制 kind=manual，关联周期须属同一订阅 |
| UpdatePayment | paymentID、subscriptionID、expectedPaymentRevision、expectedSubscriptionRevision、periodLinkPatch(keep/link(UUID)/clear)、PaymentValues；可明确纠正/解除同订阅内关联，不改周期事实 |
| DeletePayment | paymentID、subscriptionID、expectedPaymentRevision、expectedSubscriptionRevision；UI 先确认 |
| AuthorizedFile | 系统选择器得到并处于有效安全作用域的本地文件访问句柄，不能由外部路径字符串任意构造 |
| StagedIcon | token、previewData、pixelSize、byteCount、sha256；有效期为本次草稿，取消释放 |
| IconThumbnail | 解码后的 Sendable 图像数据 / 缓存键；UI MainActor 构造展示图像 |

实际付款按区间查询由 Tab3 StatisticsService 在一致快照内完成；list 用于详情或周期关联付款，详情首屏由 detail 一次快照整合，不能先后 list 得到不同版本。所有入口共用 PaymentService 写规则，删除付款不删除周期。

### 6.4 错误与副作用

| 错误 | 条件 | UI 处理 |
| --- | --- | --- |
| validation([FieldIssue]) | 必填、金额、日期、图片失败 | 定位字段，保留草稿 |
| notFound(entity,id) | 记录已删除 | 提示并关闭过期详情，不自动新建 |
| revisionConflict | 记录版本变化 | 保留草稿，提供重新加载 |
| stalePlan | 全库版本变化 | 重新计算并展示预览，需再确认 |
| datasetChanged | 已恢复或清空数据集 | 丢弃旧查询；旧表单禁止提交并说明原因 |
| idempotencyMismatch | 同 operationID 的请求内容变化 | 阻止提交，修正提交上下文 |
| maintenanceInProgress | 维护锁占用 | 等待维护结束，再重新读取 |
| storageFailure | 保存、打开、迁移失败 | 保留输入和原数据，显示可重试原因 |
| assetUnavailable | 图片 token 失效或文件不可读 | 重新选择图片，不部分保存 |
| unsupportedOperation | 对终生调用续费等不适用命令 | 说明原因并引导编辑计费类型或补录付款 |

通知和孤立图片清理在提交后执行，由单独状态通道汇报，例如“保存成功，提醒更新失败”。恢复旧回执不意味着应重复创建付款；可以触发幂等的通知核对来补足后处理。

### 6.5 服务模板接口

```swift
protocol TemplateService: Sendable {
    func query(_ query: TemplateQuery) async throws -> TemplateSnapshot
    func makeDraft(key: TemplateKey) async throws -> TemplateDraftResult
    func draftFromSubscription(id: UUID) async throws -> ServiceTemplateDraft
    func save(_ request: SaveTemplate, context: MutationContext) async throws -> MutationResult
    func delete(_ request: DeleteTemplate, context: MutationContext) async throws -> MutationResult
}
```

| 类型 | 字段与契约 |
| --- | --- |
| TemplateQuery | searchText（名称/别名忽略大小写）、categories、source(all/builtin/user)、groupByCategory；不接收 SharedSubscriptionFilter |
| TemplateSnapshot | version、catalogVersion、TemplateDTO 列表、groups、matchedCount；名字按本地化比较后以 TemplateKey 稳定排序 |
| TemplateDraftResult | key、sourceRevision?、SubscriptionDraft、stagedIconToken?；只在内存/暂存目录预填，未创建订阅 |
| ServiceTemplateDraft | name、aliases、category、symbolName、IconChoice、suggestedBillingKind、suggestedCycleMonths?、suggestedAmountText?、currency |
| SaveTemplate | id、expectedRevision?、合法模板 Values；创建提供新 UUID，编辑检查版本；内置 key 拒绝写入 |
| DeleteTemplate | id、expectedRevision；确认删除用户模板，保留所有订阅/付款，资产按双向引用数回收 |

从内置模板复制和从订阅提取模板都只生成 ServiceTemplateDraft，确认 save 才持久化。图片 token 失效时保留其他输入并要求重新选择；没有图片不阻止使用符号完成创建。模板的保存/删除和订阅一样使用回执、版本冲突及维护锁。

### 6.6 周期历史与应用当前设置接口

```swift
protocol PeriodService: Sendable {
    func previewSave(_ request: SavePeriod) async throws -> PeriodSavePlan
    func save(planID: UUID, context: MutationContext) async throws -> MutationResult
    func previewDeletion(periodID: UUID) async throws -> PeriodDeletionPlan
    func delete(planID: UUID, context: MutationContext) async throws -> MutationResult
    func previewApplication(_ request: ApplyPeriod) async throws -> PeriodApplicationPlan
    func apply(planID: UUID, context: MutationContext) async throws -> MutationResult
}
```

| 类型 | 字段 / 校验 |
| --- | --- |
| PeriodValues | periodType、startDate、endDate?、quotedAmount?、currency、note；开始必填、结束条件必填、金额可未知 |
| SavePeriod | subscriptionID、periodID?、expectedSubscriptionRevision、expectedPeriodRevision?、values、newPayment?；nil periodID 表示新增 manual，编辑保留 source |
| PeriodSavePlan | planID、version、目标 ID/版本、规范化 values、关联付款草稿、重叠/相同区间提示、影响摘要；无错误可提交，有提示需用户确认 |
| PeriodDeletionPlan | planID、version、periodID、subscriptionID、linkedPaymentCount、currentValuesUnchanged=true；删除只 nullify 付款关联 |
| ApplyPeriod | periodID、expectedPeriodRevision、subscriptionID、expectedSubscriptionRevision、cycleMonthsForCustom?、useQuotedPrice=false、restoreActive=false、reminderOverride? |
| PeriodApplicationPlan | planID、version、before/after 当前字段、通知影响摘要；源记录与父 ID 必须一致，未知报价不能 useQuotedPrice |

PeriodSavePlan 由服务持有，绑定快照；服务提交重新验证后原子写周期、可选付款、父 revision、metadata 和回执。`newPayment` 用 PaymentValues、kind=manual，覆盖日期初始复制周期起止，用户可确认修改；更改已有周期不会改变既有付款。若对已有周期“同时登记付款”，预览必须列明这是新增付款而非纠正旧付款。

所有 plan 提交先用 operationID 查回执，再核对 plan 版本；计划内容摘要固定且服务保留到本次确认结束。重放已完成的相同 plan 返回原周期/付款 ID，不因旧 storeRevision 再建记录。恢复或清空后旧 datasetID 仍应首先拒绝。

删除周期在一事务中解除每笔关联付款的 periodRecord，递增这些付款 revision 以拦截持有旧关联的编辑，保留它们的金额/日期快照；删周期、版本、回执同存。父订阅 revision 加一而当前日期不变。删整个订阅则同时 cascade 删除周期与付款。

apply 只更新当前订阅，preview 显示类型转换、当前日期、价格/币种是否采用、active 是否恢复和提醒变动；所有默认值必须明示，不能隐式覆盖价格或恢复状态。失败及过期 plan 沿用 validation/stalePlan/revisionConflict；不允许旧年份请求写入已切换的数据集。

年份纯规则接口：`PeriodRules.matchesYear(period,selection,today)`、`PeriodRules.availableYears(periods,payments,today)`、`PeriodRules.assignOrdinals(allPeriods)`；前者按闭区间相交，lifetime 只匹配开始年。UI 年份是查询参数，不写进这些记录。

## 7. 实现组织与落地顺序

| 现有位置 / 建议新增位置 | 职责 |
| --- | --- |
| App/PeriodicApp、Models/AppDestination、Views/DetailView | 启动数据集、注册三个导航值、加载/错误/维护状态 |
| App/AppCommands、Views/ContentView | focused scene 命令、WindowSession、单一 Sheet 路由 |
| Stores/PersistenceController、Stores/Schema、Stores/StoreActor | 复用容器工厂，定义 V1、迁移及事务入口 |
| Models/Subscription、Models/Payment、Models/LocalDate、Models/Money | 领域 DTO 和纯规则输入输出 |
| Services/Subscriptions、Services/Payments、Services/Icons | 业务服务与图片适配 |
| Views/Overview、Views/SubscriptionEditor、Views/Payments | 表格、详情、表单、历史 |
| Views/SubscriptionDetail、Stores/SubscriptionDetailStore、Views/Periods、Services/Periods | 共用详情、年份栏、手动周期、应用当前的预览与事务 |
| Views/ServiceCatalog、Services/Templates、Resources/BuiltinServiceCatalog.json | 模板库、预填与用户模板维护；离线目录校验 |
| Stores/OverviewStore、Services/AppServices | 页面异步状态和依赖装配 |

数据库 actor 必须在合适的非 MainActor 执行环境初始化并验证隔离；当前 MainActor 容器工厂只是骨架起点，不能假定给方法加 async 就消除了主线程 IO。重型图片解码和聚合离开 MainActor，UI 更新回 MainActor。

按以下顺序交付：

1. 实现 LocalDate、Money、状态、分类及费用规则，用固定 Clock 验证边界。
2. 建立 V1 模型、设置单例、元数据、StoreActor、回执和快照事件；验证重启持久化及失败回滚。
3. 接入三个导航占位、WindowSession 与命令，再实现 Tab1 查询、快捷视图、分组、列配置、排序、底栏。
4. 实现含周期/终生的表单、initial 周期与可选首次付款；完成模板预填后，接入续费的周期/付款原子事务、共用详情、按年历史与手动周期维护。
5. 加入停用、复制、预览删除、跨窗口冲突；与 Tab2 提醒、Tab3 数据交换连通。
6. 检查键盘、VoiceOver、深浅色、减少透明度、缩放和测试数据隔离。

## 8. 验收与测试设计

| 用例 | 具体断言 | 对应需求 |
| --- | --- | --- |
| 新建、取消、编辑、重启 | 取消不写数据；保存跨 Tab 一致；失败输入保留；首次金额为空必填 | AC-01、EDIT-01～03 |
| 状态边界 | 昨天 -1、今天 0、未来 7/8/30/31 天标签准确；管理状态不被过期改写 | AC-02 |
| 自然日 | 夏令时 23/25 小时日、跨午夜、换时区不修改保存年月日 | AC-03 |
| 周期型无日期 | 表格可见、天数“—”、无预估资格，不伪造日期；终生另行识别 | AC-04 |
| 精确金额 | 88 年付、120 半年、43.20 季度，以及三条 88 年付月均 22.00 | AC-05～06 |
| 过期/停用/恢复 | 预估资格按规则变动；历史实付不变；底栏排除数互斥 | AC-07 |
| 续费 | 2027/2028 月末、已过期 09-22→10-21、inactive 续费恢复 active | AC-08～09 |
| 原子性与重试 | 在写周期或付款后、save 前失败，订阅/周期/付款全回滚；同请求仅一周期一付款 | RENEW-03、AC-09 |
| 付款历史 | 调价、换币不改历史；纠正/删除付款不回退周期；零元实付是合法记录 | AC-10 |
| 无隐式付款 | 普通新建、复制、CSV 后付款数不增加，详情显示尚无付款记录 | AC-11 |
| 筛选排序 | 五维且关系、无日期降序仍最后、币种内金额排序且终生 nil 置后、Tab 切换保留条件 | AC-12 |
| 删除与共享图标 | 预览付款计数准确，级联删除；另有订阅引用的图标不删；失败回滚 | AC-20 |
| 多窗口竞争 | A 保存后 B 旧 revision 被拒绝，恢复后旧 datasetID 不能写入 | NAV-01、NAV-03 |
| 原生体验 | Cmd+N/F/,、键盘表单、VoiceOver、960×640、系统外观与对比度 | AC-21 |
| 规模 | 1,000 订阅 + 10,000 付款下搜索与操作可用；不反复在 body 中全库计算 | AC-22 |
| 快捷视图/分组 | 条件可见、组内排序、跨组选择、折叠不改底栏或导出、列配置可恢复 | AC-23 |
| 模板闭环 | 内置可浏览但业务库仍空；选择/返回/取消不写库；用户模板改删不改已有订阅 | AC-24 |
| 终生 | active 计有效、不进预估/未知/提醒；类型切换合法性；月均/年化 nil；续费服务拒绝 | AC-26 |
| 终生付款 | 一次性价格不代表实付；首付与订阅原子保存；补录不改当前类型 | AC-27 |
| 共享模板图片 | 删除最后订阅但模板仍引用时文件保留；删除最后引用后才清理；恢复可读 | AC-28 |
| 详情入口 | 名称/双击/Return、日期锚点、卡片共用详情；多选及返回位置正常 | AC-30 |
| 手动周期 | 任意合法起止、未知报价与零元区分、可选付款；历史写入不改当前日期 | AC-31 |
| 默认当年 | 当年空不切旧年、关闭再开回当年、固定年跨元旦不变；跨年不复制或重编号 | AC-32 |
| 年份口径 | 2025-12-15～2026-01-14 在两年可见，2025 付款只计 2025；顶部当前资料不变 | AC-33 |
| 应用当前 | 单独确认、custom 必选 M、保留价格/状态默认；取消无变化，成功更新提醒 | AC-34 |
| 删除/关联 | 删周期 nullify 不删付款或退当前日期，旧付款编辑版本冲突；续费幂等三表一致 | AC-35 |
| 历史边界 | 复制和 CSV 不造周期；备份恢复关联正确；删除预览周期数准确 | AC-36 |

日期、金额、事务和并发测试使用独立容器；界面用正式构建但独立测试数据集。最终须在 macOS 26 环境验证，不能把现有骨架在 macOS 27 上通过的测试当作这些业务功能已验收。
