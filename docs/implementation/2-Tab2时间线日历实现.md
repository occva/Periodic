# 2. Tab2 时间线日历实现

> 版本：1.2｜日期：2026-09-22｜状态：待实现的详细设计。
> 产品依据：[需求文档](../requirement.md)。当前 AppShell 尚未实现本模块。

本文完整定义时间线 Tab 的需求、功能、数据库字段、接口、布局算法、提醒及验收。共用订阅编辑和数据库基础见 [Tab1 表格总览](1-Tab1表格总览实现.md)，偏好设置和数据恢复入口见 [Tab3 统计仪表盘](3-Tab3统计仪表盘实现.md)。

## 1. 需求与模块边界

| 需求 | 功能 | 数据及接口 | 用户结果 |
| --- | --- | --- | --- |
| TIME-01～04 | 横向连续日期轴，一条订阅一行，今天线 | subscriptions → TimelineService.load | 直接看到当前周期的到期位置 |
| TIME-05～07 | 1 月 / 3 月 / 1 年 / 5 年、横纵滚动、定位 | TimelineViewport、TimelineLayout | 缩放不丢失中心日期，范围外仍可定位 |
| TIME-08～09 | 无日期列表、详情、编辑、续费 | 同一筛选快照；复用 Tab1 服务 | 未知日期不伪造位置，修改后自动刷新 |
| TIME-10～13 | 前后平移、近 15 天卡片、终生独立列表 | dueHorizonDays、TimelineSnapshot | 临期不受轴上年份限制，终生不算未知 |
| DETAIL-01～08、PERIOD-01～07 | 从事件进入共享详情、当年历史、手动周期 | SubscriptionService.detail + PeriodService | 和列表同一详情；主轴不展开历史付款/周期 |
| NAV-05、RULE-01～04 | 共享筛选、自然日状态 | WindowSession.filter、Clock、DateRules | 与表格一致，跨日自动更新 |
| NOTIFY-01～06 | 全局授权、到期本地提醒、核对和点击路由 | app_settings + subscriptions；NotificationService | 系统授权下处理未来提醒，异常可见可重试 |
| UI-01～04、QA-01～04 | 原生布局、可访问性、滚动性能 | TimelineStore、LazyVStack、语义化控件 | 1,000 条订阅可用，不依赖网络 |

时间轴只展示每条周期订阅当前保存的到期事件；终生通过独立列表查看，不制造时间轴事件。不展开历史付款、不预测未来续费、不提供拖拽改期，也不写入系统日历。所有记录修改和模板新建调用 Tab1 共享服务。提醒设置仍在独立 Settings 窗口。

## 2. 功能与页面流程

### 2.1 页面结构

```text
工具栏：新建下拉｜搜索｜筛选｜范围 1 月/3 月/1 年/5 年｜前一范围/今天/后一范围
辅助入口：无日期周期项目(n)｜终生(n)
日期头：年份、月份/周/日刻度（纵向固定，跟随水平位置）
内容区：网格 + 红色今天线 + 纵向虚拟订阅行
每一行：左范围提示 / 精确日期锚点及标签 / 右范围提示
状态区：结果数量、加载/错误状态；需要时提示提醒调度异常
临期区：未来 7/15/30 天（默认 15）｜卡片数量｜详情/续费/轴上定位
```

每行只有一个事件。标签包含图标、名称、剩余天数和到期状态；起止日期齐全时附剩余比例。标签的开始位置跟随日期锚点，文字可以向右延伸，但不能为了放下文字移动日期锚点。停用行视觉弱化，保留真实日期和状态。

今天以红线和“今天 YYYY/MM/DD”文字共同标识。网格装饰不单独暴露给 VoiceOver；事件以完整名称、到期日期、剩余天数和管理状态提供可访问标签。

### 2.2 查询、排序与无日期

