# 3. 首页实现

> 版本：1.2｜日期：2026-09-22｜状态：待实现的详细设计。
> 产品依据：[需求文档](../requirement.md)。当前 Periodic 尚未实现本模块。

> 数据交换部分已由 [数据导入与导出规格 v1.3](../extensions/3-数据导入导出规格.md) 取代：当前只保留 `.periodicdata` 完整导出与合并导入。本文第 6～7 节中的 CSV、整体替换恢复和清空方案是历史设计记录，不属于当前实现要求，也不得在设置中显示占位入口。

本文覆盖首页统计的需求、功能、数据库、字段、接口、实现及验收。设置仍使用独立 Settings 窗口；模板管理是第四个主页面。当前数据交换规则以扩展规格为准。

共用订阅/付款模型及写服务见 [Tab1 表格总览](1-Tab1表格总览实现.md)；日期轴、提醒计划和系统授权见 [Tab2 时间线日历](2-Tab2时间线日历实现.md)。

## 1. 需求与功能映射

| 需求 | 功能 | 数据及接口 | 用户结果 |
| --- | --- | --- | --- |
| STAT-01、RULE、COST-01 | 全库概况 | subscriptions；StatisticsService.load | 总数与四个互斥状态数量 |
| STAT-02、COST-02～04 | 月均 / 年化预估 | 当前有效 recurring，按币种聚合 | 终生不折算，不混币种、不冒充实付 |
| STAT-03、TIME-11 | 即将到期 | recurring + active 且 0 ≤ D ≤ N；N=7/15/30 | 默认 15 天，查看详情及手动续费 |
| STAT-04 | 分类图 | 有效周期订阅年化金额，单币种 | 类型金额及占比，零值无虚假占比 |
| STAT-05、COST-05～06 | 已记录实际支出和明细 | payments；付款日期范围 | 付款快照统计，不受当前价格/状态影响 |
| STAT-06～07 | 数据下钻、终生实付 | 全库记录/付款快照 | 有效终生数量与周期预估分离；真实付款才算支出 |
| NAV、UI、NOTIFY | 通用、提醒及数据设置 | app_settings；SettingsService | 外观、视图默认值、提醒入口 |
| EXCHANGE-01～10 | Periodic 数据包 | 当前 V1 实体、图片和设置白名单；DataExchangeService | 完整导出、校验预览和按 UUID 合并导入 |
| TECH、QA | 离线、精度、进度、故障保护 | 快照、文件适配器、维护锁 | 可维护、可验证，无网络依赖 |

统计请求不接受 Tab1/Tab2 的 SharedSubscriptionFilter。页面明确标注“全库统计”，切换到本页不清除其他页面已有筛选。

## 2. 统计功能和交互

### 2.1 页面布局

| 区域 | 展示内容 | 操作 |
| --- | --- | --- |
| 概况 | 全库总数、当前有效、已过期、已停用、日期未知；有效细分周期/终生 | 点击查看同口径记录列表 |
| 预估费用 | 每币种一组月均预估、年化预估、参与预估周期条目数 | 查看参与者，不提供跨币种总额 |
| 即将到期 | 7/15/30 天选择、名称、到期日、剩余天数、管理状态 | 默认 15；详情、周期续费 |
| 服务类型图 | 单币种有效周期型的年化金额、占比 | 默认 CNY；可访问列表及类别下钻 |
| 已记录实际支出 | 本月 / 本年 / 自选范围、按币种金额、付款笔数 | 打开选定范围的付款明细 |

内容可纵向滚动；概况卡在支持的最小窗口宽度内等宽铺满，不产生空白占位；成对内容卡在同一网格行内等高。金额右对齐或等宽数字，默认显示货币代码；用户可在设置切换为货币符号，此偏好只改变展示，不改变存储、分组或计算口径。尚未接通真实数据源的统计模块不展示伪筛选器、破折号数值或空壳卡片，等对应数据能力落地后再显示。图表使用 Swift Charts，不在卡片每个数字后面叠加玻璃；导航和适合的浮层使用原生材料及 macOS 26 `.glassEffect()`。

### 2.2 概况与预估口径

每条订阅按如下优先级归属，避免一条同时被计入停用和过期：

```text
managementState == inactive → 已停用
其余 billingKind == lifetime → 当前有效（终生）
其余 recurring expiry == nil → 日期未知
其余 recurring expiry < today → 已过期
其余                         → 当前有效（周期型）
```

四类之和等于全库总数。有效子计数 effectiveRecurring + effectiveLifetime = effective，子计数不能再加一次到总数。开始日只作辅助说明；只有 isForecastEligible 的周期型进入主预估。免费有效周期型金额可以为 0；终生预估不适用，不能显示成“免费周期订阅”。

同币种先精确累计年化金额，再除以 12 得月均，最后按币种精度显示。三条 CNY 88 年付的月均合计必须为 22.00，不能把三行显示的 7.33 相加。USD、JPY 等单独显示，不能换汇后混合。

### 2.3 即将到期与分类图

临期集合为 recurring + active 且 `0 ≤ D ≤ N`，N=7/15/30、默认 15，包含今天和未来第 N 天；按 expiry/name/UUID 升序。停用、无日期、终生不进入。N 与 Tab2 共用 WindowSession 的范围值，但此处取全库、Tab2 取共享筛选，两页明确标注范围。详情及续费复用 Tab1，保存后刷新整个统计快照。

分类图针对选择币种的有效 recurring，按固定 ServiceCategory 汇总年化金额。终生一次性价格不入该图。默认 CNY，即使 CNY 暂无参与数据也显示空态，允许选择有数据币种，不悄悄更换口径。

主图可采用水平条形图，旁边列出类型、金额和占比。占比由未舍入类别金额 / 未舍入币种总额计算，显示一位小数；因四舍五入产生的总和 99.9% / 100.1% 是显示误差，不修改金额补差。总额为 0 或无有效记录时不计算占比，不画虚假满圆/等分图。转换 Double 仅发生在图形位置，文本与汇总仍用 Decimal。

### 2.4 实际支出与付款明细

