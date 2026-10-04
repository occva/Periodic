import CoreData
import Foundation
import SwiftData
import Testing
@testable import Periodic

struct SubscriptionMaintenanceTests {
    @Test func customReminderScheduleUsesCalendarDaysAndSelectedTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let expiry = try #require(LocalDate(year: 2026, month: 10, day: 1))
        let reminderDate = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 9,
                    day: 27,
                    hour: 14,
                    minute: 30
                )
            )
        )

        let schedule = try #require(
            SubscriptionNotificationSchedule(
                reminderDate: reminderDate,
                expiry: expiry,
                calendar: calendar
            )
        )

        #expect(SubscriptionNotificationSchedule.default.advanceDays == [1])
        #expect(schedule.advanceDays == [4])
        #expect(schedule.minuteOfDay == 14 * 60 + 30)
        #expect(
            schedule.reminderDate(
                relativeTo: expiry.date(calendar: calendar),
                calendar: calendar
            ) == reminderDate
        )
        let afterExpiry = try #require(expiry.addingDays(1))
        #expect(
            SubscriptionNotificationSchedule(
                reminderDate: afterExpiry.date(calendar: calendar),
                expiry: expiry,
                calendar: calendar
            ) == nil
        )
    }

    @Test func untouchedEditorSchedulePreservesCompatibleMultipleReminderTimes() {
        let importedSchedule = SubscriptionNotificationSchedule(
            advanceDays: [7, 3, 1, 0],
            minuteOfDay: SubscriptionNotificationSchedule.defaultMinuteOfDay
        )
        let displayedCustomValue = SubscriptionNotificationSchedule(
            advanceDays: [7],
            minuteOfDay: SubscriptionNotificationSchedule.defaultMinuteOfDay
        )

        #expect(
            SubscriptionNotificationSchedule.resolvingEditorSchedule(
                initial: importedSchedule,
                edited: displayedCustomValue,
                isModified: false
            ) == importedSchedule
        )
        #expect(
            SubscriptionNotificationSchedule.resolvingEditorSchedule(
                initial: importedSchedule,
                edited: displayedCustomValue,
                isModified: true
            ) == displayedCustomValue
        )
    }

    @Test func untouchedCustomReminderFollowsChangedExpiry() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let originalExpiry = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 28))
        )
        let changedExpiry = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 8))
        )
        let timedExpiry = try #require(
            calendar.date(
                bySettingHour: 14,
                minute: 30,
                second: 0,
                of: originalExpiry
            )
        )
        let originalReminder = try #require(
            calendar.date(byAdding: .day, value: -4, to: timedExpiry)
        )

        let adjustedReminder = SubscriptionNotificationSchedule.adjustedCustomReminderDate(
            current: originalReminder,
            previousExpiryDate: originalExpiry,
            expiryDate: changedExpiry,
            followsExpiry: true,
            calendar: calendar
        )

        #expect(
            adjustedReminder == SubscriptionNotificationSchedule(
                reminderDate: originalReminder,
                expiry: LocalDate(originalExpiry, calendar: calendar),
                calendar: calendar
            )?.reminderDate(relativeTo: changedExpiry, calendar: calendar)
        )
        #expect(
            calendar.dateComponents([.hour, .minute], from: adjustedReminder)
                == DateComponents(hour: 14, minute: 30)
        )
        #expect(
            SubscriptionNotificationSchedule.adjustedCustomReminderDate(
                current: originalReminder,
                previousExpiryDate: originalExpiry,
                expiryDate: changedExpiry,
                followsExpiry: false,
                calendar: calendar
            ) == originalReminder
        )
    }

    @Test func overviewColumnPreferencesDistinguishDefaultsFromNoOptionalColumns() {
        #expect(
            OverviewColumnPreferences.visibleColumns(from: "")
                == Set(OverviewTextColumn.allCases)
        )
        let storedEmptyValue = OverviewColumnPreferences.storedValue(for: [])
        #expect(!storedEmptyValue.isEmpty)
        #expect(OverviewColumnPreferences.visibleColumns(from: storedEmptyValue).isEmpty)
    }

    @Test func overviewSelectionDropsItemsOutsideCurrentResults() throws {
        let expiry = try LocalDate(iso8601Text: "2026-12-31")
        let visible = try makeDTO(name: "Visible", expiry: expiry)
        let hidden = try makeDTO(name: "Hidden", expiry: expiry)

        #expect(
            OverviewSelection.visibleIDs(
                in: [visible.id, hidden.id],
                items: [SubscriptionListItem(dto: visible)]
            ) == [visible.id]
        )
    }

    @Test func overviewAmountSortUsesCurrentPriceWithoutAnnualizing() throws {
        let expiry = try LocalDate(iso8601Text: "2026-12-31")
        let monthly = try makeDTO(
            name: "Monthly",
            expiry: expiry,
            cycleMonths: 1,
            amountMinor: 10_000
        )
        let annual = try makeDTO(
            name: "Annual",
            expiry: expiry,
            cycleMonths: 12,
            amountMinor: 12_000
        )

        let names = OverviewSortOption.amountAscending.sorted(
            [SubscriptionListItem(dto: annual), SubscriptionListItem(dto: monthly)],
            referenceDate: expiry
        ).map(\.name)

        #expect(names == ["Monthly", "Annual"])
    }

    @Test func overviewRemainingDaysSupportsBothDirections() throws {
        let referenceDate = try LocalDate(iso8601Text: "2026-09-28")
        let earlier = try makeDTO(
            name: "Earlier",
            expiry: try LocalDate(iso8601Text: "2026-09-29")
        )
        let later = try makeDTO(
            name: "Later",
            expiry: try LocalDate(iso8601Text: "2026-10-08")
        )
        let items = [SubscriptionListItem(dto: later), SubscriptionListItem(dto: earlier)]

        #expect(
            OverviewSortOption.remainingDaysAscending.sorted(
                items,
                referenceDate: referenceDate
            ).map(\.name) == ["Earlier", "Later"]
        )
        #expect(
            OverviewSortOption.remainingDaysDescending.sorted(
                items,
                referenceDate: referenceDate
            ).map(\.name) == ["Later", "Earlier"]
        )
    }

    @Test func appSchemaHasExplicitVersionsAndMigration() {
        let schema = Schema(versionedSchema: AppSchemaV9.self)

        #expect(schema.version == Schema.Version(9, 0, 0))
        #expect(schema.entities.count == AppSchemaV9.models.count)
        #expect(AppSchemaMigrationPlan.schemas.count == 9)
        #expect(AppSchemaMigrationPlan.stages.count == 8)
    }

    @MainActor
    @Test func versionedSchemaReopensStoreCreatedWithEquivalentLegacySchema() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let storeURL = directory.appending(path: "Periodic.store")
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = try makeInput(name: "Legacy")

        do {
            let legacySchema = Schema([
                AppSchemaV1.SubscriptionRecord.self,
                AppSchemaV1.SubscriptionPeriodRecord.self,
                AppSchemaV1.ServiceTemplateRecord.self,
                AppSchemaV1.TemplateCategoryRecord.self,
                AppSchemaV1.BuiltinTemplateCategoryAssignmentRecord.self,
            ])
            let container = try PersistenceController(storeURL: storeURL).makeContainer(
                schema: legacySchema
            )
            let context = ModelContext(container)
            context.insert(AppSchemaV1.SubscriptionRecord(input: input))
            try context.save()
        }

        let versionedSchema = Schema(versionedSchema: AppSchemaV9.self)
        let reopenedContainer = try PersistenceController(storeURL: storeURL).makeContainer(
            schema: versionedSchema,
            migrationPlan: AppSchemaMigrationPlan.self
        )
        let records = try ModelContext(reopenedContainer).fetch(
            FetchDescriptor<SubscriptionRecord>()
        )

        #expect(records.map(\.id) == [input.id])
        #expect(records.first?.reminderAdvanceDaysRaw == "1")
        #expect(records.first?.reminderMinuteOfDay == 9 * 60)
    }

    @MainActor
    @Test func versionEightStoreMigratesWithoutChangingPublishedSchema() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let storeURL = directory.appending(path: "Periodic.store")
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = try makeInput(name: "V8 Subscription")
        let syncRecordID = input.id.uuidString

        do {
            let container = try PersistenceController(storeURL: storeURL).makeContainer(
                schema: Schema(versionedSchema: AppSchemaV8.self)
            )
            let context = ModelContext(container)
            context.insert(SubscriptionRecord(input: input))
            context.insert(
                AppSchemaV8.SyncRecordStateRecord(
                    recordType: .subscription,
                    recordID: syncRecordID,
                    revision: 1,
                    modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    modifiedByDeviceID: UUID(),
                    isDeleted: false,
                    deletedAt: nil
                )
            )
            try context.save()
        }

        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: storeURL
        )
        #expect(
            metadata["NSStoreModelVersionChecksumKey"] as? String
                == "EWK1jZXboGvf1odtPGpEany6A+RVDlwdnHheieCbGUM="
        )

        let container = try PersistenceController(storeURL: storeURL).makeContainer(
            schema: Schema(versionedSchema: AppSchemaV9.self),
            migrationPlan: AppSchemaMigrationPlan.self
        )
        let context = ModelContext(container)
        let subscriptions = try context.fetch(FetchDescriptor<SubscriptionRecord>())
        let syncStates = try context.fetch(FetchDescriptor<SyncRecordStateRecord>())

        #expect(subscriptions.map(\.id) == [input.id])
        #expect(syncStates.map(\.recordID) == [syncRecordID])
        #expect(syncStates.first?.serverRecordData == nil)
    }

    @MainActor
    @Test func versionThreePaymentMigratesWithNoScreenshotAttachment() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let storeURL = directory.appending(path: "Periodic.store")
        defer { try? FileManager.default.removeItem(at: directory) }
        let subscriptionInput = try makeInput(name: "V3 Payment")
        let paymentID = UUID()

        do {
            let container = try PersistenceController(storeURL: storeURL).makeContainer(
                schema: Schema(versionedSchema: AppSchemaV3.self)
            )
            let context = ModelContext(container)
            context.insert(SubscriptionRecord(input: subscriptionInput))
            context.insert(
                SubscriptionPaymentRecord(
                    input: SubscriptionPaymentCreateInput(
                        id: paymentID,
                        subscriptionID: subscriptionInput.id,
                        periodRecordID: nil,
                        kind: .manual,
                        paymentDate: .today,
                        money: subscriptionInput.money,
                        periodStart: nil,
                        periodEnd: nil,
                        note: "V3",
                        attachmentReferences: []
                    )
                )
            )
            try context.save()
        }

        let container = try PersistenceController(storeURL: storeURL).makeContainer(
            schema: Schema(versionedSchema: AppSchemaV9.self),
            migrationPlan: AppSchemaMigrationPlan.self
        )
        let context = ModelContext(container)
        #expect(
            try context.fetch(FetchDescriptor<SubscriptionPaymentRecord>()).map(\.id)
                == [paymentID]
        )
        #expect(
            try context.fetch(FetchDescriptor<SubscriptionPaymentAttachmentRecord>())
                .isEmpty
        )
        #expect(
            try context.fetch(FetchDescriptor<SubscriptionPaymentAttachmentItemRecord>())
                .isEmpty
        )
    }

    @MainActor
    @Test func versionFourSingleScreenshotMigratesToOrderedAttachmentItem() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let storeURL = directory.appending(path: "Periodic.store")
        defer { try? FileManager.default.removeItem(at: directory) }
        let subscriptionInput = try makeInput(name: "V4 Screenshot")
        let paymentID = UUID()
        let reference = PaymentAttachmentReference.make(
            contentHash: String(repeating: "a", count: 64)
        )

        do {
            let container = try PersistenceController(storeURL: storeURL).makeContainer(
                schema: Schema(versionedSchema: AppSchemaV4.self)
            )
            let context = ModelContext(container)
            context.insert(SubscriptionRecord(input: subscriptionInput))
            context.insert(
                SubscriptionPaymentRecord(
                    input: SubscriptionPaymentCreateInput(
                        id: paymentID,
                        subscriptionID: subscriptionInput.id,
                        periodRecordID: nil,
                        kind: .manual,
                        paymentDate: .today,
                        money: subscriptionInput.money,
                        periodStart: nil,
                        periodEnd: nil,
                        note: "V4",
                        attachmentReferences: []
                    )
                )
            )
            context.insert(
                SubscriptionPaymentAttachmentRecord(
                    paymentID: paymentID,
                    reference: reference
                )
            )
            try context.save()
        }

        let container = try PersistenceController(storeURL: storeURL).makeContainer(
            schema: Schema(versionedSchema: AppSchemaV9.self),
            migrationPlan: AppSchemaMigrationPlan.self
        )
        let context = ModelContext(container)
        let migratedItems = try context.fetch(
            FetchDescriptor<SubscriptionPaymentAttachmentItemRecord>()
        )

        #expect(
            try context.fetch(FetchDescriptor<SubscriptionPaymentAttachmentRecord>())
                .isEmpty
        )
        #expect(migratedItems.map(\.paymentID) == [paymentID])
        #expect(migratedItems.map(\.reference) == [reference])
        #expect(migratedItems.map(\.sortOrder) == [0])
        #expect(
            try await SubscriptionStore(modelContainer: container)
                .fetchPayments(for: subscriptionInput.id)
                .first?
                .attachmentReferences == [reference]
        )
    }

    @MainActor
    @Test func copiedSubscriptionKeepsFieldsWithoutCopyingPeriodHistory() async throws {
        let store = try makeStore()
        let original = try makeInput(name: "Original")
        _ = try await store.create(original)

        let copy = SubscriptionCreateInput(
            id: UUID(),
            name: "Original 副本",
            symbolName: original.symbolName,
            iconResourceName: original.iconResourceName,
            iconURLString: original.iconURLString,
            category: original.category,
            managementState: original.managementState,
            billingKind: original.billingKind,
            periodStart: original.periodStart,
            expiry: original.expiry,
            cycleMonths: original.cycleMonths,
            money: original.money,
            note: original.note,
            reminderEnabled: original.reminderEnabled,
            reminderAdvanceDays: original.reminderAdvanceDays,
            reminderMinuteOfDay: original.reminderMinuteOfDay
        )
        _ = try await store.create(copy, historyPolicy: .skipInitialPeriod)

        #expect(try await store.fetchAll().map(\.name) == ["Original", "Original 副本"])
        #expect(try await store.fetchPeriods(for: original.id).count == 1)
        #expect(try await store.fetchPeriods(for: copy.id).isEmpty)
    }

    @MainActor
    @Test func lifetimeBackfillRunsOnlyOnceSoLaterCopiesKeepEmptyHistory() async throws {
        let suiteName = "LifetimePeriodBackfillTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let services = AppServices(
            persistence: PersistenceController(
                storeURL: directory.appending(path: "Periodic.store")
            ),
            inMemory: false,
            defaults: defaults
        )
        let store = try #require(services.subscriptionStore)
        let legacyLifetime = makeLifetimeInput(name: "Legacy Lifetime")
        _ = try await store.create(legacyLifetime, historyPolicy: .skipInitialPeriod)

        try await services.prepareStoredSubscriptionData()

        let datasetID = AppPreferenceValues.datasetID(in: defaults)
        #expect(defaults.bool(forKey: PreferenceKey.lifetimePeriodBackfillCompleted(
            datasetID: datasetID
        )))
        #expect(defaults.object(forKey: PreferenceKey.completedLifetimePeriodBackfill) == nil)
        #expect(try await store.fetchPeriods(for: legacyLifetime.id).count == 1)

        let copiedLifetime = makeLifetimeInput(name: "Lifetime Copy")
        _ = try await store.create(copiedLifetime, historyPolicy: .skipInitialPeriod)
        try await services.prepareStoredSubscriptionData()

        #expect(try await store.fetchPeriods(for: copiedLifetime.id).isEmpty)
    }

    @MainActor
    @Test func inMemoryStoreDoesNotRunOrMarkPersistentLifetimeBackfill() async throws {
        let suiteName = "InMemoryLifetimePeriodBackfillTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let datasetID = UUID()
        defaults.set(datasetID.uuidString, forKey: PreferenceKey.datasetID)
        let services = AppServices(inMemory: true, defaults: defaults)
        let store = try #require(services.subscriptionStore)
        let lifetime = makeLifetimeInput(name: "Sample Lifetime")
        _ = try await store.create(lifetime, historyPolicy: .skipInitialPeriod)

        try await services.prepareStoredSubscriptionData()

        #expect(try await store.fetchPeriods(for: lifetime.id).isEmpty)
        #expect(!defaults.bool(forKey: PreferenceKey.lifetimePeriodBackfillCompleted(
            datasetID: datasetID
        )))
        #expect(defaults.object(forKey: PreferenceKey.completedLifetimePeriodBackfill) == nil)
    }

    @MainActor
    @Test func deletionPreviewAndCommitCascadePeriodRecords() async throws {
        let store = try makeStore()
        let first = try makeInput(name: "First")
        let second = try makeInput(name: "Second")
        _ = try await store.create(first)
        _ = try await store.create(second)

        let preview = try await store.previewDeletion([
            SubscriptionMutationTarget(id: first.id, expectedRevision: 1),
            SubscriptionMutationTarget(id: second.id, expectedRevision: 1),
        ])
        #expect(preview.subscriptionCount == 2)
        #expect(preview.periodCount == 2)
        #expect(preview.paymentCount == 0)

        let result = try await store.delete(preview)
        #expect(result.deletedSubscriptionCount == 2)
        #expect(result.deletedPeriodCount == 2)
        #expect(result.deletedPaymentCount == 0)
        #expect(try await store.fetchAll().isEmpty)
    }

    @MainActor
    @Test func staleDeletionPreviewDoesNotDeleteUpdatedSubscription() async throws {
        let store = try makeStore()
        let input = try makeInput(name: "Protected")
        _ = try await store.create(input)
        let preview = try await store.previewDeletion([
            SubscriptionMutationTarget(id: input.id, expectedRevision: 1)
        ])
        try await store.setManagementState(
            .inactive,
            for: [SubscriptionMutationTarget(id: input.id, expectedRevision: 1)]
        )

        do {
            _ = try await store.delete(preview)
            Issue.record("更新后的订阅不应被旧删除预览删除。")
        } catch SubscriptionStore.StoreError.revisionConflict {
            // Expected.
        }
        #expect(try await store.fetchAll().count == 1)
    }

    @Test func notificationPlanUsesEachSubscriptionsAdvanceDaysAndLocalTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let referenceDate = try LocalDate(iso8601Text: "2026-09-24")
        let expiry = try LocalDate(iso8601Text: "2026-10-01")
        let now = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 8))
        )
        let subscription = try makeDTO(
            name: "Reminder",
            expiry: expiry,
            reminderAdvanceDays: [7, 1, 1, 0],
            reminderMinuteOfDay: 14 * 60 + 30
        )
        let secondSubscription = try makeDTO(
            name: "Second Reminder",
            expiry: expiry,
            reminderAdvanceDays: [3],
            reminderMinuteOfDay: 16 * 60 + 45
        )

        let plans = SubscriptionNotificationPlan.plans(
            subscriptions: [subscription, secondSubscription],
            referenceDate: referenceDate,
            calendar: calendar,
            now: now
        )

        let firstPlans = plans.filter { $0.subscriptionID == subscription.id }
        let secondPlans = plans.filter { $0.subscriptionID == secondSubscription.id }
        #expect(firstPlans.map(\.advanceDays) == [7, 1, 0])
        #expect(firstPlans.allSatisfy { $0.deliveryComponents.hour == 14 })
        #expect(firstPlans.allSatisfy { $0.deliveryComponents.minute == 30 })
        #expect(secondPlans.map(\.advanceDays) == [3])
        #expect(secondPlans.allSatisfy { $0.deliveryComponents.hour == 16 })
        #expect(secondPlans.allSatisfy { $0.deliveryComponents.minute == 45 })
        #expect(Set(plans.map(\.identifier)).count == 4)
        let disabled = try makeDTO(
            name: "Disabled",
            expiry: expiry,
            reminderEnabled: false
        )
        #expect(SubscriptionNotificationPlan.plans(
            subscriptions: [disabled],
            referenceDate: referenceDate
        ).isEmpty)
    }

    @Test func notificationFingerprintChangesWithVisibleContentAndDeliveryTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let referenceDate = try LocalDate(iso8601Text: "2026-09-24")
        let expiry = try LocalDate(iso8601Text: "2026-10-01")
        let now = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 8))
        )
        let subscriptionID = UUID()
        let original = try makeDTO(id: subscriptionID, name: "Original", expiry: expiry)
        let renamed = try makeDTO(id: subscriptionID, name: "Renamed", expiry: expiry)
        let rescheduled = try makeDTO(
            id: subscriptionID,
            name: "Original",
            expiry: expiry,
            reminderMinuteOfDay: 14 * 60
        )
        let plan: (SubscriptionDTO) -> SubscriptionNotificationPlan? = { subscription in
            SubscriptionNotificationPlan.plans(
                subscriptions: [subscription],
                referenceDate: referenceDate,
                calendar: calendar,
                now: now
            ).first
        }

        let originalPlan = try #require(plan(original))
        let renamedPlan = try #require(plan(renamed))
        let rescheduledPlan = try #require(plan(rescheduled))

        #expect(originalPlan.identifier == renamedPlan.identifier)
        #expect(originalPlan.identifier == rescheduledPlan.identifier)
        #expect(originalPlan.submissionFingerprint == renamedPlan.submissionFingerprint)
        #expect(originalPlan.requestFingerprint != renamedPlan.requestFingerprint)
        #expect(originalPlan.submissionFingerprint != rescheduledPlan.submissionFingerprint)
    }

    @Test func notificationFingerprintChangesWithTimeZone() throws {
        var shanghai = Calendar(identifier: .gregorian)
        shanghai.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let referenceDate = try LocalDate(iso8601Text: "2026-09-24")
        let expiry = try LocalDate(iso8601Text: "2026-10-01")
        let subscription = try makeDTO(name: "Reminder", expiry: expiry)

        let shanghaiPlan = try #require(
            SubscriptionNotificationPlan.plans(
                subscriptions: [subscription],
                referenceDate: referenceDate,
                calendar: shanghai,
                now: .distantPast
            ).first
        )
        let losAngelesPlan = try #require(
            SubscriptionNotificationPlan.plans(
                subscriptions: [subscription],
                referenceDate: referenceDate,
                calendar: losAngeles,
                now: .distantPast
            ).first
        )

        #expect(shanghaiPlan.submissionFingerprint != losAngelesPlan.submissionFingerprint)
        #expect(shanghaiPlan.requestFingerprint != losAngelesPlan.requestFingerprint)
    }

    @MainActor
    private func makeStore() throws -> SubscriptionStore {
        let container = try PersistenceController().makeContainer(
            schema: Schema([
                SubscriptionSharingRecord.self,
                SubscriptionRecord.self,
                SubscriptionPeriodRecord.self,
                SubscriptionPaymentRecord.self,
                SubscriptionPaymentAttachmentRecord.self,
                SubscriptionPaymentAttachmentItemRecord.self,
                ServiceTemplateRecord.self,
            ]),
            inMemory: true
        )
        return SubscriptionStore(modelContainer: container)
    }

    private func makeInput(name: String) throws -> SubscriptionCreateInput {
        SubscriptionCreateInput(
            id: UUID(),
            name: name,
            symbolName: "calendar",
            iconResourceName: nil,
            iconURLString: nil,
            category: .tools,
            managementState: .active,
            billingKind: .recurring,
            periodStart: try LocalDate(iso8601Text: "2026-01-01"),
            expiry: try LocalDate(iso8601Text: "2026-12-31"),
            cycleMonths: 12,
            money: Money(minorUnits: 1_200, currency: .cny),
            note: "note",
            reminderEnabled: true
        )
    }

    private func makeLifetimeInput(name: String) -> SubscriptionCreateInput {
        SubscriptionCreateInput(
            id: UUID(),
            name: name,
            symbolName: "infinity",
            iconResourceName: nil,
            iconURLString: nil,
            category: .tools,
            managementState: .active,
            billingKind: .lifetime,
            periodStart: nil,
            expiry: nil,
            cycleMonths: nil,
            money: Money(minorUnits: 12_000, currency: .cny),
            note: "",
            reminderEnabled: false
        )
    }

    private func makeDTO(
        id: UUID = UUID(),
        name: String,
        expiry: LocalDate,
        reminderEnabled: Bool = true,
        reminderAdvanceDays: [Int] = SubscriptionNotificationSchedule.defaultAdvanceDays,
        reminderMinuteOfDay: Int = SubscriptionNotificationSchedule.defaultMinuteOfDay,
        cycleMonths: Int = 1,
        amountMinor: Int64 = 100
    ) throws -> SubscriptionDTO {
        SubscriptionDTO(
            id: id,
            name: name,
            symbolName: "bell",
            iconResourceName: nil,
            iconURLString: nil,
            category: .tools,
            managementState: .active,
            billingKind: .recurring,
            periodStart: LocalDate(dayNumber: expiry.dayNumber - 29),
            expiry: expiry,
            cycleMonths: cycleMonths,
            money: Money(minorUnits: amountMinor, currency: .cny),
            note: "",
            reminderEnabled: reminderEnabled,
            reminderAdvanceDays: reminderAdvanceDays,
            reminderMinuteOfDay: reminderMinuteOfDay,
            revision: 1,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