- 绑定 Tab1 同窗口的 SharedSubscriptionFilter，包括名称、管理状态、到期状态、服务类型、计费类型、币种；所有维度语义与表格一致。
- 筛选后分为 datedRows（有日期 recurring）、undatedRows（无日期 recurring）和 lifetimeRows（终生）；每个 dated 记录独占一行，按到期日、名称、UUID 升序稳定排列。
- 时间范围只影响坐标视口，不把范围外订阅从结果中筛掉。范围外的每行保留方向按钮。
- 无日期数量受相同筛选影响。点击“无日期(n)”打开 Sheet 列表，显示名称、管理状态、类型、补充日期操作；不在时间轴零点或今天放虚构事件。
- 补充日期调用共享编辑，成功后从无日期集合移入对应时间轴行；保留当前中心，提供定位已修改条目的入口，不自动强制移动用户视口。
- “终生(n)”单独显示同一筛选下的终生记录，提供详情、编辑、补录付款、复制、停用/恢复、删除；没有续费或补充到期日快捷操作。需改为周期型时进入完整编辑并明确切换。

### 2.3 首次进入和浏览

首次进入默认五年，今天位于日期内容区中央。恢复同窗口有效 SceneStorage 时使用原中心与缩放；无有效状态时才使用默认值。新窗口可使用用户保存的视图默认偏好，首次安装默认仍为五年。

| 动作 | 行为 |
| --- | --- |
| 水平滚动 | 向过去/未来浏览；日期头、网格、事件共享一份 offset |
| 纵向滚动 | 只移动行，日期头固定；虚拟化不可见行 |
| 切换范围 | 保留当前中心日期，包括小数日偏移；重新计算 pxPerDay |
| 点击今天 | 将今天日序号定位到中央，保留当前缩放 |
| 前一/后一范围 | 中心按当前缩放平移 ±1/3/12/60 公历月，月末钳制并保留小数日偏移；边界禁用 |
| 点击左/右范围提示 | 把该条目的到期日定位到中央，保留其行及纵向位置 |
| 点击日期点或标签 | 打开共享详情，历史默认当年，可手动维护周期和付款、编辑当前资料及续费 |
| 键盘激活事件 | 与点击一致；方向提示有日期和方向的可访问说明 |
| 系统减少动态效果 | 定位直接更新或缩短动画，不用大幅缩放动画 |

默认不允许拖拽事件。日期位置本身是事实的映射，修改日期必须经过共享表单的校验和保存。

### 2.3.1 详情与年份的作用范围

事件、无日期列表、终生列表及临期卡片使用同一个 detail(subscriptionID, history=currentYear) 路由。详情结构和接口以 Tab1 第 2.3.1～2.3.3、6.6 节为准；真正的服务请求类型为 SubscriptionDetailQuery，不另建日历专用详情。

详情历史表上方的年份栏默认当前公历年，不使用主轴 centerDay 的年份。即使用户正在主轴浏览 2024 年到期的记录，打开详情也先显示当年历史及“查看全部”入口；顶部当前日期仍展示真实记录，不能被选年隐藏。主轴默认五年、缩放和今天定位保持原设计。

返回详情时保持主轴中心、缩放、纵向位置、筛选及焦点。详情仅新增/纠正旧周期不会把主轴移到该历史结束日，也不会重排提醒；“应用到当前设置”、设置当前周期或续费提交后才刷新主轴当前到期锚点与通知。自动刷新保留 viewport，提供“定位新到期日”操作。

### 2.4 空态与错误

| 状态 | 表现 |
| --- | --- |
| 全库为空 | 提供新建与导入，保留范围工具栏 |
| 筛选后无任何结果 | 显示无匹配，提供清除筛选 |
| 有结果但全部是无日期周期型 | 时间区说明“这些订阅尚未填写到期日期”，突出无日期入口 |
| 仅终生或终生+未知周期型 | 显示“当前无可定位的到期日期”，分别列出终生/无日期入口，不称全部日期缺失 |
| 都在范围外 | 每行显示方向提示，今天和范围切换仍可操作，不显示成无记录 |
| 查询刷新失败 | 保留旧内容及视口，明确未刷新并提供重试 |
| 数据集恢复/清空中 | 维护遮罩，阻止新修改；成功后清除旧数据集选择和草稿 |