- 默认本年：当前公历 1 月 1 日至 12 月 31 日；本月：月初至月末。由于付款日不允许未来日期，尚未发生的日期自然无付款。
- 自选范围包含首尾两天，start ≤ end；空的未来区间可以查询，不推断未来支出。
- 按付款 paymentDate 过滤，使用每笔付款自己的币种和金额；不看订阅当前价格、币种、有效性或管理状态。
- 全库没有付款时显示“尚无付款记录”；全库有付款但所选区间没有时显示“所选期间尚无付款记录”。存在零元付款则显示真实的 0 金额与笔数，不能当作无记录。
- 明细列为付款日、订阅名称、付款类型、金额与币种、覆盖周期、备注；未知覆盖日显示“—”。按付款日倒序、createdAt 倒序、UUID 排序。
- 明细中的名称使用当前关联订阅名称，金额/日期/覆盖周期使用历史快照。订阅永久删除会按已确认规则级联删除历史，统计随之减少。
- 明细纠正和删除跳转共享 PaymentService 流程，不产生第二套修改规则；修改后保留统计范围并重新读快照。
- 终生项目的 initial/manual 付款按相同日期和币种规则计入实际支出；只填一次性价格未登记付款仍无历史。项目后来改为周期/终生不追溯改写付款，不按当前 billingKind 排除旧付款。
- 周期记录及其 quotedAmount 也不是实付来源。新增/纠正/删除周期、把周期应用到当前，都不自动增减支出；只有明确登记或改删 PaymentRecord 才影响实付。删除周期后解除关联的付款继续计入支出。

### 2.5 状态与刷新

DashboardStore 持有图表币种、实际支出范围、下钻路由、请求 generation 和快照，临期范围绑定 WindowSession。首次 loading，空库仍显示数量 0 及新建/从模板/导入入口；读取失败提供重试，不用伪造 0 代替错误。

DataChange、共享 today 或用户切换范围/币种触发重新计算。缓存键为 version + today + range + chartCurrency + dueHorizonDays；CPU 聚合在后台，结果回 MainActor，旧请求不覆盖新请求。模板数不计入统计，但为快照一致性可在全库版本变化后重新取值。

### 2.6 概况、类别及实付下钻

数量卡片打开当前 DashboardSnapshot 对应的全库记录列表：总数/有效/过期/停用/未知，有效可再切周期/终生；预估卡片查看本币种参与者。分类图点击某类型，列表为该类型 + 该币种 + isForecastEligible，金额之和与图中一致。

实付卡片打开当前区间和指定币种的 PaymentDetailRow 列表，显示币种、含首尾日期和付款笔数。可查看详情及纠正付款；保存后父仪表盘与下钻视图同时以新版本刷新，避免旧卡片配新明细。

下钻在统计页面自己的 Sheet/详情区域完成，不写 WindowSession.filter；返回保留范围、币种和滚动位置。数据变化导致当前条目离开集合时明确提示并刷新；不为了保留列表强行改业务状态。

从下钻列表再打开订阅详情时，使用 Tab1 共用详情并默认历史当年；仪表盘付款日期范围不隐式传给详情年份。若直接点击一笔付款“纠正”，以 paymentID 打开该付款编辑，不先按当年过滤掉它。返回保持统计原范围。

详情的周期年筛选按覆盖区间相交，统计/详情实付按付款日，所以跨年周期可在两年显示，但一笔付款只在付款年统计。主仪表盘本月/本年/自选范围保持原定义，不因为详情出现年份栏而改成周期年归属。

## 3. 数据库与统计字段

### 3.1 表与读写边界

不创建 dashboard_totals、monthly_spending 等物化汇总表；在需求规模内从一致数据快照聚合，避免多份事实和跨日更新错误。

| 表 | 使用字段 | 用途 / 写入方 |
| --- | --- | --- |
| subscriptions | id、name、billingKindRaw、managementStateRaw、expiryDay、categoryRaw、cycleMonths?、periodAmountMinor、currencyCode、currencyScale、图标引用 | 数量、预估、临期、分类；统计只读 |
| subscription_periods | 全部周期字段、父订阅及付款反向关联 | 不聚合成实付；详情、完整备份、恢复和清空使用 |
| payments | id、subscription、periodRecord?、kindRaw、paymentDay、amountMinor、currencyCode、currencyScale、periodStartDay、periodEndDay、note、createdAt、revision | 只以付款自身事实计实付；可选周期关联不影响金额 |
| icon_assets | 全字段及文件 | 临期图标、完整备份；统计只读 |
| service_templates | 全部用户模板字段、图标引用 | 统计不读、不计数；完整数据包包含它 |
| app_settings | 全字段 | 设置读写及备份，详见第 4 节 |
| store_metadata | datasetID、storeRevision、schemaVersion | 统计版本、导入预览、恢复维护 |
| mutation_receipts | operationID、digest、resultData 等 | 写入安全重试；不包含在 V1 数据包中 |

subscriptions、payments、icon_assets 的完整逐字段约束沿用 Tab1 第 4 节；本模块以下字段均为这些表的明确投影，不扩展隐含事实字段。

### 3.2 输出字段字典

| 输出类型 | 字段 | 类型及含义 |
| --- | --- | --- |
| OverviewCounts | total、effective、expired、inactive、unknown、effectiveRecurring、effectiveLifetime | 四主类和=total；两子类和=effective |
| CurrencyEstimate | currency、scale、subscriptionCount、monthly、annual | 金额 Decimal，未舍入；只包含 isForecastEligible 的周期型 |
| ExpiringSubscription | id、name、iconAssetID?、symbolName、expiry、remainingDays、revision | recurring，expiry 非空，remainingDays 0…N；统一详情入口 |
| CategoryAmount | category、subscriptionCount、annualAmount、share?、subscriptionIDs | 年化仅 recurring；总额 0 时 share=nil；ID 用于同快照下钻 |
| CategoryBreakdown | currency、scale、totalAnnual、rows、emptyReason? | emptyReason = noEffectiveSubscriptions / zeroTotal |
| SpendingTotal | currency、scale、amount、paymentCount | amount Decimal，允许 0；按历史付款分组 |
| SpendingSummary | range、allTimePaymentCount、rangePaymentCount、totalsByCurrency | 区分全库无历史和范围内无历史 |
| PaymentDetailRow | paymentID、subscriptionID、periodRecordID?、subscriptionName、kind、paymentDate、Money、periodStart?、periodEnd?、note、paymentRevision、subscriptionRevision | 最新版本；不从周期报价或当前价格回填 |

