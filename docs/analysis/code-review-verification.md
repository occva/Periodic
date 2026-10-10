# Periodic 审查报告逐条核实

日期：2026-10-08。源码基线：`262eb66`。本次核实用户提供的审查报告，区分当前缺陷、条件风险、维护建议与误报，不实施应用修复。

后续已按用户要求修复确认项，参见 [修复与验证记录](code-review-fixes.md)。下文保留修复前基线的裁定和复现证据。

## 结论

优先处理 **M1 并发导入丢失更新、H1 编辑/详情目标失效**。M1 已通过现有 Store 的真实代码在内存和临时 SQLite 数据库中复现，应该提高优先级。

其次处理 **M6 展示舍入、导入同名分类、订阅表单放弃确认、M3 部分坏记录的可见提示、M4 图标文件回收**。M11 是刷新协调与效率问题；M5 记为没有当前 UI 读取方的潜在时序风险。

**M7、M8 不应作为当前功能缺陷；M10 指向的是不可达的外层 catch。M2 是后续模型演进风险，M9 主要是职责与复用建议。** 报告中的“全部已核实”不能代替可复查的执行路径和验证证据。

## 高危与中危项

| 报告项 | 核实结果 | 实际问题及适用边界 |
| --- | --- | --- |
| H1 跨窗口删除 | 核心成立，交互描述有夸大 | 删除并 reload 后，目标 DTO 已为 nil，但编辑和详情的呈现标志仍为 true。详情内容没有失效分支；编辑把 nil 当新建，保存入口可转为 create。状态测试已确认目标和呈现状态不一致。没有验证“只能关窗口”，不能把系统取消能力也断言为失效。 |
| M1 并发导入覆盖编辑 | **已复现，应优先修复** | 后台导入 1,001 条记录期间，另一 Store 编辑同一订阅。导入、编辑均提交成功，数据库最终保留 Imported，编辑内容丢失，revision 仍为 2。内存和 SQLite 两种配置都出现。报告把图标写盘放在 digest 后面不正确：资源先写，Store 再检查 digest；真正未保护的是 digest 检查到最终 save 之间的数据库写入。订阅 apply 递增的是目标记录 revision，也不是导入方 revision。 |
| M2 V2–V6 未冻结 Schema | 成立的演进风险，未证实当前迁移故障 | 这些版本共用顶层模型，未来修改属性会改变旧版本声明。应在下一次模型变更前处理，并使用真实历史形状验证迁移。现有历史中，V2 建立后共享模型的持久字段没有再次修改；不能据此断言今天所有旧库已损坏，也不能声称任意无默认值字段必然使所有版本全部失败。 |
| M3 坏记录被隐藏 | 成立，需要坏数据条件 | 一条有效、一条 categoryRaw 无法识别的记录：页面只返回有效记录，loadError 为 nil，数据库仍保留两条。问题是没有部分读取失败提示，数据没有物理删除。报告举的 planData 解码失败例子不准确：共享计划在循环前解码，失败通常使整个 fetchAll 抛错。 |
| M4 图标孤儿文件 | 成立，属于资源回收缺陷 | 图标选择先落盘，取消订阅/模板表单没有撤销文件写入；启动只扫描付款附件孤儿。只回收曾被数据库引用的图标，不能覆盖未提交的草稿图标。按内容或 URL 去重只减少重复，不限制不同图标的总量。 |
| M5 reload 缺 generation | 潜在时序风险，无当前用户可见故障 | 两个 reload 重叠时，第一个结束会把 isLoading 设为 false，第二个尚未结束；已用状态测试复现。不过当前页面没有读取 session.isLoading，不能直接推导用户看到错误加载提示。旧响应覆盖新数据属于需要继续保护的时序风险，本次未复现该结果。 |
| M6 展示/计算舍入差异 | **已复现** | 使用生产 Money 代码：JPY 3 / 6 个月，monthlyEstimate 为 JPY 0，annualEstimate 为 JPY 6，而 prorated(6→1) 为 1。formatter 默认 half-even 与 COST-03 的四舍五入不符。存储与中间 Decimal 计算没有因此丢精度。parse 中的 .plain 是精度检查，不是接受输入后舍入保存。月均显示乘 12 不等于年均本身也不能作为错误判据。 |
| M7 取消 fileImporter 弹错误 | **当前实机验证不成立** | 已补查不带 onCancellation 的准确重载文档，该重载也明确约定取消不调用 onCompletion。在 macOS 27.0.1 当前 Debug 构建的内存样例中，消费截图及本地图标两处选择器获得焦点后按 Esc，均正常返回原表单，没有错误告警。新增 onCancellation 参数和其他调用方的防御过滤都不能证明旧重载取消会进入 failure。 |
| M8 三档排序与五档统计冲突 | **当前入口不成立** | 状态排序实际只用于 session.datedItems，该集合已排除终生和无日期。三档排序与五类统计也不是同一个契约。报告指出的 nil→0 在当前调用链不可达，不会由此把这些项目计入有效统计。 |
| M9 续费日期双实现 | 维护建议，未发现当前结果错误 | 自动续费确认、手工补录拼车历史、可调整的周期报价不是同一种操作；拼车草稿还处理自定义天数和终生记录。共用日历运算可以提取，但不能因表达式相似就认定业务规则冲突。 |
| M10 reconcile 外层 catch 丢原因 | 当前故障结论不成立 | 外层 do 没有会向外传播的 Swift throwing 调用。center.add 的错误已经被内层 catch 捕获并记录 domain/code，其余调用不抛错或内部使用 try?。这个外层 catch 是冗余代码，不是已证实的实际失败诊断入口。 |
| M11 保存后重复 reload | 成立的重复工作，闪烁未证实 | 显式 reload 与 subscriptionDataVersion 的 onChange 都调用全量加载；通知核对也被重复排队。不能保证每次都恰好执行两轮，也没有证明必然可见闪烁。属于刷新协调与效率问题。 |