### 2.5 临期卡片及截图核对

截图中的“近 15 天即将到期”独立模块在本页保留，默认 N=15，可切 7/15/30。范围值放 WindowSession.dueHorizonDays，Tab3 共用范围值，但 Tab2 卡片取当前筛选结果、Tab3 取全库，分别标注“当前筛选”/“全库”。通知提前天数仍为设置中的 7/3/1/0，不能因切卡片范围而改通知计划。

卡片集合 = 已筛选 recurring + active + `0 ≤ D ≤ N`，按 expiry/name/UUID 稳定排序。它独立于时间轴 viewport：即使正在浏览 2020 年，未来 15 天卡片仍按今天计算。零条明确显示当前条件下无临期，不伪造内容；有多条使用横向滚动卡片或按窗口换行，并始终显示总数。

卡片包含图标、名称、实际到期日、D、准确标签，点击进入共享详情，操作提供续费及“在时间轴定位”。定位以该 ID 最新 expiry 为准，记录已改期/删除先刷新；定位不改搜索筛选。新建入口使用共享新建菜单，不能在卡片区直接插入一条无效空记录。

截图中的“本周/本月”仅作预警意图参考，统一用今天、7 天内、30 天内等滚动日标签；截图的“加载更多”通过虚拟化承载全部匹配条目，不能让未绘制行不计数。截图“在日历中管理”不扩展为系统日历集成。

## 3. 数据库与表设计

### 3.1 不新增时间线事实表

时间线是 subscriptions 当前事实的投影。remainingDays、expiryStatus、坐标、刻度、比例在内存计算，不建 timeline_events/每日状态表。subscription_periods 和 payments 的历史不参与主轴事件生成；只有共享详情查询它们，不能因为补录历史而多画一个主轴事件。

| 表 | 本模块读取字段 | 写入边界 |
| --- | --- | --- |
| subscriptions | id、name、symbolName、iconAsset、billingKindRaw、managementStateRaw、categoryRaw、periodStartDay、expiryDay、currencyCode、reminderEnabled、revision | 详情编辑/周期续费委托 Tab1；本页不直接写模型 |
| icon_assets | id、relativePath、sha256、尺寸 | 只读缩略图；维护由 IconService 完成 |
| app_settings | notificationsEnabled、reminderOffsetsData、reminderMinuteOfDay、viewPreferencesData、revision | SettingsService 提交后触发调度 |
| store_metadata | datasetID、storeRevision | 验证快照、通知任务是否过期 |
| mutation_receipts | 本页无需直接读取 | 共享编辑和设置写服务使用 |

关系沿用 Tab1：一条订阅可选一张图片，提醒直接依赖其 expiryDay，无需复制订阅名称和到期日到另一张提醒表。

### 3.2 字段与投影字典

| 字段 | 类型 / 来源 | 约束和用途 |
| --- | --- | --- |
| subscriptionID | UUID / subscriptions.id | 行、详情及通知路由稳定标识 |
| name | String | 标签；通知内容使用当前保存名称 |
| iconAssetID / symbolName | UUID? / String | 优先图片，加载失败使用符号 |
| managementState | active / inactive | 停用行弱化；仅 active 可调度 |
| billingKind | recurring / lifetime | 决定日期轴/无日期/终生三类集合；终生不调度 |
| periodStart | LocalDate? | 已知时计算剩余比例，未知不补默认值 |
| expiry | LocalDate? | recurring 有值进入 datedRows，nil 进入 undatedRows；lifetime 单列 |
| remainingDays | Int? / 派生 | expiry - today 的自然日数 |
| expiryStatus | ExpiryStatus / 派生 | 周期型六种标签，终生 perpetual；算法引用 Tab1 第 5 节 |
| remainingRatio | Decimal? / 派生 | 包含首尾日，clamp 0…1；缺起止则 nil |
| revision | Int64 | 详情编辑/续费使用最新版本 |
| centerDay | Double / 会话状态 | 公历日序号，可包含小数以支持平滑滚动；非业务日期 |
| zoom | TimelineZoom / 会话及视图默认偏好 | oneMonth / threeMonths / oneYear / fiveYears |
| horizontalOffset | CGFloat / 布局状态 | 像素滚动；从 centerDay 派生，不作为备份事实 |
| selectedSubscriptionID | UUID? / 会话 | 记录消失后清理，不能复用旧选择写新数据集 |
| dueHorizonDays | Int / WindowSession | 7/15/30，默认 15，两个页面共享范围值 |

