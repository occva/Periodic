# 项目结构与职责

Periodic 按职责和单向依赖组织代码，业务行为和外部接口不依赖文件位置：

```text
App ───────────────→ Views
                       ├──→ Features
                       ├──→ Services
                       └──→ Models
Features ───────────→ Services、Models
Services ───────────→ Stores、Models、系统适配器
Stores ─────────────→ Models、Schema
```

下层不反向依赖具体页面或 App 入口；Models 不依赖 SwiftUI、SwiftData 页面状态或系统服务。

## 目录职责

- `App/`：应用入口、Scene 和 Commands，只负责装配。
- `Features/`：窗口或功能范围内的可观察状态、筛选和展示协调；不保存 SwiftData 实体。
- `Models/`：稳定领域枚举、值类型、DTO、输入类型和纯计算。
- `Services/`：依赖聚合、系统客户端、内置资源加载及开发数据准备。
- `Stores/`：SwiftData 容器、事务入口和 `Schema/` 持久化实体。
- `Support/`：环境值、ViewModifier、日志、配置和小型平台胶水。
- `Views/`：按功能分目录；页面根视图、专用组件、布局和草稿类型就近放置。
- `Resources/`：本地化、Asset Catalog、内置目录和图标资源。
- `Tests/`：单元测试与 UI 测试，目录名称与被测职责对应。

## 文件组织约定

- 页面根文件只保留页面状态、主体组合、工具栏和用户意图转发。
- 可复用或独立测量的布局使用单独文件，例如 `IndependentColumnLayout`、`TimelineAxisLayout`。
- 纯展示组件不持有 Store 或 Service，通过明确输入、Binding 和闭包接收依赖。
- 表单草稿与行展示模型放在对应功能目录，不混入领域 DTO 或持久化实体。
- 领域文件按稳定概念拆分：日期、金额、分类、DTO、分析模型分别维护。
- 持久化写入只通过 Store；页面不直接操作 `ModelContext`。
- 新增类型优先放入现有职责目录；只有形成新的稳定业务能力时才增加顶层模块。

## 行为保持要求

结构调整不改变：

- 类型名称和现有调用接口；
- 数据模型、迁移和存储位置；
- 日期、金额、筛选和统计规则；
- 页面输入输出、交互路径与本地化文案；
- 并发隔离、事务边界和错误语义。

每批结构调整后运行现有单元测试；完成后运行完整测试和 Debug 构建。

## 可选扩展

需要独立架构边界或详细补充的设计放在 [扩展功能规格](extensions/README.md)：

- [iCloud 多端同步](extensions/1-iCloud多端同步规格.md)
- [AI 订阅助手](extensions/2-AI订阅助手规格.md)
- [数据导入与导出](extensions/3-数据导入导出规格.md)
- [菜单栏订阅速览](extensions/4-菜单栏订阅速览规格.md)
- [试用、取消计划与续费意图](extensions/5-试用取消计划与续费意图规格.md)
- [变更记录与安全撤销](extensions/6-变更记录与安全撤销规格.md)

扩展必须通过 Adapter 和 Service 接入，不能让文件格式、CloudKit 或 Provider SDK 反向渗透到 Domain、Store 或具体页面。未启用网络扩展时，应用保持现有本地行为。