付款明细默认由已加载快照分页/虚拟展示。需求规模为 10,000 笔时可一次读取值类型数据并后台聚合；视图只渲染当前屏幕，不每个统计卡片分别全库读取。

## 4. 设置的表、字段与交互

### 4.1 设置表

`app_settings` 对应 AppSettingsRecord，唯一 `id=main`。存同一 SwiftData 数据集，确保恢复时数据库、图片和设置整体切换。系统授权与临时窗口状态不入表。

| 字段 | 类型 | 默认值 | 校验与语义 |
| --- | --- | --- | --- |
| id | String | main | 唯一单例，不接受外部任意 ID |
| appearanceRaw | String | system | system / light / dark |
| notificationsEnabled | Bool | false | 全局提醒意图，不等于授权 |
| reminderOffsetsData | Data | JSON `[0,1,3,7]` | 非负整数、去重、升序；空列表表示无时间点 |
| reminderMinuteOfDay | Int | 540 | 0…1439，本地时分 |
| viewPreferencesData | Data | ViewPreferencesV1 JSON | 固定结构，有版本且严格解码 |
| revision | Int64 | 1 | 每次设置事务增加，防多窗口覆盖 |
| updatedAt | Date | 提交时间 | 审计字段，恢复保留备份值 |

`ViewPreferencesV1` 字段如下，JSON 中不可出现 NaN/Infinity：

| 字段 | 类型 / 默认 | 使用方式 |
| --- | --- | --- |
| version | Int / 1 | 不认识的版本拒绝或经显式迁移 |
| windowWidth / windowHeight | Double / 1100、720 | 点，下限 960×640；恢复时另限制到可用屏幕范围 |
| sidebarWidth | Double / 220 | 工程默认范围 180…280 点 |
| sidebarVisible | Bool / true | 新窗口及数据集恢复后默认 |
| timelineZoom | String / fiveYears | oneMonth / threeMonths / oneYear / fiveYears |
| overviewGrouping | String / none | none/category/managementState |
| overviewVisibleColumns | [String] / 默认全部列 ID | 去重、仅已知列 ID，必须包含名称列 |
| overviewColumnWidths | [String:Double] / 空字典 | 有限正数，按列最小/最大可用宽度约束；空为系统默认 |

尺寸/侧边栏在最近活动主窗口布局稳定后去重、合并写入，不每个像素移动都更新数据库。已有窗口保留自己的 SceneStorage；设置偏好用作新窗口及恢复后的默认，不强制把所有窗口改成同样状态。

外观数据库值为事实来源，现有 AppStorage 仅作镜像。会话筛选、临期 N、组折叠、草稿、统计范围、详情年份/子视图、时间线中心及系统私有窗口恢复存档不备份；列配置和默认分组仍是可备份偏好。详情新打开总是 currentYear，不恢复某个旧年份。

### 4.2 设置窗口

| 分区 | 内容 | 保存方式 |
| --- | --- | --- |
| 通用 | 跟随系统/浅色/深色、视图默认偏好 | 外观即时提交；其余去重或显式保存 |
| 提醒 | 全局开关、提前天数、本地时间、权限和调度状态 | 参数校验后一次提交，用户主动开启才请求授权 |
| 数据 | `.periodicdata` 导入、完整备份导出 | 校验、预览并确认；不展示未实现功能 |

设置接口使用 typed patch，只改当前操作字段，避免更改外观时覆盖其他窗口刚改的提醒。系统授权行为及 NotificationReport 详见 Tab2 第 6 节。

## 5. 统计和设置接口

接口为本地 Swift 协议设计，命名请求/响应类型的字段由下表定义；公共版本、金额、错误沿用 Tab1。

```swift
protocol StatisticsService: Sendable {
    func load(_ query: DashboardQuery) async throws -> DashboardSnapshot
}
protocol SettingsService: Sendable {
    func load() async throws -> SettingsSnapshot
    func update(_ request: UpdateSettings, context: MutationContext) async throws -> SettingsSnapshot
}
```

| 类型 | 字段及契约 |
| --- | --- |
| DashboardQuery | today、spendingRange、chartCurrency、dueHorizonDays（7/15/30）；没有共享表格筛选参数 |
| DateRange | start:LocalDate、end:LocalDate，包含两端；start ≤ end |
| DashboardSnapshot | version、asOfDay、dueHorizonDays、counts、estimates、expiring、categoryBreakdown、spending、paymentDetails、subscriptionRows；后者用于数量/类别下钻 |
| DashboardDrilldown | counts(bucket/subtype?) / estimate(currency) / category(currency,category) / spending(currency,range)；从同一快照筛选，不改共享 filter |
| SettingsSnapshot | version、settingsRevision、appearance、ReminderPreferences、ViewPreferencesV1 |
| UpdateSettings | expectedSettingsRevision、SettingsPatch；按字段修改，保留未指定字段 |
| SettingsPatch | appearance?、reminderPreferences?、viewPreferences?；nil 表示不修改，列表为空与未修改不同 |

统计从同一次 StoreActor 快照读齐订阅和付款，计算使用同一个 today。SettingsService 写入也经过唯一 StoreActor 和操作回执；返回的设置快照为本次提交结果，重试相同 operationID 不重复写入。展示更近版本时不能用旧回执覆盖最新 UI，必要时再 load。

错误：统计参数非法返回 validation；读取失败返回 storageFailure；设置并发变化返回 revisionConflict；维护期间返回 maintenanceInProgress；数据集已切换返回 datasetChanged。提醒调度失败不改变设置提交成功的事实。