Double 只用于屏幕坐标，数据库和日期业务仍使用整数自然日；不把浮点坐标反向当作真实到期日保存。

### 3.3 提醒字段

| 表字段 | 类型 / 默认 | 校验及语义 |
| --- | --- | --- |
| subscriptions.reminderEnabled | Bool / 周期 true、终生 false | 单条提醒意图；终生固定 false |
| app_settings.notificationsEnabled | Bool / false | 全局用户意图，不代表已获系统许可 |
| app_settings.reminderOffsetsData | Data / JSON `[0,1,3,7]` | 整数自然日，非负、去重、升序；可空表示不安排任何时间点 |
| app_settings.reminderMinuteOfDay | Int / 540 | 0…1439，540 即本地 09:00 |
| app_settings.revision | Int64 / 1 | 设置修改并发校验 |

日期减去提前天数若越界，设置提交或调度结果需给出具体错误，不 wrap 为另一日期。不把系统授权、pending 请求列表、已投递状态存进可备份设置；每次从系统获取当前状态。

## 4. 日期坐标与布局算法

### 4.1 坐标定义

令可用日期区宽度为 W，当前中心自然日序号为 C，可见跨度为 S 个真实自然日，则：

```text
pixelsPerDay = W / S
x(day) = W / 2 + (day.dayNumber - C) * pixelsPerDay
leftDay = C - S / 2
rightDay = C + S / 2
```

同一条公式用于事件、今天线、网格和点击定位。不得把每个月都当 30 天，也不得按数组位置均匀排月份。

范围对应公历月数 M = 1、3、12、60。切换范围时捕获中心对应的整数 LocalDate，以其减去 floor(M/2) 月作为跨度测量起点 A，以 A 加 M 月得到 B；S = B-A 的实际自然日数，再将该跨度对称放到原中心 C 两边。这样“一月”按中心附近真实月长定标，而视口可从月中开始；年和五年自然包含闰日。

一次缩放后 S 固定，平移不持续改变比例；再次缩放才重新计算。窗口变宽时固定 C 和 S，重算 pixelsPerDay。靠近支持日期边界时限制可浏览范围并显示边界提示，不能将坐标溢出为无效日期。

### 4.2 刻度、网格和文本

| 范围 | 主要刻度 | 分组标签 | 密度处理 |
| --- | --- | --- | --- |
| 1 个月 | 每日 | 月 / 年 | 空间不足时只画部分日数字，日期位置不变 |
| 3 个月 | 每周（公历周一） | 月 / 年 | 周线按真实日期，每月边界单独显示 |
| 1 年 | 每月首日 | 年 | 月宽随实际天数变化 |
| 5 年 | 每月首日 | 年 | 保留月网格；文字按可用间距抽样，避免 60 个标签重叠 |

先枚举视口及少量预取范围中的真实刻度日期，再映射坐标，不通过重复累加固定像素宽生成月份。只渲染可见刻度，行网格复用背景绘制，不每行各建一份完整网格视图树。

事件锚点在 `0…W` 时显示点和向右标签；标签宽度受剩余空间限制并可截断，完整内容通过悬停、详情及 VoiceOver 获取。锚点越过左/右边界时改为边缘方向按钮；按钮用于定位，必须与真正事件点的视觉样式区分，不暗示到期日就在边缘。

### 4.3 滚动同步与虚拟化

优先用 SwiftUI `ScrollView`、`ScrollPosition`、`onScrollGeometryChange` 管理滚动。日期头和内容不能各有独立的可变水平状态；维护一个 TimelineViewport 作为真值，由同一 horizontalOffset 驱动头部和行。