主要代码依据：

- H1、M5：[WindowSession.swift](../../Periodic/Features/Workspace/WindowSession.swift)、[ContentView.swift](../../Periodic/Views/ContentView.swift)、[SubscriptionEditorView.swift](../../Periodic/Views/SubscriptionEditor/SubscriptionEditorView.swift)。
- M1：[DataExchangeService.swift](../../Periodic/Services/DataExchange/DataExchangeService.swift)、[DataExchangeStore.swift](../../Periodic/Stores/DataExchangeStore.swift)。
- M2：[AppSchema.swift](../../Periodic/Stores/Schema/AppSchema.swift)，并核对共享模型的 Git 历史。
- M3：[SubscriptionStore.swift](../../Periodic/Stores/SubscriptionStore.swift)、[SubscriptionSharingPersistence.swift](../../Periodic/Stores/SubscriptionSharingPersistence.swift)。
- M4：[AppleIconCache.swift](../../Periodic/Services/AppleIconCache.swift)、[AppServices.swift](../../Periodic/Services/AppServices.swift)。
- M6：[Money.swift](../../Periodic/Models/Money.swift)、[COST-03](../requirement.md)。
- M7：[无 onCancellation 重载的原始契约](https://developer.apple.com/documentation/swiftui/view/fileimporter%28ispresented%3Aallowedcontenttypes%3Aallowsmultipleselection%3Aoncompletion%3A%29)，正文明确取消不调用 onCompletion；原始 Markdown 已核对。
- M8：[TimelineView.swift](../../Periodic/Views/Timeline/TimelineView.swift)、[WindowSession.swift](../../Periodic/Features/Workspace/WindowSession.swift)。
- M10：[SubscriptionNotificationService.swift](../../Periodic/Services/SubscriptionNotificationService.swift)。
- M11：[ContentView.swift](../../Periodic/Views/ContentView.swift)。

## 低危项拆分

| 报告中的断言 | 判断 | 理由与处理建议 |
| --- | --- | --- |
| 创建规范化 automaticallyRenews，导入却拒绝非法组合 | 契约差异，不足以认定用户缺陷 | 内部构造输入规范化与外部包严格校验可以有不同契约；正常表单也主动构造合法组合。需要明确 API 契约，不应一律要求内部输入和外部数据使用相同策略。 |
| LocalDate(Date) 失败回退 1970 | 防御性风险 | fallback 确实存在，但普通 DatePicker 和有效 Date 转换路径没有复现失败；ISO 日期导入是严格校验并抛错的另一入口。 |
| datasetID 首读生成不同 UUID | 条件竞争风险 | getter 的读取和写入非原子；实际启动通常先在 MainActor 的准备流程初始化。没有证实正常启动已经产生两个 ID，宜收敛初始化入口。 |
| 新汇率下载后写缓存失败，丢弃新数据 | 可用性改进 | 写失败后不会更新内存；latestCatalog 可回退旧缓存，但明确标 stale，手动刷新会抛错。不能称无标记的错误汇率或静默财务错误。 |
| 导入清理旧付款附件的失败集合被丢弃 | 即时重试缺口成立，“永不重试”不成立 | 导入后没有入持久重试队列；下次启动会扫描超过 24 小时的无引用附件并将失败入队。可以改善当次和下一次启动前的回收。 |
| preflight 枚举错误静默结束 | 错误传播缺口成立，未证实坏包会成功导入 | 错误回调 false 会停止枚举，却不抛出明确错误。后续 FileWrapper 的读取及 Codec 校验仍可能失败，不能略过这些后续检查断言验证已被绕过。 |
| 数据交换写死 standard，绕过 defaults 注入 | 测试与依赖一致性问题成立 | AppServices 接收注入的 defaults，DataExchangeService 没有沿用。生产默认 standard 的场景不等于已出现设置损坏，但注入场景不能保证隔离。 |
| 未知图标前缀跳过清理 | 泛化判断不成立；旧 Apple URL 有具体缺口 | 无法定位未知格式文件时不应猜测删除。代码仍支持旧 HTTPS Apple URL 的读取，但 removeStoredImages 只认识两个新前缀，因此这种已支持的旧引用确有残留问题，可并入 M4。 |
| JSONL 裸抛 DecodingError | 提示上下文不足成立 | 缺少表名、行号和恢复建议。不能保证系统文案永远是英文；该问题没有使失败包被部分保存。 |
| 删除分类未检查每个模板 revision，必然 TOCTOU | 未证实该具体结论 | 删除检查分类 revision，并读取当前模板后更新分类与模板 revision。是否存在其他 Store 写入竞态要验证实际交错，不能仅因级联操作没有携带用户表单的每个 revision 就认定丢失更新。跨 Store 写入统一边界应与 M1 一起考虑。 |
| 导入可产生同名分类 | **真实功能问题，已复现** | Codec 只检查分类 ID 唯一；Store 按 UUID 合并，不检查规范化名称冲突。两个不同 UUID、相同名称的分类能够 encode、decode、execute 并同时入库，绕过常规分类编辑的同名限制。 |
| 切回周期型开启 reminderEnabled | **这项不是缺陷** | DATA-06 明确要求切回周期型默认开启提醒，允许修改。不能按保存旧偏好的主观预期修改这条规则。 |
| 取消订阅表单不确认未保存修改 | **真实需求缺口** | 取消直接 dismiss；NAV-03 要求确认放弃。付款编辑器已有对应机制，应按草稿变化状态补齐。 |
| cycleMonths 为 0 时显示异常 | 非正常入口可达的防御建议 | 当前构造、读库及导入都限制合法周期；没有展示一条能由正常用户操作产生 0 月周期的链路。 |
| View 内分组求和、AppAppearance 依赖 SwiftUI | 分层维护建议 | 没有给出当前计算错误或 UI 错误；不应与用户数据丢失使用同一严重度。 |
| fetchDetail 三次 fetch 非一致快照 | 未复现的跨 Store 快照风险 | 同一 SubscriptionStore 内整个函数同步执行，不会因三次 fetch 自行发生 actor 重入。其他 Store 并行写历史时是否读到混合版本另需验证；不能据 fetch 次数直接断言。 |

关键依据：[TemplateCategoryStore.swift](../../Periodic/Stores/TemplateCategoryStore.swift)、[DataExchangeStore.swift](../../Periodic/Stores/DataExchangeStore.swift)、[DataPackageCodec.swift](../../Periodic/Services/DataExchange/DataPackageCodec.swift)、[SubscriptionEditorView.swift](../../Periodic/Views/SubscriptionEditor/SubscriptionEditorView.swift)、[NAV-03 与 DATA-06](../requirement.md)。

## 测试和文档判断

1. **共享 UserDefaults 的测试污染风险成立。** 语言测试直接切换 standard，其他测试读取同一全局语言并断言中文；测试库默认并行。一次测试通过不能排除竞态。仅给一个 Suite 加 serialized 也不能隔离其他 Suite，优先消除共享配置依赖。[Apple 的并行测试说明](https://developer.apple.com/documentation/testing/parallelization)。
2. **自动续费日期断言的独立性不足成立。** 用同一套 addingMonths/addingDays 表达式生成期望值，对算法回归不敏感；可以补固定日期及月末锚点。不过普通手动续费尚未实现，报告所谓“已过期从今天开始分支”不是当前自动续费确认规则中已有但没测的分支。整个日期模块也不是零固定日期测试。
3. **包解码的拒绝分支测试不足成立，数量表述不精确。** 现有测试不仅验证篡改，还拒绝非法续费记录、未引用图片和非法设置；版本兼容也已有测试。未来版本拒收、资源上限、路径规则等仍值得补独立解码测试，不能说整个 Codec 只有一条异常输入测试。
4. **通知真实系统交互缺少可注入替身的测试成立。** 当前大量纯计划、去重和指纹规则已测。中心通过初始化参数传入，但它是具体系统类型，难以模拟失败；这不等于通知整体没有回归保护，也不允许按项目约束补 UI 测试。
5. **其他未覆盖项是测试建设建议，不自动成为产品缺陷。** 付款截图导入成功路径已有测试，失败补偿目前主要针对图标；跨币种排序、空值排序及 prorated 溢出等可以补精确边界。RULE-03 已有多个刷新入口，缺测试不代表刷新功能没实现。EDIT-02 是功能缺口，需要与测试缺口区分。

AGENTS 的联网汇率与 CSV 表述确实滞后于 requirement v1.6。这是仓库规范冲突，不是代码擅自发送隐私数据的证据；本次分析不扩展网络访问或实现权限。

此前的 SubTracker 分析文档还可以改进引用和措辞：“当前有效”包含 active 终生已由 COST-01/STAT-01 决定；“核对是否包含”应改为明确验收该规则；“前次分析”指会话前两轮而非仓库文件，应写明；已有设计建议宜链接对应实现规格。这些是文档问题，不是应用运行缺陷。

报告总评也不宜直接采纳为已证明事实，例如测试代码确有闭合常量条件下的强制解包，而“全库无强制解包”“无崩溃路径”“可访问性完善”比可证明范围更强。

## 本轮验证记录

环境：macOS 27.0.1、Apple Swift 6.4。使用现有 `script/test.sh unit`，不运行 UI 测试；没有读取或修改正式用户数据库。

- 一次完整常规单元测试：原有 194 个测试和当时的 4 个观察场景，共 198 个测试通过，性能测试按脚本排除。
- 独立编译生产 Money 源码，确认 JPY 半单位展示为 0、prorated 为 1。
- 临时状态/存储测试确认 H1 的失效目标、M3 的部分隐藏、同名分类入库，以及 M5 的提前清除加载状态。
- 补充顺序测试确认已有记录编辑后，旧 import digest 会被拒绝。
- 首轮在 MainActor 发起的导入探针返回编辑 revisionConflict，未丢失已经提交的编辑。随后改为后台任务发起导入，模拟 DataExchangeService 的 actor 调用方向，才复现缺陷。这说明首轮通过不足以覆盖实际执行路径。
- 最终并发回归测试覆盖内存和 SQLite，两次运行均失败于“不应丢失成功编辑”的断言。两次证据都是 `import=committed; edit=committed; stored=Imported; revision=2`。这是确认缺陷的预期失败，不应改低断言以使其通过。
- 初轮没有验证 Sheet 外观、Esc 的真实界面行为或跨窗口完整点击链。后续针对 M7 完成下述手工实机验证；H1 跨窗口完整交互仍以状态和源码证据为限。

临时验证源与结果未加入仓库或测试 target。应用源码、持久模型、工程配置及已有测试不作改动。

### M7 后续实机核实

平台为 macOS 27.0.1，使用当前仓库 `build/DerivedData/Build/Products/Debug/Periodic.app`，以 `-store-in-memory -seed-test-data` 启动独立样例实例，没有启用样例系统通知。原有 Release 实例不用于判断当前源码行为。

1. 样例订阅详情 → 动态 → 记录消费 → 选择截图。文件选择器获得焦点后按 Esc，选择器关闭，返回原消费草稿；没有“无法选择消费截图”告警，付款仍为零笔。
2. 编辑样例订阅 → 本地图片。文件选择器获得焦点后按 Esc，选择器关闭，返回原订阅草稿；没有“无法选择本地图片”告警。
3. 两个草稿均未保存，验证后退出样例实例。没有新增或运行 UI 测试代码、target。

此前链接指向带 onCancellation 的重载，引用不够准确，现已替换为仓库实际使用的旧重载。该旧重载的文档与实机结果一致。其他系统版本没有在本次实测范围内。

### M7 回调级复核（追加）

按用户要求撤回后加的取消错误过滤，用原始 failure 分支再次核实。构建独立 Debug 内存样例，在选择器开关和 onCompletion 入口临时记录 OSLog；没有记录文件内容、路径或业务数据。测试完成后移除全部探针，取消过滤及其新增测试文件也已撤回。

| 选择器 | 操作 | completion / failure | 界面结果 |
| --- | --- | --- | --- |
| 消费截图 | Esc | 0 / 0 | 正常返回消费草稿，无错误告警 |
| 消费截图 | 点击取消 | 0 / 0 | 正常返回消费草稿，无错误告警 |
| 消费截图 | 正常选择测试 PNG | 1 success / 0 | 草稿显示截图，证明回调探针有效 |
| 本地图标 | Esc | 0 / 0 | 正常返回订阅草稿，无错误告警 |
| 本地图标 | 点击取消 | 0 / 0 | 正常返回订阅草稿，无错误告警 |
| 本地图标 | 正常选择测试 PNG | 1 success / 0 | 草稿显示图标，证明回调探针有效 |

两处均记录到 3 次打开、3 次关闭、1 次 completion、1 次 success、0 次 failure。临时日志只用于当次核验，未加入仓库。消费草稿与订阅草稿均未保存，消费仍为零笔；验证后退出样例。

结论：macOS 27.0.1 当前使用的旧重载在正常取消时只关闭选择器，不调用 onCompletion，因此没有进入弹错分支。M7 在这个验证范围内不成立，不能因其他调用方存在取消过滤就定性为遗漏缺陷。其他系统版本未验证。

## 修复范围建议

M1 应把各 Store 的写入放到一致的事务/互斥边界中，保证 digest 检查与导入提交相对于其他用户写入不可交错。只在 save 前再读一次 revision 仍有新的检查到写入窗口，不能替代原子边界。

H1 应固定草稿的编辑身份和打开时 revision，目标失效时明确结束或报告冲突，禁止因 DTO 查不到而自动转新建。详情应有失效处理；并发修改刷新也不应替换草稿保存所用的 revision 基线。

其余问题分别按领域舍入规则、分类唯一性、草稿退出确认、部分读取诊断、带引用/租约保护的文件回收处理；不需要以修复这些问题为由扩大为全应用重构。