## 6. 已取消的 CSV 历史设计（非实现要求）

### 6.1 标准字段与映射

标准表头固定顺序：

```text
id,name,symbolName,category,managementState,billingKind,periodStart,expiryDate,cycleMonths,periodAmount,currency,note,reminderEnabled
```

| CSV 列 | 对应字段 | 标准输出 / 输入约束 | 新建缺省处理 |
| --- | --- | --- | --- |
| id | subscriptions.id | UUID 字符串 | 无 ID 分配 UUID，并保存在预览计划中 |
| name | name | Unicode 原文，保存前 trim | 必须映射或显式提供值 |
| symbolName | symbolName | SF Symbol 名称 | app.dashed |
| category | categoryRaw | Tab1 的固定 rawValue；外部中文/其他值需映射 | other，并在预览标明 |
| managementState | managementStateRaw | active / inactive；已过期不是此枚举 | active，并标明 |
| billingKind | billingKindRaw | recurring / lifetime；外部终生字样须明确映射 | 新建默认 recurring 并提示；更新未映射保留现值 |
| periodStart | periodStartDay | 输出 YYYY-MM-DD；输入也支持 YYYY/MM/DD | nil |
| expiryDate | expiryDay | 周期型同上，不接受含糊格式；终生必须空 | nil |
| cycleMonths | cycleMonths | recurring 为 1/3/6/12；lifetime 空 | 周期型必填；终生不得填 0/超大周期 |
| periodAmount | periodAmountMinor | 周期价格/终生一次性价格；固定十进制、无符号/千分位 | 必填或显式默认，0 合法；不生成付款 |
| currency | currencyCode、currencyScale | 大写 ISO 代码，scale 从目录求得 | 必须映射或显式默认，不能推断符号 |
| note | note | 多行文本，完整 CSV 转义 | 空串 |
| reminderEnabled | reminderEnabled | true / false；终生必须 false | 周期 true，终生 false，并标明 |

标准输出为 UTF-8 BOM、逗号分隔、CRLF 行结束。解析接受有无 BOM、CRLF/LF，并支持引号内换行、逗号及双引号转义，不能用 `split(",")` 或逐行分割代替 CSV 解析。重复/空表头、未闭合引号和列数异常必须报告。

输出示例（展示内容不含不可见 BOM）：

```csv
id,name,symbolName,category,managementState,billingKind,periodStart,expiryDate,cycleMonths,periodAmount,currency,note,reminderEnabled
8C1E1B28-54C3-4E3E-A487-2404DCD6F6D2,示例订阅,app.dashed,tools,active,recurring,2026-01-01,2026-12-31,12,88.00,CNY,"个人用途,年度",true
187B712A-EEC4-44C6-9BDD-1B154F8E13F0,示例终生工具,app.dashed,tools,active,lifetime,2026-09-22,,,199.00,CNY,一次性价格未登记付款,false
```

示例仅用于测试，正式空库不插入。CSV 不含周期历史、付款、图标文件、设置、审计时间及派生状态；有图片的条目导出后备符号，当前日期不是历史表的替代。

同时兼容旧的 12 列标准表头：新建无 billingKind 列时明确采用 recurring；更新未映射该列则 keep。旧文件的无日期行不能自动升级为 lifetime，缺周期的新建行仍需补齐或明确映射终生。用户服务模板不通过订阅 CSV 导出，使用完整备份保存。

### 6.2 文本公式前缀的可逆处理

仅对用户文本列应用公式前缀保护，再执行 CSV 引号转义。文本首字符为 `= + - @ '` 时在最前面增加一个单引号；其他文本不变。ID、金额、日期、枚举不是自由文本，不使用这层处理。

| 原始用户文本 | 标准 CSV 解码后字段值 | 标准模板模式回导 |
| --- | --- | --- |
| =SUM(A1:A2) | '=SUM(A1:A2) | =SUM(A1:A2) |
| '原本有引号 | ''原本有引号 | '原本有引号 |
| 普通文字 | 普通文字 | 普通文字 |

导入向导明确展示“标准模板还原转义 / 外部文件保留原文”模式。标准模式仅在字段以单引号开头且下一字符属于 `= + - @ '` 时去掉一层，不能把所有单引号无条件删除。标准表头识别后可推荐该模式，但预览仍让用户切换；外部 CSV 默认不去掉前缀，避免破坏原文。

### 6.3 金额与枚举解析

先确定币种，再解析金额。金额仅支持十进制小数点及严格三位一组的逗号千分位，CSV 内含逗号的字段必须加引号。`1,234.50` 合法，`1,23.50` 报错；不猜测逗号小数、指数或括号负数。前缀代码必须与确定币种一致。

`$`、`¥` 不能独立推出 USD/CNY。只有币种列或明确默认给出相容币种后才允许移除这些前缀；`USD 10` 对应 CNY 列则报币种冲突。负数、精度超限、Int64 最小单位溢出均为逐字段错误。

外部类型、状态、周期和布尔文本先生成待映射值清单；“已过期”只能提示它是派生标签，用户明确映射为 active/inactive 或忽略该列，不能自动认作停用。月均、年化、剩余天数列一律标为忽略，不能转换为周期价格而不经用户确认。

外部周期值“终生/永久/一次性”进入计费类型映射，将 billingKind 设 lifetime、cycleMonths 设 nil；这是用户明确确认的映射，不能由空日期或价格猜测。终生行携带 expiry/cycle 或 reminder=true 时产生逐行冲突；“清空不适用字段”选项必须展示前后差异、经用户选择后才可生成计划。

### 6.4 导入流程与更新语义