横向采用有限跨度缓冲区，例如约三个视口宽度，中间为当前可见范围。接近缓冲边缘时重置内容基准日和 offset，并保证重置前后 C 及所有可见日期的屏幕位置不变；不创建覆盖 0001～9999 年的巨大 Canvas。方向定位可直接重建缓冲中心，不逐像素滚过多年。

纵向使用 `LazyVStack`，固定或统一计算行高，按 subscriptionID 保持身份。单行只持有一个事件视图；共享图片缓存按 assetID + 摘要缓存。筛选/数据变化才重建业务投影，像素滚动只做布局，不重新查询数据库或计算全库费用。

先做小型布局验证：连续拖动、轨迹板双向滚动、缓冲重置、滚动条、窗口缩放和键盘焦点。只有原生方案确实无法保持同步/可访问性时，才引入窄范围 AppKit 滚动桥接；业务规则与坐标公式保持独立。

### 4.4 日期变化

App 级 ClockCoordinator 观察启动、前台激活、唤醒、系统日期/时区变化，并安排下一次本地午夜刷新。使用 Calendar 计算下一自然日边界，不能循环等待固定 86400 秒。休眠后先重新取 today，过期定时器不能补播多个旧事件。

跨日只刷新今天线、标签、比例、共享筛选结果与统计资格；保留用户当前中心。点击“今天”才将今天重新居中。提醒调度也订阅同一日期变化事件。

## 5. 时间线接口设计

沿用 Tab1 的 LocalDate、SubscriptionDTO、SharedSubscriptionFilter、SnapshotVersion、MutationContext 和错误定义。以下命名类型在表中定义字段，属于接口草案。

```swift
protocol TimelineService: Sendable {
    func load(_ query: TimelineQuery) async throws -> TimelineSnapshot
}
struct TimelineQuery: Sendable {
    let filter: SharedSubscriptionFilter
    let today: LocalDate
    let dueHorizonDays: Int
}
struct TimelineSnapshot: Sendable {
    let version: SnapshotVersion
    let asOfDay: LocalDate
    let totalCount: Int
    let matchedCount: Int
    let datedRows: [TimelineRow]
    let undatedRows: [UndatedRow]
    let lifetimeRows: [LifetimeRow]
    let upcomingRows: [TimelineRow]
}
```

| 类型 / 方法 | 输入或字段 | 返回与规则 |
| --- | --- | --- |
| TimelineRow | id、name、symbolName、iconAssetID?、managementState、periodStart?、expiry、remainingDays、expiryStatus、remainingRatio?、revision | expiry 非空；稳定日期顺序 |
| UndatedRow | id、name、symbolName、iconAssetID?、managementState、category、revision | 仅 recurring 且 expiry=nil；名称及 UUID 排序 |
| LifetimeRow | id、name、symbolName、iconAssetID?、managementState、category、revision | 仅 lifetime；无日期坐标，可进入共享详情 |
| upcomingRows | TimelineRow 数组 | datedRows 中 active 且 0≤D≤dueHorizonDays；不另查一个不同版本 |
| TimelineViewport | centerDay、zoom、spanDays、contentWidth、bufferBaseDay、scrollOffset | 窗口拥有，不进数据库 |
| TimelineLayout.project | datedRows、viewport、today | LayoutSnapshot：ticks、todayX、rowPlacements |
| RowPlacement | subscriptionID、position | position = event(anchorX,labelMaxWidth) / before / after |
| TimelineLayout.zoom | viewport、newZoom | 中心不变的新 viewport |
| TimelineLayout.center | viewport、targetDate | 缩放不变，中心为目标日 |
| TimelineLayout.scroll | viewport、deltaX | 更新中心与缓冲基准；不修改订阅日期 |
| TimelineLayout.shiftRange | viewport、direction(previous/next) | 按当前 zoom 对中心作公历月平移，保持 zoom，支持日期边界检查 |

