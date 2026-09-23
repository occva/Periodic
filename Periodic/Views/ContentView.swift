import SwiftUI

struct ContentView: View {
    @Environment(AppServices.self) private var services
    @SceneStorage("window.destination") private var destinationID = AppDestination.dashboard.rawValue
    @SceneStorage("window.sidebarVisible") private var sidebarVisible = true
    @State private var session = WindowSession()
    @State private var pendingTemplatePreset: SubscriptionTemplatePreset?

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
            ) { input in
                guard let store = services.subscriptionStore else {
                    throw ContentViewError.storeUnavailable
                }
                if let existing {
                    try await store.update(input, expectedRevision: existing.revision)
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
        .task {
            do {
                try await services.prepareStoredSubscriptionData()
                try await services.prepareDevelopmentDataIfRequested()
            } catch {
                session.loadError = PresentedError(error, title: "无法准备订阅数据")
            }
            await session.reload(using: services)
        }
        .onChange(of: services.subscriptionDataVersion) { _, _ in
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
        }
    }
}

private enum ContentViewError: LocalizedError {
    case storeUnavailable

    var errorDescription: String? { "订阅数据库尚未就绪。" }
}

#Preview {
    ContentView()
        .environment(AppServices())
}