1. 系统选择器选 CSV，复制至操作临时目录，记录文件摘要；解析与预览都针对这份固定副本。
2. 自动识别标准列，外部列手动映射；一个目标字段至多一个来源。来源可为列、用户明确的常量或不映射。
3. 映射枚举、选择文本模式和批量默认值；新建必须得到名称、billingKind、金额、币种，recurring 还须得到合法周期。
4. 每行展示原 CSV 记录序号、起始物理行号、原值、归一化值、默认/继承字段、错误和预计操作。
5. 与库中 UUID 相同默认 skip；用户明确选 update 才更新。无 ID 在预览中分配新 ID；修改映射不重新随机生成同一行 ID，最终计划变化后重新确认。
6. 文件内重复 UUID 标冲突；修正或明确排除多余行后再生成有效计划。同名不同 ID 仅提示，不合并；无 ID 文件重复导入可能新增重复记录，预览说明。
7. 错误须修正或用户明确排除对应行。后退修改内容、映射、文本模式、默认值或冲突动作都使旧计划失效。
8. 预览无未处理错误后确认，以单事务提交全部选定新建/更新。成功报告新增、更新、跳过、排除数量，四类合计等于数据记录数。

更新采用 `FieldPatch<T> = keep / set(T) / clear`：未映射字段 keep；有映射或显式常量则 set；映射的可空日期空值为 clear，备注空值清空为空串。名称、金额、币种等必填字段的映射空值报错，不用数据库现值悄悄补齐。

cycleMonths 的 clear 仅在合并结果为 lifetime 时合法；只改 billingKind 而保留冲突到期/周期/提醒必须报错，不能暗中清空。终生改回 recurring 需合法周期，其未知到期不等于无效输入，但不参与预估/提醒。任何类型变化都保留付款历史。

新建默认值不隐式成为更新 patch；如果要对已有行应用默认常量，必须在映射中明确选择，预览显示前后差异。更新校验基于“现有记录 + patch”的完整结果；仅改币种或金额时也必须合并校验金额精度，不重新解释未映射价格的数值。周期起止日期同理检查。

例如仅把 CNY 改为 JPY，原价格 88.00 应成为 JPY 88，而非把 8800 最小单位直接当作 JPY 8800；原价格 88.50 无法按 JPY 精度无损表达时必须报错。只改金额时使用原币种精度。两种操作都不修改付款快照。

无映射字段保留现值；周期历史、付款和图片关系保持，symbolName 只更新后备符号。CSV 不生成周期或付款，也不把更新的当前日期回填到历史，不改变已有 createdAt。

### 6.5 原子提交和导出

ImportPlan 绑定 datasetID/storeRevision、输入摘要、映射摘要、确定的 ID 和行操作。确认时取得 StoreActor，重新检查版本与字段；数据已变化返回 stalePlan，重新预览。事务中所有新建/更新、revision、元数据和回执一次保存，失败全部 rollback；成功后仅发布一次数据事件并核对提醒。

若所有行均 skip/exclude，则报告“没有需要写入的记录”，不虚增业务版本。相同确认的重试沿用 operationID；服务回执保存导入计数，不能在已成功后重试变成一批新的随机 UUID。

导出默认全库。Tab1 可以明确选择当前筛选结果，传入已展示的 ID 集与版本，预览导出数量；不能悄悄继承某个其他窗口的筛选。数据变更后重新展示数量。确定快照后一次生成文件，不在每一行输出时重新查询数据库。

写入目标目录的临时同级文件，flush/close 成功后原子替换目标；失败保留既有文件并清理临时内容，不把部分 CSV 报告为成功。文件访问使用系统选择器和安全作用域，服务不长期保存用户绝对路径。

### 6.6 CSV 接口

```swift
protocol CSVService: Sendable {
    func inspect(source: AuthorizedFile) async throws -> CSVInspection
    func preview(_ request: CSVPreviewRequest) async throws -> CSVImportPlan
    func commit(planID: UUID, context: MutationContext) async throws -> CSVImportResult
    func previewExport(scope: CSVExportScope) async throws -> CSVExportPlan
    func export(planID: UUID, destination: AuthorizedFile) async throws -> FileExportResult
    func discard(sessionID: UUID) async
}
```

| 类型 | 字段和契约 |
| --- | --- |
| CSVInspection | sessionID、fileDigest、headers、recordCount、sampleRows、parseIssues；解析失败不产生可提交计划 |
| CSVPreviewRequest | sessionID、columnMapping、valueMappings、explicitDefaults、textMode、perRowAction、excludedRows |
| CSVRowPreview | rowIndex、startLine、assignedID、operation(create/update/skip/exclude)、before?、after?、issues、warnings、defaultedFields、inheritedFields |
| CSVImportPlan | planID、sessionID、version、digest、rows、create/update/skip/excludeCount、canCommit；完整计划服务端保留，UI 不直接回传实体数组 |
| CSVImportResult | version、inserted、updated、skipped、excluded、affectedIDs、replayed；四类计数守恒 |
| CSVExportScope | all / selectedIDs(ids,expectedVersion) |
| CSVExportPlan | planID、version、scope、recordCount、固定快照、textEscapeMode |
| FileExportResult | displayFilename、byteCount、sha256、completedAt；仅成功发布最终文件才返回 |

CSV 额外错误包括 invalidEncoding、malformedCSV、mappingConflict、rowValidation、duplicateID、unsupportedCurrency、stalePlan、fileAccessDenied、writeFailed。错误附行号和字段路径，不能只弹一个“导入失败”。解析/验证支持取消，进入单事务保存后仅等待提交结果，不承诺中途逐行撤销。

## 7. 已取消的整体恢复与清空历史设计（非实现要求）

### 7.1 包结构和字段

完整备份为可读 ZIP，不加密、不依赖网络；导出逻辑模型，不复制使用中的 SQLite/WAL。方案尚未发布，初始 BackupFormatV1 包含 billingKind、用户模板、周期历史及付款可选周期关联；发布后格式变更再显式升版。固定结构：

```text
manifest.json
subscriptions.json
periods.json
payments.json
templates.json
icons.json
settings.json
Assets/<iconID>.png
```