TimelineService.load 不接收像素尺寸或视口范围，因此不会错误排除范围外记录。布局为纯函数；`datedRows.count + undatedRows.count + lifetimeRows.count == matchedCount`，upcomingRows 是 datedRows 的子集，不能重复加到匹配总数。

TimelineStore 在 MainActor 持有 snapshot、viewport、loadState、requestGeneration。新筛选、相关 DataChange、today 或临期范围变化触发 load；滚动只布局。旧响应丢弃；详情调用 `SubscriptionService.detail`，传 subscriptionID、currentYear、共享 today，历史改动用 PeriodService，当前改动/续费用 SubscriptionService。两者事件语义区分，不另写第二套规则。

## 6. 本地提醒功能与接口

### 6.1 开关与授权流程

1. 默认全局关闭，不在启动时弹通知授权。
2. 用户主动开启时，先检查系统授权；notDetermined 才请求 alert/sound 授权，保存用户开启意图。
3. 拒绝后设置显示“系统通知未允许”和打开系统设置指引，其他业务照常；保留开启意图便于用户授权后在前台核对时恢复调度。
4. 修改提前天数或时间先校验再一次保存，成功后核对请求。全局关闭时移除本应用的待发送提醒，不修改单条开关。
5. 从备份恢复的开启状态不能触发未经用户操作的授权弹窗；若系统尚未授权，显示需用户主动授权的状态。

### 6.2 计划生成

读取同一快照中的 settings 和 subscriptions，并捕获一次 now / timeZone。候选记录须满足 recurring、active、expiry 非空、reminderEnabled=true，全局也开启且系统允许通知。即使损坏/旧输入让终生记录带上日期，计划层仍拒绝调度并报告完整性错误。

对每个 offset，目标自然日 = expiry - offset，目标时间为该日本地 reminderMinuteOfDay。构造公历日期组件的 `UNCalendarNotificationTrigger(repeats:false)`，时区为本次系统时区。若时刻 ≤ now 则跳过，不补发。夏令时不存在的本地时刻采用 Calendar 的下一有效时刻，重复时刻取第一次；必须仍属目标自然日，否则跳过并在诊断中说明。

请求 ID：`subscription.<datasetID>.<subscriptionID>.<offsetDays>`。ID 不随名称/日期修改，修改后更新相同 ID 的内容和触发时间；新数据集使用新前缀，恢复后旧前缀全部移除。userInfo 仅包含 schemaVersion、datasetID、subscriptionID，不能依赖备份带回旧通知 ID。

通知文本包括当前名称、到期 `YYYY/MM/DD` 和目标通知日相对到期日的剩余天数。到期当天使用“今天到期”，不使用调度时刻的 D 作为数周后将显示的剩余天数。

### 6.3 核对、容量与竞态

`NotificationCoordinator` 为 App 级单实例，合并短时间多个变更，串行执行核对。触发原因：启动、回前台、时区/日期变化、订阅保存/改期/续费/停用/删除、单条或全局提醒修改、恢复/清空以及用户点击重试。

核对流程：读取最新期望计划 → 查询本应用系统 pending → 删除已无资格、旧数据集或不再存在的请求 → 对比并新增/替换有变化的请求 → 再读 pending 确认实际结果 → 发布状态。变更若在调度期间发生，递增 generation，中途检查并停止旧计划，最后再以最新版本核对一次，避免旧请求覆盖新日期。

系统待发送容量不作为无限资源。实现一个可注入 capacityBudget，初始工程预算设为 64，用目标 macOS 环境验证；这不是操作系统保证，API 也不提供统一的最大值查询。按目标时刻、订阅 ID、offset 稳定排序，优先最近请求；实际添加错误与 pending 核对可能进一步降低可用数量。无法安排的候选数显示为 deferredCount 或 failedCount，启动/回前台后补齐。

数量定义：candidateCount 为资格及未来时刻过滤后的候选；scheduledCount 为已核对正确存在的候选；deferredCount 为因预算未尝试的候选；failedCount 为尝试后仍未正确登记的候选。满足 `candidateCount = scheduledCount + deferredCount + failedCount`；清理旧请求失败另计 stalePendingCount。应用退出后系统可处理已提交的请求，不承诺后台自动扩充队列。

