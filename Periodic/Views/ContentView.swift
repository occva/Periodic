import SwiftUI

struct ContentView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppWindowRouter.self) private var windowRouter
    @Environment(\.scenePhase) private var scenePhase
    @SceneStorage("window.instanceID") private var windowIDText = UUID().uuidString
    @SceneStorage("window.destination") private var destinationID = AppDestination.dashboard.rawValue
    @SceneStorage("window.sidebarVisible") private var sidebarVisible = true
    @State private var session = WindowSession(
        timelineRange: AppPreferenceValues.defaultTimelineRange
    )
    @State private var pendingTemplatePreset: SubscriptionTemplatePreset?
    @State private var pendingWindowRoute: MainWindowRoute?

    private var windowID: UUID {
        UUID(uuidString: windowIDText) ?? UUID()
    }

    private var selection: Binding<AppDestination?> {
        Binding(
            get: { AppDestination(rawValue: destinationID) ?? .dashboard },
            set: { if let destination = $0 { destinationID = destination.rawValue } }
        )
    }

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { sidebarVisible ? .all : .detailOnly },
            set: { sidebarVisible = $0 != .detailOnly }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            SidebarView(selection: selection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            DetailView(destination: selection.wrappedValue ?? .dashboard, session: session)
        }
        .frame(minWidth: 960, minHeight: 640)
        .background {
            WindowRegistrationView(windowID: windowID, router: windowRouter)
                .frame(width: 0, height: 0)
        }
        .focusedSceneValue(
            \.createSubscriptionAction,
            CreateSubscriptionAction {
                session.presentNewSubscription()
            }
        )
        .sheet(
            isPresented: Binding(
                get: { session.isPresentingSubscriptionEditor },
                set: { if !$0 { session.dismissEditor() } }
            ),
            onDismiss: { session.dismissEditor() }
        ) {
            let existing = session.editingSubscription
            SubscriptionEditorView(
                subscription: existing,
                preset: existing == nil ? session.subscriptionEditorPreset : nil
            ) { input, historyPolicy in
                guard let store = services.subscriptionStore else {
                    throw ContentViewError.storeUnavailable
                }
                if let existing {
                    try await store.update(
                        input,
                        expectedRevision: existing.revision,
                        historyPolicy: historyPolicy
                    )
                } else {
                    _ = try await store.create(input)
                }
                services.notifySubscriptionDataChanged()
                await session.reload(using: services)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { session.isPresentingSubscriptionDetail },
                set: { if !$0 { session.dismissDetails() } }
            ),
            onDismiss: { session.dismissDetails() }
        ) {
            if let subscription = session.detailSubscription {
                SubscriptionDetailView(
                    subscription: subscription,
                    onEditSubscription: {
                        session.dismissDetails()
                        Task { @MainActor in
                            await Task.yield()
                            session.presentEditor(for: subscription.id)
                        }
                    },
                    loadPeriods: { id in
                        guard let store = services.subscriptionStore else {
                            throw ContentViewError.storeUnavailable
                        }
                        return try await store.fetchPeriods(for: id)
                    },
                    addPeriod: { input in
                        guard let store = services.subscriptionStore else {
                            throw ContentViewError.storeUnavailable
                        }
                        try await store.addPeriod(input)
                        services.notifySubscriptionDataChanged()
                        await session.reload(using: services)
                    },
                    updatePeriod: { input in
                        guard let store = services.subscriptionStore else {
                            throw ContentViewError.storeUnavailable
                        }
                        try await store.updatePeriod(input)
                        services.notifySubscriptionDataChanged()
                        await session.reload(using: services)
                    },
                    deletePeriod: { input in
                        guard let store = services.subscriptionStore else {
                            throw ContentViewError.storeUnavailable
                        }
                        try await store.deletePeriod(input)
                        services.notifySubscriptionDataChanged()
                        await session.reload(using: services)
                    },
                    confirmAutomaticRenewal: { request in
                        guard let store = services.subscriptionStore else {
                            throw ContentViewError.storeUnavailable
                        }
                        _ = try await store.confirmAutomaticRenewal(request)
                        services.notifySubscriptionDataChanged()
                        await session.reload(using: services)
                    },
                    markAutomaticRenewalNotRenewed: { request in
                        guard let store = services.subscriptionStore else {
                            throw ContentViewError.storeUnavailable
                        }
                        try await store.markAutomaticRenewalNotRenewed(request)
                        services.notifySubscriptionDataChanged()
                        await session.reload(using: services)
                    }
                )
            }
        }
        .sheet(
            isPresented: Binding(
                get: { session.isPresentingTemplateLibrary },
                set: { if !$0 { session.dismissTemplateLibrary() } }
            ),
            onDismiss: {
                session.dismissTemplateLibrary()
                guard let preset = pendingTemplatePreset else { return }
                pendingTemplatePreset = nil
                session.presentNewSubscription(preset: preset)
            }
        ) {
            TemplateLibraryView(
                presentation: .sheet,
                onSelectPreset: { preset in
                    pendingTemplatePreset = preset
                    session.dismissTemplateLibrary()
                }
            ) { input in
                guard let store = services.subscriptionStore else {
                    throw ContentViewError.storeUnavailable
                }
                _ = try await store.create(input)
                services.notifySubscriptionDataChanged()
                await session.reload(using: services)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { session.isPresentingReminderCenter },
                set: { if !$0 { session.dismissReminderCenter() } }
            ),
            onDismiss: { session.dismissReminderCenter() }
        ) {
            SubscriptionReminderCenterView(
                initialScope: session.reminderCenterScope,
                reminderItems: session.reminderItems,
                referenceDate: session.referenceDate,
                previewRenewal: session.renewalPreview(for:),
                confirmRenewal: { request in
                    guard let store = services.subscriptionStore else {
                        throw ContentViewError.storeUnavailable
                    }
                    _ = try await store.confirmAutomaticRenewal(request)
                    services.notifySubscriptionDataChanged()
                    await session.reload(using: services)
                },
                markNotRenewed: { request in
                    guard let store = services.subscriptionStore else {
                        throw ContentViewError.storeUnavailable
                    }
                    try await store.markAutomaticRenewalNotRenewed(request)
                    services.notifySubscriptionDataChanged()
                    await session.reload(using: services)
                },
                onDetails: { id in
                    session.dismissReminderCenter()
                    Task { @MainActor in
                        await Task.yield()
                        session.presentDetails(for: id)
                    }
                }
            )
        }
        .task {
            do {
                try await services.prepareStoredSubscriptionData()
                try await services.prepareDevelopmentDataIfRequested()
            } catch {
                session.loadError = PresentedError(error, title: "无法准备订阅数据")
            }
            await session.reload(using: services)
            applyPendingWindowRoute()
            receiveNotificationSelection()
        }
        .onChange(of: services.subscriptionDataVersion) { _, _ in
            Task { @MainActor in
                await session.reload(using: services)
                applyPendingWindowRoute()
            }
        }
        .onChange(of: windowRouter.routeRevision) { _, _ in
            receiveWindowRoute()
        }
        .onChange(of: services.subscriptionNotifications.selection.subscriptionID) { _, _ in
            receiveNotificationSelection()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { @MainActor in
                    await session.reload(using: services)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            Task { @MainActor in
                await session.reload(using: services)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in
            Task { @MainActor in
                await session.reload(using: services)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            Task { @MainActor in
                await session.reload(using: services)
            }
        }
        .errorAlert(
            Binding(
                get: { session.loadError },
                set: { session.loadError = $0 }
            )
        )
        .onAppear {
            AppLog.lifecycle.info("Main window appeared")
            receiveWindowRoute()
        }
    }

    private func receiveWindowRoute() {
        guard let route = windowRouter.consumeRoute(for: windowID) else { return }
        pendingWindowRoute = route
        applyPendingWindowRoute()
    }

    private func receiveNotificationSelection() {
        guard let id = services.subscriptionNotifications.selection.consume() else { return }
        pendingWindowRoute = .subscriptionDetails(id)
        applyPendingWindowRoute()
    }

    private func applyPendingWindowRoute() {
        guard let route = pendingWindowRoute else { return }
        switch route {
        case .dashboard(let dueHorizon):
            destinationID = AppDestination.dashboard.rawValue
            if let dueHorizon {
                session.dueHorizon = dueHorizon
            }
            pendingWindowRoute = nil
        case .overview:
            destinationID = AppDestination.overview.rawValue
            pendingWindowRoute = nil
        case .subscriptionDetails(let id):
            destinationID = AppDestination.overview.rawValue
            if session.tryPresentDetails(for: id) {
                pendingWindowRoute = nil
            } else if session.hasLoadedSubscriptions {
                pendingWindowRoute = nil
                session.loadError = PresentedError(
                    ContentViewError.subscriptionNotFound,
                    title: "无法打开订阅"
                )
            }
        case .newSubscription:
            destinationID = AppDestination.dashboard.rawValue
            session.presentNewSubscription()
            pendingWindowRoute = nil
        case .templateLibrary:
            destinationID = AppDestination.templates.rawValue
            pendingWindowRoute = nil
        }
    }
}

private enum ContentViewError: LocalizedError {
    case storeUnavailable
    case subscriptionNotFound

    var errorDescription: String? {
        switch self {
        case .storeUnavailable:
            "订阅数据库尚未就绪。"
        case .subscriptionNotFound:
            "该订阅已被删除或不再存在。菜单栏将在下次更新后移除它。"
        }
    }
}

#Preview {
    ContentView()
        .environment(AppServices())
        .environment(AppWindowRouter())
}