| 文件 / 类型 | 字段 | 类型及约束 |
| --- | --- | --- |
| manifest / BackupManifestV1 | formatVersion | Int，首版 1；未知未来版本拒绝 |
| manifest | appVersion、schemaVersion、currencyCatalogVersion | String；标识来源及校验目录，不代替格式版本 |
| manifest | exportedAt | ISO 8601 UTC 时间戳 |
| manifest | calendar | 固定 gregorian，业务日期没有时区偏移 |
| manifest | subscriptionCount、periodCount、paymentCount、templateCount、iconCount | Int，与内容一致；periodCount 不因跨年重复，templateCount 只数用户模板 |
| manifest | files | FileEntry 数组，列出除 manifest 自身外的所有文件 |
| FileEntry | path、byteCount、sha256 | 安全相对路径、非负长度、实际内容摘要 |
| subscriptions.json | BackupSubscriptionV1 数组 | 包含每条订阅全部事实字段、revision 和审计时间 |
| periods.json | BackupPeriodV1 数组 | 周期 ID、父订阅、来源/类型、完整日期/报价快照及审计字段 |
| payments.json | BackupPaymentV1 数组 | 包含每笔付款快照、父 UUID、revision 和审计时间 |
| templates.json | BackupTemplateV1 数组 | 全部用户模板字段、图片引用、revision、审计时间；不包含内置目录 |
| icons.json | BackupIconV1 数组 | id、relativePath、sha256、mimeType、byteCount、pixelWidth、pixelHeight、createdAt |
| settings.json | BackupSettingsV1 | id=main、appearance、ReminderPreferences、ViewPreferencesV1、revision、updatedAt |

BackupSubscriptionV1 的完整键：`id,name,symbolName,iconAssetID,category,managementState,billingKind,periodStart,expiryDate,cycleMonths,periodPrice,note,reminderEnabled,revision,createdAt,updatedAt`。lifetime 的 expiryDate/cycleMonths 为 null，reminderEnabled=false；periodPrice 沿用键名，此时表示一次性价格。

BackupPeriodV1 的完整键：`id,subscriptionID,source,periodType,startDate,endDate,quotedAmount,currency,currencyScale,note,revision,createdAt,updatedAt`。quotedAmount 为十进制字符串或 null，未知不能写成 0；lifetime 的 endDate=null，其余日期完整。ordinal/year 为派生值，不写备份。

BackupPaymentV1 的完整键：`id,subscriptionID,periodRecordID,kind,paymentDate,paidMoney,periodStart,periodEnd,note,revision,createdAt,updatedAt`。periodRecordID 可 null；非空时必须存在且父订阅相同。

BackupTemplateV1 的完整键：`id,name,aliases,category,symbolName,iconAssetID,suggestedBillingKind,suggestedCycleMonths,suggestedAmount,currency,currencyScale,revision,createdAt,updatedAt`。aliases 为 String 数组，建议金额为十进制字符串或 null；终生建议周期必须 null。模板未填建议金额时仍保留建议币种。

`periodPrice` 和 `paidMoney` 均为 BackupMoneyV1：`{ "amount": "88.00", "currency": "CNY", "scale": 2 }`。amount 是固定十进制字符串，不是 JSON 浮点数；精度、非负及最小单位范围按 Tab1 校验。LocalDate 输出 `YYYY-MM-DD`，未知日期和 iconAssetID 为 null，非空备注可为空串。

数据库关系在备份中用 UUID 表示：先建图片/订阅/用户模板，再建周期，最后建付款并建立可选周期关联。保留全部业务 UUID、价格和实付；跨年周期仍只一条。模板与订阅无必需外键，settings 输出可读结构。

不导出系统授权、待发送通知 ID、绝对路径、查询缓存、临时草稿、SceneStorage 私有存档、store_metadata 或 mutation_receipts。恢复创建新的内部 datasetID 与 storeRevision，保留用户业务 ID；这些内部版本变化不属于丢失用户数据。

### 7.2 一致备份流程

1. 获取活动数据集读取租约并暂停孤立资产回收；一次 StoreActor 读取取得订阅、周期、付款、用户模板、两种拥有者引用图片、设置及版本。
2. 释放写入阻塞后可以继续普通编辑，但导出始终使用这份固定快照。租约期间保留其中引用的不可变图标文件；恢复切换也不能提前删除被租用的旧目录。
3. 校验所有引用图标存在、可解码、摘要匹配；读取失败报错，不导出缺图的“成功备份”。
4. 在受控临时目录写 JSON、图片和清单，构建 ZIP；生成内容与清单逐一核对。
5. 写目标目录同级临时文件，完成关闭及必要 flush 后原子替换最终文件。已有同名文件由系统保存面板确认覆盖；失败保留已有文件。
6. 成功才返回 FileExportResult，释放租约并清理临时目录；取消或错误也释放租约。

进度分为读取快照、校验图片、写入包、完成。输出是否成功以最终发布文件为准，不以某个中间 JSON 已生成为准。

### 7.3 恢复前验证

文件经系统选择器授权后复制到操作临时目录并固定摘要，先校验后展示预览。首版由 ArchiveClient 隔离 ZIP 能力，优先验证系统 libarchive 的本地集成，无新增网络依赖；需覆盖 UTF-8 路径、读写 ZIP、损坏包错误，不能仅凭 SDK 中存在库文件就视为已完成接入。

| 校验层 | 必须检查 |
| --- | --- |
| 容器 | ZIP 结构完整、可读取、无加密条目、条目数与解压资源预算可接受 |
| 路径 | 仅清单允许的普通文件；拒绝绝对路径、`..`、反斜杠变体、符号/硬链接、规范化后重复路径和大小写碰撞 |
| 范围 | 标准化后每个最终目标仍在新 staging 根内；不能只靠字符串前缀检查 |
| 清单 | 必需文件齐全、版本受支持、长度及 SHA-256 相符、无未声明文件 |
| JSON | 指定版本结构、必填字段、枚举、日期、金额、settings 单例和偏好范围 |
| 身份 | 每种实体 ID 唯一；周期/付款父订阅存在；付款可选周期引用存在且同属订阅；两种图片引用存在；不依赖 upsert |
| 图片 | 所有声明图片实际存在且可解码，格式、摘要、大小及尺寸匹配；缺失拒绝 |
| 业务 | 当前计费类型与条件字段、历史 periodType/日期/可空报价、金额精度、付款覆盖快照及模板规则；历史类型不必等于当前类型 |