已到触发时刻的请求在核对时不属于未来候选，不能将正常消失误报为失败；系统状态快照与 now 需要一起更新。数据库提交成功后调度失败，不回滚订阅或付款，展示重试入口。

### 6.4 调度接口和输出字段

```swift
protocol NotificationService: Sendable {
    func authorizationStatus() async -> NotificationAuthorization
    func requestAuthorizationFromUserAction() async throws -> NotificationAuthorization
    func reconcile(reason: ReconcileReason) async -> NotificationReport
    func statusUpdates() async -> AsyncStream<NotificationReport>
}
protocol NotificationPlanBuilder: Sendable {
    func build(_ input: NotificationPlanInput) throws -> NotificationPlan
}
```

| 类型 | 字段 |
| --- | --- |
| NotificationAuthorization | notDetermined / denied / authorized / limited；保留平台原始状态用于适配 |
| ReconcileReason | launch / foreground / dayChanged / timeZoneChanged / dataChanged / settingsChanged / datasetChanged / retry |
| NotificationPlanInput | version、订阅 DTO 列表、ReminderPreferences、now、timeZoneIdentifier、authorization |
| ReminderPreferences | enabled、offsetDays:[Int]、minuteOfDay:Int；数据库映射见 3.3 |
| NotificationPlan | version、generation、computedAt、timeZoneIdentifier、按时刻排序的 candidates |
| NotificationCandidate | requestID、subscriptionID、offsetDays、fireDate:Date、dateComponents、title、body、userInfo |
| NotificationReport | version、checkedAt、authorization、globalEnabled、candidateCount、scheduledCount、deferredCount、failedCount、stalePendingCount、lastError? |
| NotificationRoutingPayload | schemaVersion:Int=1、datasetID:UUID、subscriptionID:UUID |

系统适配器封装 `UNUserNotificationCenter` 的权限、getPending、add、remove 调用，便于用 fake 验证拒绝授权、容量限制和添加失败。NotificationReport 为内存状态，不进入备份；启动后允许显示“正在核对”。

设置写接口复用 Tab3 `SettingsService.update`，禁止通知服务直接改数据库设置。UI 仅在用户明确开关动作上调用授权方法，不能由普通 reconcile 间接触发系统权限弹窗。

### 6.5 点击通知

通知 delegate 解析并校验 payload，转到 MainActor 路由。无主窗口时先创建主窗口，数据集未加载时暂存一条待处理路由；加载后检查 datasetID 和 subscriptionID。

存在当前记录则打开共享详情，不要求记录满足当前筛选；记录已删除或通知属于旧数据集时进入表格总览并提示记录不存在。点击旧通知不得自动创建记录、恢复过期数据或改变订阅日期。

## 7. 组件拆分与实现顺序

| 建议位置 | 组件职责 |
| --- | --- |
| Views/Timeline/TimelineView | 工具栏、加载状态、内容组合 |
| Views/Timeline/TimelineHeader、TimelineRowView、UndatedSubscriptionsView | 刻度、事件及无日期 Sheet |
| Views/Timeline/UpcomingCardsView、LifetimeSubscriptionsView | 7/15/30 天临期卡片、终生独立列表 |
| Stores/TimelineStore、Models/TimelineViewport | 快照请求、窗口滚动和缩放状态 |
| Services/Timeline/TimelineService、TimelineLayout | 读投影和纯坐标算法 |
| Services/Notifications/NotificationCoordinator、NotificationPlanBuilder | 串行核对与纯计划生成 |
| Services/Notifications/SystemNotificationClient、NotificationRouter | 系统 API 和点击转场 |
| Services/ClockCoordinator | 共享今天与日期变化事件 |
| Views/Settings/ReminderSettingsView | 独立设置窗口内的授权/提醒/状态视图 |

实施顺序：