为避免恶意或意外超大包耗尽磁盘，ArchiveClient 要在解压前及过程中执行可配置预算。初始工程默认：压缩文件 ≤ 512 MiB、累计展开 ≤ 1 GiB、条目 ≤ 20,000、单个 JSON ≤ 128 MiB，图像按上传规范限制。超限明确报错并保留当前库，不静默截断数据；未来放宽需更新资源和失败测试。这些是工程参数，不替代 1,000 订阅/10,000 付款的性能验收。

解包后不调用任何包内脚本或可执行内容。版本首版只接受 BackupFormatV1；未来格式升级需增加明确的逻辑转换器，禁止将未来字段直接忽略后宣称完整恢复。

### 7.4 预览和整体替换

预览列明当前与待恢复的订阅数、周期数、付款数、用户模板数、图片数和设置变化，明确整体替换。先备份入口保留；验证失败不能确认恢复，取消只清理 staging。

RestorePlan 绑定当前 SnapshotVersion、包摘要和候选摘要。预览后任何库变更都要求刷新预览；点击确认后由 DatasetCoordinator 取得维护锁，排空已开始写入，阻止各窗口新写入并暂停通知核对。

数据集结构为：

```text
Application Support/Periodic/
  active-dataset.json                 # 活动指针：formatVersion、datasetID
  Datasets/<datasetID>/
    default.store                    # SwiftData 管理及其 sidecar
    Assets/<iconID>.png
  Staging/<operationID>/              # 包副本、验证结果、候选数据
  Recovery/                          # 切换日志，仅内部恢复使用
```

确认后的步骤：

1. 重新核对 plan 版本和包摘要；取得维护锁期间读写均路由到协调器，已有只读 UI 可继续显示旧快照并标记维护中。
2. 在新 datasetID 目录生成完整候选数据库、图片、用户模板及设置。以 V1 schema 导入保留业务 ID 的逻辑数据，新 metadata 的 storeRevision=0，回执为空。
3. 关闭/重新打开候选容器并读回校验实体数量、关系、金额和图片；候选服务装配完成但尚不对窗口发布。此阶段所有可失败的构建动作都发生在切换前。
4. 写好恢复日志及新指针临时文件，完成持久化准备后，在同一卷原子替换 active-dataset.json。这是整体替换的提交点，禁止分别覆盖 live SQLite、图片和 UserDefaults。
5. 将已准备好的候选 AppServices 发布到所有窗口，清除旧 datasetID 的选择、查询缓存和草稿，外观镜像从新 settings 同步；通知服务移除旧数据集请求并按本机权限核对新请求。
6. 显示恢复完成，释放维护锁。旧数据集在没有租约且成功切换已确认后由清理流程移除；清理故障不将新旧数据合并。

指针替换前任何失败都保留旧指针、原数据库、图标和设置；删除未激活候选即可。原子替换后的业务恢复已经提交，外观镜像、通知、临时文件清理等失败属于后处理，需显示“恢复已完成，某项后处理待重试”，不能误称整体恢复失败并要求再导入一次。

如果替换时进程终止，重启只依据原子指针选择一个完整数据集，再根据恢复日志清理未激活候选或继续后处理。活动指针无效或选中数据集无法打开时进入恢复错误页，保留文件，禁止自动新建空库。故障测试须证明不会出现新数据库配旧图片/设置的混合状态。

### 7.5 清除全部数据

清空预览列明订阅、周期、付款、用户模板、图片及设置并提供备份。普通删除订阅会删其周期/付款但不删模板；完整清空删除全部用户历史和模板，内置目录保留。

使用同一 DatasetCoordinator 创建空候选数据集及默认设置，验证后原子切换。成功后打开表格空态、全局提醒关闭、外观跟随系统，取消本应用待发送请求；系统授权保持本机原状，不尝试撤销。旧图片和数据集清理失败单独提示，后续启动重试，并明确不能保证对磁盘介质做安全擦除。

清空预览与恢复预览都绑定全库版本；维护期间禁止提交旧编辑、CSV 和设置修改。旧数据集的 MutationContext 永久不适用于新数据集。

### 7.6 备份和维护接口

```swift
protocol BackupService: Sendable {
    func export(destination: AuthorizedFile) async throws -> FileExportResult
    func inspect(source: AuthorizedFile) async throws -> RestorePlan
    func restore(planID: UUID, operationID: UUID) async throws -> DatasetSwitchResult
    func discard(planID: UUID) async
}
protocol MaintenanceService: Sendable {
    func previewReset() async throws -> ResetPlan
    func reset(planID: UUID, operationID: UUID) async throws -> DatasetSwitchResult
    func progress() async -> AsyncStream<MaintenanceProgress>
}
```

| 类型 | 字段及契约 |
| --- | --- |
| DatasetCounts | subscriptionCount、periodCount、paymentCount、templateCount、iconCount、settingsCount；新库 settingsCount=1，其余=0；不数内置目录 |
| RestorePlan | planID、expectedVersion、archiveDigest、candidateDigest、formatVersion、exportedAt、currentCounts、incomingCounts、settingsDifference、validationSummary |
| ResetPlan | planID、expectedVersion、currentCounts、defaultSettingsSummary |
| DatasetSwitchResult | operationID、previousDatasetID、version、restoredCounts、committedAt、pendingPostActions；明确数据集已切换 |
| MaintenanceProgress | operationID、kind、phase、completedUnits、totalUnits?、canCancel、message |
| phase | reading / validating / waitingForWrites / buildingCandidate / activating / refreshing / completed / failed |

planID 指向服务端已验证临时内容，不允许 UI 拼接数据库路径。确认恢复/清空用 operationID 与恢复日志防止重复切换；重试同一次已提交操作返回现有结果，不把已经恢复的库再次替换。原子激活阶段 canCancel=false，其他尚未提交阶段允许取消并保留当前数据集。

错误应区分 unsupportedFormat、invalidManifest、unsafePath、duplicateID、brokenReference、missingAsset、checksumMismatch、invalidField、archiveBudgetExceeded、insufficientDiskSpace、stalePlan、maintenanceInProgress、candidateStoreFailed、activationFailed。错误附文件/字段/实体标识，日志不打印用户备注或付款明细。切换后后处理失败走状态流，不作为这些“未提交错误”返回。

## 8. 实现组织与交付顺序

| 建议目录 / 组件 | 职责 |
| --- | --- |
| Views/Dashboard/DashboardView、SummaryCards、CategoryChart、SpendingSection | 统计布局、图表和空态 |
| Views/Dashboard/PaymentDetailsView | 付款明细及共享付款维护路由 |
| Stores/DashboardStore、Services/Statistics/StatisticsService | 请求管理、后台纯聚合 |
| Views/Settings、Stores/SettingsStore、Services/SettingsService | 现有 Settings 场景扩展、设置统一来源 |
| Views/Settings/DataSettingsView、Views/DataExchange | 当前数据包入口、预览、确认及结果 |
| Services/DataExchange、Stores/DataExchangeStore | package 编解码、校验、快照和事务合并 |
| Services/DatasetCoordinator、Stores/DatasetLocator | iCloud 阶段再实现维护锁、候选构建和安全切换 |

文件选择器使用 SwiftUI fileImporter/fileExporter 或窄范围平台适配器。业务接入时增加 `com.apple.security.files.user-selected.read-write` 沙盒权限，并成对管理安全作用域访问；不开放全盘权限。图标和数据包共用 AuthorizedFile 边界。

实施顺序：

1. 在 Tab1 持久化及 Money/LocalDate 基础上实现统计纯聚合与全库快照；锁定周期/终生有效性与预估资格的区别、精度、互斥计数和实付边界。
2. 完成统计 UI、币种选择、日期范围、明细和共享维护回调，验证不继承其他 Tab 筛选。
3. 接入 app_settings、外观镜像、独立设置分区；与 Tab2 提醒授权和调度联调。
4. 数据包功能维持完整导出与合并导入边界，不追加 CSV、复制导入或整体恢复入口。
5. iCloud 阶段实现持久化 dataset revision、维护锁、合并器和候选数据集安全切换。
6. 完成多窗口维护状态、文件权限、辅助功能及需求规模测试。

全项目交付依赖为：Tab1 共享规则/存储 → Tab1 维护闭环 → Tab2 时间线与提醒、Tab3 统计 → Periodic 数据包 → 三个 Tab 联合验收。iCloud 的写入协调与安全切换另按扩展规格分阶段落地。

## 9. 验收矩阵与失败路径

| 场景 | 具体断言 | 需求 |
| --- | --- | --- |
| 概况互斥 | 停用先单列；active 无日期 recurring 进未知、lifetime 进有效；四项和=总数 | STAT-01、AC-07 |
| 全库预估 | 其他页面筛选不影响统计；三条年付 88 合计月均 22.00；USD 单列 | AC-05～06、AC-12 |
| 即将到期 | 默认 15 天包含今天和第 15 天，第 16 天/停用/无日期/终生排除，今天排前 | STAT-03 |
| 分类图 | 单币种、年化口径；CNY 无数据不自动切币种；全零不显示虚假占比 | AC-14 |
| 实付边界 | 区间首尾包含；过期/停用订阅付款仍在；当前调价换币不改历史汇总 | AC-07、AC-10 |
| 无记录与零元 | 无付款、区间无付款、存在零元付款三种状态不同 | AC-11、COST-06 |
| 设置 | 多窗口版本冲突不覆盖；恢复后外观与提醒偏好来自新数据集；系统权限仍用本机 | NAV、BACKUP-05 |
| 数据包往返 | Unicode、换行、金额、日期、终生、模板关系和图片逐字段相等 | AC-16、AC-28 |
| 数据包坏数据 | 坏日期、金额精度、未知枚举、重复 ID、坏摘要、越界路径和链接均在写入前拒绝 | AC-17、AC-19 |
| 数据包合并 | 新增、相同、冲突准确；同名不同 ID 不合并；历史和图片关系保持 | AC-17～18 |
| 数据包事务 | 第 N 条写入时注入错误，库和历史均不部分改变 | EXCHANGE-05 |
| 完整导出 | 从一致版本输出 V1 实体、用户模板、图片及设置白名单；并发编辑不混快照 | EXCHANGE-01～02 |
| 原生和离线 | Cmd+,、键盘向导、VoiceOver 图表列表、深浅色/透明度、无产品网络访问 | AC-21～22 |
| 数据规模 | 1,000 订阅 + 10,000 付款查询、聚合和数据包操作无持续主线程卡顿 | QA-03、AC-22 |
| 临期范围 | 默认 15，7/15/30 边界包含第 N 天；与 Tab2 共用 N 但此页始终全库 | AC-25 |
| 终生费用 | active 计有效且细分终生；不计预估/分类年化；只填价格仍无实付，登记零元付款有笔数 | AC-26～27 |
| 终生数据包 | billingKind、cycle/expiry、reminder 和冲突字段按领域规则往返 | AC-28 |
| 模板导入 | 用户模板 UUID、建议金额、别名及共享图片完整恢复 | AC-28 |
| 统计下钻 | 数量列表、图表参与者、币种实付明细均与同版本口径相等；返回不改共享 filter | AC-29 |
| 周期与实付 | 跨年周期两年可见但实际支出只按付款年；手动周期报价不进入实付，删周期保留付款 | AC-31～33、AC-35 |
| 历史备份 | periods.json 和可选 periodRecordID 正确往返；孤儿或跨订阅关联拒绝；跨年不复制；清空数量准确 | AC-36 |

统计、编码和事务采用隔离数据集的自动化测试；文件写入/替换、权限、取消与恢复使用临时沙盒故障注入，不能在用户正式库演练删除。最终在 macOS 26 实机或对应环境完成主要 UI、文件权限和系统提醒联合验收。

三份文档共同覆盖需求 AC-01～AC-36。文档完成不等于业务验收通过；开发时每个模块须记录实际测试结果后再标记完成。