1. 接入 Tab1 的 LocalDate、DateRules、过滤器、快照和维护路由，验证有日期周期/无日期周期/终生三个集合互斥且完整。
2. 实现并测试坐标公式、真实日刻度、缩放中心及范围外分类，再搭日期头和行。
3. 完成水平缓冲、纵向虚拟化、今天和事件定位；核对窗口变宽及缓冲重置无跳动。
4. 加入无日期与终生列表、近 15 天卡片、范围平移、共享编辑与周期续费、跨日刷新及可访问性。
5. 实现提醒计划纯函数、系统适配器和设置授权流程，最后接入提交事件与恢复事件。
6. 用大量数据和模拟系统失败验收，再在真实 macOS 26 验证滚动和通知。

## 8. 验收与故障测试

| 场景 | 断言 | 需求 |
| --- | --- | --- |
| 参考布局 | 日期横轴，一订阅一行，只有当前到期事件，无纵向日期分组替代 | TIME-01～04 |
| 月长及闰年 | 1 月 31 日、2 月 28/29 日、3 月 1 日间距按自然日，头部和锚点共坐标 | AC-03、AC-13 |
| 四种范围 | 首次五年、今天居中；来回切换保留同中心，窗口缩放不改变中心 | AC-13 |
| 缓冲重置 | 向两侧持续浏览时日期和鼠标下事件无可见跳位，纵向滚动不移动头部 | TIME-02、TIME-05 |
| 范围外事件 | 两侧方向正确，点击定位到精确到期日，不修改记录 | TIME-07 |
| 无日期 | 数量受相同筛选影响、天数未知、不安排提醒；补日期后进入时间轴 | AC-04 |
| 共享筛选 | Tab1 与 Tab2 匹配 ID 集合一致；表格金额排序不改变日历日期排序 | AC-12 |
| 跨日与时区 | today 和标签更新、原年月日不变、正在浏览的历史中心不被强拉回今天 | AC-02～03 |
| 默认与拒绝授权 | 首次不弹窗；主动开启才请求；拒绝不影响保存和续费 | AC-15 |
| 计划内容 | 默认 7/3/1/0 日 09:00；过去时刻跳过；目标日文案正确；重复 offset 无重复请求 | NOTIFY-02～03 |
| 修改与竞争 | 改期、续费、停用、删除移除旧请求；快速连续修改最终只保留最新计划 | AC-15 |
| 通知容量/失败 | 最近优先、四项候选计数守恒、待补数和失败数可见，重试不重复付款 | NOTIFY-05～06 |
| 数据集恢复 | 旧数据集请求移除；新权限取本机状态；旧通知点击回总览 | BACKUP-05 |
| 可访问性 | 红线有文字、方向按钮可键盘激活、事件 VoiceOver 信息完整、减少动态效果生效 | AC-21 |
| 规模 | 1,000 行只渲染可见/预取内容；像素滚动不触发 DB 读取，无持续主线程卡顿 | AC-22 |
| 15 天临期 | 0/15 日包含、16 日排除；切 7/30 边界准确；浏览历史年份不影响卡片；筛选仍生效 | AC-25 |
| 终生集合 | 不入 dated/undated/临期/通知，单独 lifetime 计数，三集合之和等于结果数 | AC-26 |
| 类型切换 | 周期改终生后移除旧通知及日期行；改回周期无日期后进入 undated，不造提醒 | DATA-06、AC-26 |
| 共享详情 | 任一事件/列表/卡片可进入，布局与 Tab1 一致；关闭回原中心、行与筛选 | AC-30 |
| 历史年份 | 主轴浏览旧年仍默认当年历史；详情切年不移动主轴、不改默认五年范围 | AC-32～33 |
| 历史和当前 | 补录旧周期不生成额外事件/提醒；应用到当前/续费才刷新当前锚点和提醒 | AC-34～35 |

坐标和提醒计划使用固定 Clock 的单元测试；滚动同步、系统权限、后台投递条件和辅助功能需实机检查。自动化只能证明请求构造与调度结果，不能把 Focus、休眠或系统策略下的实际送达时间当作应用保证。
