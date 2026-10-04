import Foundation
import SwiftData

@ModelActor
actor SyncRemoteChangeApplier {
    enum ApplyError: LocalizedError, Equatable {
        case invalidStoredValue(String)
        case missingParentSubscription
        case missingReferencedRecord(String)
        case dependentRecordsRemain(String)
        case invalidMutationChain
        case revisionOverflow
        case untrackedLocalRecord
        case conflictNotFound
        case conflictAlreadyResolved
        case unsupportedConflictResolution

        var errorDescription: String? {
            switch self {
            case .invalidStoredValue(let field):
                "同步数据的 \(field) 字段无法识别。"
            case .missingParentSubscription:
                "周期记录对应的订阅尚未下载完成。"
            case .missingReferencedRecord(let relationship):
                "同步数据依赖的 \(relationship) 尚未下载完成。"
            case .dependentRecordsRemain(let relationship):
                "同步数据仍被 \(relationship) 引用，已等待关联变更。"
            case .invalidMutationChain:
                "本地待上传变更的版本链不连续。"
            case .revisionOverflow:
                "同步记录版本已达到上限。"
            case .untrackedLocalRecord:
                "本地记录尚未建立同步状态，已停止远端覆盖。"
            case .conflictNotFound:
                "这条同步冲突已不存在。"
            case .conflictAlreadyResolved:
                "这条同步冲突已经处理。"
            case .unsupportedConflictResolution:
                "删除与修改冲突不能直接覆盖，请先保留需要的数据副本。"
            }
        }
    }

    private enum ApplicationResult {
        case applied(
            businessChanged: Bool,
            acceptedRemoteAsset: SyncRecordPayloadDecoder.IconAssetPayload?
        )
        case conflicted
        case deferred
    }

    private var datasetAccess = DatasetAccessCoordinator()
    private var assetRepository: CloudAssetRepository?

    init(
        modelContainer: ModelContainer,
        datasetAccess: DatasetAccessCoordinator = DatasetAccessCoordinator(),
        assetRepository: CloudAssetRepository? = nil
    ) {
        self.modelContainer = modelContainer
        modelExecutor = DefaultSerialModelExecutor(
            modelContext: ModelContext(modelContainer)
        )
        self.datasetAccess = datasetAccess
        self.assetRepository = assetRepository
    }

    func resolveConflict(
        _ conflictID: UUID,
        resolution: CloudSyncConflictResolution,
        now: Date = Date()
    ) async throws {
        let lease = try await datasetAccess.acquireWrite()
        var materializedAsset:
            CloudAssetRepository.MaterializedDownload?
        do {
            let conflict = try fetchConflict(conflictID)
            guard conflict.stateRaw
                == SyncConflictState.unresolved.rawValue else {
                throw ApplyError.conflictAlreadyResolved
            }
            let payload = try JSONDecoder().decode(
                SyncConflictPayload.self,
                from: conflict.payloadData
            )
            guard !payload.localSnapshot.isDeleted,
                  !payload.remoteEnvelope.isDeleted else {
                throw ApplyError.unsupportedConflictResolution
            }
            let inbox = try fetchRemoteChange(
                conflict.sourceChangeID
            )
            guard let state = try fetchState(
                recordType: payload.remoteEnvelope.recordType,
                recordID: payload.remoteEnvelope.recordID
            ) else {
                throw ApplyError.invalidStoredValue("conflict.state")
            }
            let localMutations = try activeMutations(
                recordType: payload.remoteEnvelope.recordType,
                recordID: payload.remoteEnvelope.recordID
            )

            switch resolution {
            case .keepLocal:
                let currentSnapshot = try await snapshot(for: state)
                guard !currentSnapshot.isDeleted else {
                    throw ApplyError.unsupportedConflictResolution
                }
                localMutations.forEach(modelContext.delete)
                let highestRevision = max(
                    currentSnapshot.revision,
                    payload.remoteEnvelope.revision
                )
                let targetRevision = try nextRevision(
                    highestRevision
                )
                state.revision = targetRevision
                state.modifiedAt = now
                state.modifiedByDeviceID = datasetAccess.deviceID
                state.isDeleted = false
                state.deletedAt = nil
                state.serverRecordData =
                    conflict.remoteServerRecordData
                try SyncMutationJournal.recordRebasedUpdate(
                    in: modelContext,
                    deviceID: datasetAccess.deviceID,
                    recordType: currentSnapshot.recordType,
                    recordID: currentSnapshot.recordID,
                    baseRevision: payload.remoteEnvelope.revision,
                    targetRevision: targetRevision,
                    fieldValues: currentSnapshot.fieldValues,
                    relationshipChanges:
                        payload.localChange.relationshipChanges,
                    now: now
                )
            case .useRemote:
                let businessChanged = try await applyRemoteBusiness(
                    payload.remoteEnvelope
                )
                if payload.remoteEnvelope.recordType == .iconAsset {
                    guard let assetRepository else {
                        throw ApplyError.invalidStoredValue("iconAsset")
                    }
                    let asset = try SyncRecordPayloadDecoder.iconAsset(
                        recordID: payload.remoteEnvelope.recordID,
                        fieldValues:
                            payload.remoteEnvelope.fieldValues
                    )
                    materializedAsset = try await assetRepository
                        .commitStagedDownload(
                            reference: asset.reference,
                            metadata: asset.metadata
                        )
                }
                localMutations.forEach(modelContext.delete)
                apply(
                    payload.remoteEnvelope,
                    serverRecordData:
                        conflict.remoteServerRecordData,
                    to: state
                )
                if businessChanged {
                    try DatasetMetadata.advanceRevision(
                        in: modelContext,
                        descriptor: datasetAccess.descriptor,
                        now: now
                    )
                }
            }

            conflict.stateRaw = SyncConflictState.resolved.rawValue
            conflict.updatedAt = now
            inbox.stateRaw = SyncRemoteChangeState.applied.rawValue
            inbox.failureCode = nil
            inbox.updatedAt = now
            try modelContext.save()
            if let materializedAsset {
                await assetRepository?.finalize(materializedAsset)
            }
            await datasetAccess.releaseWrite(lease)
        } catch {
            modelContext.rollback()
            if let materializedAsset {
                await assetRepository?.rollback(materializedAsset)
            }
            await datasetAccess.releaseWrite(lease)
            throw error
        }
    }

    func applyPending(
        limit: Int = 100,
        now: Date = Date()
    ) async throws -> SyncRemoteApplyReport {
        guard limit > 0 else {
            return SyncRemoteApplyReport(
                appliedCount: 0,
                conflictCount: 0,
                deferredCount: 0,
                failedCount: 0
            )
        }
        let lease = try await datasetAccess.acquireWrite()
        do {
            let pendingRaw = SyncRemoteChangeState.pending.rawValue
            let pendingRecords = try modelContext.fetch(
                FetchDescriptor<SyncRemoteChangeRecord>(
                    predicate: #Predicate { $0.stateRaw == pendingRaw },
                    sortBy: [SortDescriptor(\.receivedAt, order: .forward)]
                )
            )
            .sorted(by: remoteChangeSort)
            .prefix(limit)
            let changeIDs = pendingRecords.map(\.sourceChangeID)
            var appliedCount = 0
            var conflictCount = 0
            var deferredCount = 0
            var failedCount = 0

            for sourceChangeID in changeIDs {
                var materializedAsset: CloudAssetRepository.MaterializedDownload?
                do {
                    let record = try fetchRemoteChange(sourceChangeID)
                    let result = try await apply(record, now: now)
                    switch result {
                    case .applied(
                        let businessChanged,
                        let acceptedRemoteAsset
                    ):
                        if let acceptedRemoteAsset {
                            guard let assetRepository else {
                                throw ApplyError.invalidStoredValue(
                                    "iconAsset"
                                )
                            }
                            materializedAsset = try await assetRepository
                                .commitStagedDownload(
                                    reference: acceptedRemoteAsset.reference,
                                    metadata: acceptedRemoteAsset.metadata
                                )
                        }
                        if businessChanged {
                            try DatasetMetadata.advanceRevision(
                                in: modelContext,
                                descriptor: datasetAccess.descriptor,
                                now: now
                            )
                        }
                        record.stateRaw = SyncRemoteChangeState.applied.rawValue
                        record.failureCode = nil
                        record.updatedAt = now
                        try modelContext.save()
                        if let materializedAsset {
                            await assetRepository?.finalize(materializedAsset)
                        }
                        appliedCount += 1
                    case .conflicted:
                        record.stateRaw = SyncRemoteChangeState.conflicted.rawValue
                        record.failureCode = nil
                        record.updatedAt = now
                        try modelContext.save()
                        conflictCount += 1
                    case .deferred:
                        modelContext.rollback()
                        deferredCount += 1
                    }
                } catch ApplyError.missingParentSubscription,
                        ApplyError.missingReferencedRecord,
                        ApplyError.dependentRecordsRemain {
                    modelContext.rollback()
                    deferredCount += 1
                } catch is CloudImageAssetStager.StagingError,
                        is AppleIconCache.CacheError,
                        is PaymentAttachmentStore.StoreError,
                        is CloudAssetRepository.RepositoryError {
                    modelContext.rollback()
                    if let materializedAsset {
                        await assetRepository?.rollback(materializedAsset)
                    }
                    deferredCount += 1
                } catch {
                    modelContext.rollback()
                    if let materializedAsset {
                        await assetRepository?.rollback(materializedAsset)
                    }
                    let failed = try fetchRemoteChange(sourceChangeID)
                    failed.stateRaw = SyncRemoteChangeState.failed.rawValue
                    failed.failureCode = failureCode(for: error)
                    failed.updatedAt = now
                    try modelContext.save()
                    failedCount += 1
                }
            }
            await datasetAccess.releaseWrite(lease)
            return SyncRemoteApplyReport(
                appliedCount: appliedCount,
                conflictCount: conflictCount,
                deferredCount: deferredCount,
                failedCount: failedCount
            )
        } catch {
            modelContext.rollback()
            await datasetAccess.releaseWrite(lease)
            throw error
        }
    }

    private func apply(
        _ inbox: SyncRemoteChangeRecord,
        now: Date
    ) async throws -> ApplicationResult {
        let envelope = try JSONDecoder().decode(
            CloudRecordEnvelope.self,
            from: inbox.envelopeData
        )
        guard envelope.recordType.rawValue == inbox.recordTypeRaw,
              envelope.recordID == inbox.recordID else {
            throw ApplyError.invalidStoredValue("remoteEnvelope")
        }
        guard supportsApplication(envelope.recordType) else {
            return .deferred
        }

        let state = try fetchState(
            recordType: envelope.recordType,
            recordID: envelope.recordID
        )
        guard let state else {
            if let localPayload = try await existingPayload(
                recordType: envelope.recordType,
                recordID: envelope.recordID
            ) {
                guard !envelope.isDeleted,
                      localPayload == envelope.fieldValues else {
                    throw ApplyError.untrackedLocalRecord
                }
                modelContext.insert(
                    SyncRecordStateRecord(
                        recordType: envelope.recordType,
                        recordID: envelope.recordID,
                        revision: envelope.revision,
                        modifiedAt: envelope.modifiedAt,
                        modifiedByDeviceID: envelope.modifiedByDeviceID,
                        isDeleted: false,
                        deletedAt: nil,
                        serverRecordData: inbox.serverRecordData
                    )
                )
                return accepted(
                    envelope,
                    businessChanged: false
                )
            }
            let businessChanged = try await applyRemoteBusiness(envelope)
            modelContext.insert(
                SyncRecordStateRecord(
                    recordType: envelope.recordType,
                    recordID: envelope.recordID,
                    revision: envelope.revision,
                    modifiedAt: envelope.modifiedAt,
                    modifiedByDeviceID: envelope.modifiedByDeviceID,
                    isDeleted: envelope.isDeleted,
                    deletedAt: envelope.deletedAt,
                    serverRecordData: inbox.serverRecordData
                )
            )
            return accepted(
                envelope,
                businessChanged: businessChanged
            )
        }

        let localSnapshot = try await snapshot(for: state)
        if try hasUnresolvedConflict(
            recordType: envelope.recordType,
            recordID: envelope.recordID
        ) {
            return .deferred
        }
        let localMutations = try activeMutations(
            recordType: envelope.recordType,
            recordID: envelope.recordID
        )
        if localMutations.isEmpty {
            if state.isDeleted, !envelope.isDeleted {
                try persistConflict(
                    sourceChangeID: inbox.sourceChangeID,
                    localSnapshot: localSnapshot,
                    localChange: syntheticChange(from: localSnapshot),
                    remoteEnvelope: envelope,
                    remoteServerRecordData: inbox.serverRecordData,
                    reasons: [.deletionVersusModification],
                    localMutations: [],
                    now: now
                )
                return .conflicted
            }
            if envelope.revision < state.revision {
                return .applied(
                    businessChanged: false,
                    acceptedRemoteAsset: nil
                )
            }
            if envelope.revision == state.revision {
                guard snapshotsMatch(localSnapshot, envelope) else {
                    try persistConflict(
                        sourceChangeID: inbox.sourceChangeID,
                        localSnapshot: localSnapshot,
                        localChange: syntheticChange(from: localSnapshot),
                        remoteEnvelope: envelope,
                        remoteServerRecordData: inbox.serverRecordData,
                        reasons: [
                            .divergentBaseRevision(
                                local: max(localSnapshot.revision - 1, 0),
                                remote: envelope.baseRevision
                            ),
                        ],
                        localMutations: [],
                        now: now
                    )
                    return .conflicted
                }
                state.serverRecordData = inbox.serverRecordData
                return accepted(
                    envelope,
                    businessChanged: false
                )
            }

            let businessChanged = try await applyRemoteBusiness(envelope)
            apply(
                envelope,
                serverRecordData: inbox.serverRecordData,
                to: state
            )
            return accepted(
                envelope,
                businessChanged: businessChanged
            )
        }

        if envelope.revision >= state.revision,
           snapshotsMatch(localSnapshot, envelope) {
            localMutations.forEach(modelContext.delete)
            apply(
                envelope,
                serverRecordData: inbox.serverRecordData,
                to: state
            )
            return accepted(
                envelope,
                businessChanged: false
            )
        }

        let localChange = try localChangeSet(
            snapshot: localSnapshot,
            mutations: localMutations
        )
        switch SyncMergeEngine.merge(
            local: localChange,
            remote: envelope.changeSet
        ) {
        case .conflict(let conflict):
            try persistConflict(
                sourceChangeID: inbox.sourceChangeID,
                localSnapshot: localSnapshot,
                localChange: localChange,
                remoteEnvelope: envelope,
                remoteServerRecordData: inbox.serverRecordData,
                reasons: conflict.reasons,
                localMutations: localMutations,
                now: now
            )
            return .conflicted
        case .merged(let merged):
            if merged.operation == .delete {
                let businessChanged = try await applyRemoteBusiness(envelope)
                localMutations.forEach(modelContext.delete)
                apply(
                    envelope,
                    serverRecordData: inbox.serverRecordData,
                    to: state
                )
                return accepted(
                    envelope,
                    businessChanged: businessChanged
                )
            }

            var mergedValues = envelope.fieldValues
            for field in localChange.changedFields {
                guard let localValue = localSnapshot.fieldValues[field] else {
                    throw ApplyError.invalidStoredValue(field)
                }
                mergedValues[field] = localValue
            }
            let mergedEnvelope = CloudRecordEnvelope(
                recordType: envelope.recordType,
                recordID: envelope.recordID,
                revision: merged.targetRevision,
                modifiedAt: now,
                modifiedByDeviceID: datasetAccess.deviceID,
                isDeleted: false,
                deletedAt: nil,
                fieldValues: mergedValues,
                baseRevision: envelope.revision,
                changedFields: localChange.changedFields,
                relationshipChanges: localChange.relationshipChanges
            )
            let businessChanged = try await applyRemoteBusiness(
                mergedEnvelope
            )
            localMutations.forEach(modelContext.delete)
            apply(
                mergedEnvelope,
                serverRecordData: inbox.serverRecordData,
                to: state
            )
            try SyncMutationJournal.recordRebasedUpdate(
                in: modelContext,
                deviceID: datasetAccess.deviceID,
                recordType: mergedEnvelope.recordType,
                recordID: mergedEnvelope.recordID,
                baseRevision: envelope.revision,
                targetRevision: mergedEnvelope.revision,
                fieldValues: mergedValues.filter {
                    localChange.changedFields.contains($0.key)
                },
                relationshipChanges: localChange.relationshipChanges,
                now: now
            )
            return accepted(
                mergedEnvelope,
                businessChanged: businessChanged
            )
        }
    }

    private func accepted(
        _ envelope: CloudRecordEnvelope,
        businessChanged: Bool
    ) -> ApplicationResult {
        let assetPayload: SyncRecordPayloadDecoder.IconAssetPayload?
        if envelope.recordType == .iconAsset, !envelope.isDeleted {
            assetPayload = try? SyncRecordPayloadDecoder.iconAsset(
                recordID: envelope.recordID,
                fieldValues: envelope.fieldValues
            )
        } else {
            assetPayload = nil
        }
        return .applied(
            businessChanged: businessChanged,
            acceptedRemoteAsset: assetPayload
        )
    }

    private func applyRemoteBusiness(
        _ envelope: CloudRecordEnvelope
    ) async throws -> Bool {
        switch envelope.recordType {
        case .subscription:
            return try await applySubscription(envelope)
        case .subscriptionPeriod:
            return try applyPeriod(envelope)
        case .subscriptionPayment:
            return try await applyPayment(envelope)
        case .serviceTemplate:
            return try await applyTemplate(envelope)
        case .templateCategory:
            return try applyCategory(envelope)
        case .builtinTemplateCategoryAssignment:
            return try applyBuiltinCategoryAssignment(envelope)
        case .iconAsset:
            if envelope.isDeleted {
                guard try !isAssetReferenced(envelope.recordID) else {
                    throw ApplyError.dependentRecordsRemain("业务记录")
                }
                guard let assetRepository else {
                    throw ApplyError.invalidStoredValue("iconAsset")
                }
                try await assetRepository.delete(
                    reference: envelope.recordID
                )
                return false
            }
            _ = try SyncRecordPayloadDecoder.iconAsset(
                recordID: envelope.recordID,
                fieldValues: envelope.fieldValues
            )
            return false
        }
    }

    private func applySubscription(
        _ envelope: CloudRecordEnvelope
    ) async throws -> Bool {
        let id = try uuid(envelope.recordID)
        let existing = try fetchSubscription(id)
        let sharingPersistence = SubscriptionSharingPersistence(
            context: modelContext
        )
        if envelope.isDeleted {
            guard let existing else { return false }
            guard try !hasPeriod(subscriptionID: id),
                  try !hasPayment(subscriptionID: id) else {
                throw ApplyError.dependentRecordsRemain("周期或付款记录")
            }
            try sharingPersistence.remove(subscriptionID: id)
            modelContext.delete(existing)
            return true
        }

        let payload = try SyncRecordPayloadDecoder.subscription(
            recordID: envelope.recordID,
            fieldValues: envelope.fieldValues
        )
        try await requireAsset(
            payload.input.iconURLString,
            relationship: "订阅图标"
        )
        if let existing {
            let current = try SyncRecordPayload.subscription(
                existing,
                sharing: sharingPersistence.plan(subscriptionID: id)
            )
            guard current != envelope.fieldValues else { return false }
            try sharingPersistence.set(
                payload.input.sharing,
                subscriptionID: id,
                myMoney: payload.input.money
            )
            try apply(
                payload,
                modifiedAt: envelope.modifiedAt,
                to: existing
            )
            return true
        }

        try sharingPersistence.set(
            payload.input.sharing,
            subscriptionID: id,
            myMoney: payload.input.money
        )
        let record = SubscriptionRecord(
            input: payload.input,
            now: payload.createdAt
        )
        record.updatedAt = envelope.modifiedAt
        modelContext.insert(record)
        return true
    }

    private func applyPeriod(
        _ envelope: CloudRecordEnvelope
    ) throws -> Bool {
        let id = try uuid(envelope.recordID)
        let existing = try fetchPeriod(id)
        let sharingPersistence = SubscriptionSharingPersistence(
            context: modelContext
        )
        if envelope.isDeleted {
            guard let existing else { return false }
            guard try !hasPayment(periodID: id) else {
                throw ApplyError.dependentRecordsRemain("付款记录")
            }
            let parent = try fetchSubscription(existing.subscriptionID)
            try sharingPersistence.remove(
                subscriptionID: existing.subscriptionID,
                periodID: id
            )
            modelContext.delete(existing)
            try markHistoryChanged(parent)
            return true
        }

        let payload = try SyncRecordPayloadDecoder.period(
            recordID: envelope.recordID,
            fieldValues: envelope.fieldValues
        )
        guard let parent = try fetchSubscription(payload.input.subscriptionID)
        else {
            throw ApplyError.missingParentSubscription
        }
        if let existing {
            let current = try SyncRecordPayload.period(
                existing,
                sharing: sharingPersistence.plan(
                    subscriptionID: existing.subscriptionID,
                    periodID: existing.id
                )
            )
            guard current != envelope.fieldValues else { return false }
            let previousParentID = existing.subscriptionID
            try sharingPersistence.remove(
                subscriptionID: previousParentID,
                periodID: id
            )
            try sharingPersistence.set(
                payload.input.sharing,
                subscriptionID: payload.input.subscriptionID,
                periodID: id,
                myMoney: payload.input.money
            )
            apply(payload, to: existing)
            if previousParentID != payload.input.subscriptionID,
               let previousParent = try fetchSubscription(previousParentID) {
                try markHistoryChanged(previousParent)
            }
            try markHistoryChanged(parent)
            return true
        }

        try sharingPersistence.set(
            payload.input.sharing,
            subscriptionID: payload.input.subscriptionID,
            periodID: id,
            myMoney: payload.input.money
        )
        modelContext.insert(
            SubscriptionPeriodRecord(
                input: payload.input,
                now: payload.createdAt
            )
        )
        try markHistoryChanged(parent)
        return true
    }

    private func applyPayment(
        _ envelope: CloudRecordEnvelope
    ) async throws -> Bool {
        let id = try uuid(envelope.recordID)
        let existing = try fetchPayment(id)
        if envelope.isDeleted {
            guard let existing else { return false }
            let parent = try fetchSubscription(existing.subscriptionID)
            try removePaymentAttachments(paymentID: id)
            modelContext.delete(existing)
            try markHistoryChanged(parent)
            return true
        }

        let payload = try SyncRecordPayloadDecoder.payment(
            recordID: envelope.recordID,
            fieldValues: envelope.fieldValues
        )
        guard let parent = try fetchSubscription(payload.input.subscriptionID)
        else {
            throw ApplyError.missingReferencedRecord("订阅")
        }
        if let periodID = payload.input.periodRecordID {
            guard let period = try fetchPeriod(periodID) else {
                throw ApplyError.missingReferencedRecord("周期")
            }
            guard period.subscriptionID == payload.input.subscriptionID else {
                throw ApplyError.invalidStoredValue(
                    "payment.periodRecordID"
                )
            }
        }
        for reference in payload.input.attachmentReferences {
            try await requireAsset(
                reference,
                relationship: "付款附件"
            )
        }

        if let existing {
            let current = SyncRecordPayload.payment(
                existing,
                attachmentReferences: try paymentAttachmentReferences(
                    paymentID: id
                )
            )
            guard current != envelope.fieldValues else { return false }
            let previousParentID = existing.subscriptionID
            try apply(
                payload,
                modifiedAt: envelope.modifiedAt,
                to: existing
            )
            try replacePaymentAttachments(
                paymentID: id,
                references: payload.input.attachmentReferences
            )
            if previousParentID != payload.input.subscriptionID,
               let previousParent = try fetchSubscription(previousParentID) {
                try markHistoryChanged(previousParent)
            }
            try markHistoryChanged(parent)
            return true
        }

        let record = SubscriptionPaymentRecord(
            input: payload.input,
            now: payload.createdAt
        )
        record.updatedAt = envelope.modifiedAt
        modelContext.insert(record)
        try replacePaymentAttachments(
            paymentID: id,
            references: payload.input.attachmentReferences
        )
        try markHistoryChanged(parent)
        return true
    }

    private func applyTemplate(
        _ envelope: CloudRecordEnvelope
    ) async throws -> Bool {
        let id = try uuid(envelope.recordID)
        let existing = try fetchTemplate(id)
        if envelope.isDeleted {
            guard let existing else { return false }
            modelContext.delete(existing)
            return true
        }

        let payload = try SyncRecordPayloadDecoder.template(
            recordID: envelope.recordID,
            fieldValues: envelope.fieldValues
        )
        if let categoryID = payload.input.customCategoryID,
           try fetchCategory(categoryID) == nil {
            throw ApplyError.missingReferencedRecord("自定义分类")
        }
        try await requireAsset(
            payload.input.iconURLString,
            relationship: "模板图标"
        )
        if let existing {
            guard try SyncRecordPayload.template(existing)
                    != envelope.fieldValues else {
                return false
            }
            try apply(
                payload,
                modifiedAt: envelope.modifiedAt,
                to: existing
            )
            return true
        }

        let record = ServiceTemplateRecord(
            input: payload.input,
            aliasesData: payload.aliasesData,
            now: payload.createdAt
        )
        record.updatedAt = envelope.modifiedAt
        modelContext.insert(record)
        return true
    }

    private func applyCategory(
        _ envelope: CloudRecordEnvelope
    ) throws -> Bool {
        let id = try uuid(envelope.recordID)
        let existing = try fetchCategory(id)
        if envelope.isDeleted {
            guard let existing else { return false }
            guard try !hasTemplate(categoryID: id),
                  try !hasBuiltinAssignment(categoryID: id) else {
                throw ApplyError.dependentRecordsRemain("模板")
            }
            modelContext.delete(existing)
            return true
        }

        let payload = try SyncRecordPayloadDecoder.category(
            recordID: envelope.recordID,
            fieldValues: envelope.fieldValues
        )
        if let existing {
            guard SyncRecordPayload.category(existing)
                    != envelope.fieldValues else {
                return false
            }
            try apply(
                payload,
                modifiedAt: envelope.modifiedAt,
                to: existing
            )
            return true
        }

        let record = TemplateCategoryRecord(
            input: payload.input,
            now: payload.createdAt
        )
        record.updatedAt = envelope.modifiedAt
        modelContext.insert(record)
        return true
    }

    private func applyBuiltinCategoryAssignment(
        _ envelope: CloudRecordEnvelope
    ) throws -> Bool {
        let key = envelope.recordID
        let existing = try fetchBuiltinAssignment(key)
        if envelope.isDeleted {
            guard let existing else { return false }
            modelContext.delete(existing)
            return true
        }

        let payload = try SyncRecordPayloadDecoder
            .builtinCategoryAssignment(
                recordID: envelope.recordID,
                fieldValues: envelope.fieldValues
            )
        if let categoryID = payload.assignment.customCategoryID,
           try fetchCategory(categoryID) == nil {
            throw ApplyError.missingReferencedRecord("自定义分类")
        }
        if let existing {
            guard SyncRecordPayload.builtinCategoryAssignment(existing)
                    != envelope.fieldValues else {
                return false
            }
            existing.apply(
                payload.assignment,
                now: envelope.modifiedAt
            )
            return true
        }

        modelContext.insert(
            BuiltinTemplateCategoryAssignmentRecord(
                templateKey: payload.templateKey,
                assignment: payload.assignment,
                now: envelope.modifiedAt
            )
        )
        return true
    }

    private func apply(
        _ payload: SyncRecordPayloadDecoder.SubscriptionPayload,
        modifiedAt: Date,
        to record: SubscriptionRecord
    ) throws {
        let input = payload.input
        record.name = input.name
        record.symbolName = input.symbolName
        record.iconResourceName = input.iconResourceName
        record.iconURLString = input.iconURLString
        record.categoryRaw = input.category.rawValue
        record.managementStateRaw = input.managementState.rawValue
        record.billingKindRaw = input.billingKind.rawValue
        record.periodStartDay = input.periodStart?.dayNumber
        record.expiryDay = input.expiry?.dayNumber
        record.cycleMonths = input.cycleMonths
        record.periodAmountMinor = input.money.minorUnits
        record.currencyCode = input.money.currency.rawValue
        record.currencyScale = input.money.currency.scale
        record.note = input.note
        record.reminderEnabled = input.reminderEnabled
        record.reminderAdvanceDaysRaw =
            SubscriptionNotificationSchedule.storedAdvanceDays(
                input.reminderAdvanceDays
            )
        record.reminderMinuteOfDay = input.reminderMinuteOfDay
        record.automaticallyRenews = input.automaticallyRenews
        record.revision = try nextRevision(record.revision)
        record.createdAt = payload.createdAt
        record.updatedAt = modifiedAt
    }

    private func apply(
        _ payload: SyncRecordPayloadDecoder.PeriodPayload,
        to record: SubscriptionPeriodRecord
    ) {
        let input = payload.input
        record.subscriptionID = input.subscriptionID
        record.billingKindRaw = input.billingKind.rawValue
        record.cycleMonths = input.cycleMonths
        record.startDay = input.start.dayNumber
        record.endDay = input.end?.dayNumber
        record.amountMinor = input.money.minorUnits
        record.currencyCode = input.money.currency.rawValue
        record.currencyScale = input.money.currency.scale
        record.sourceRaw = input.source.rawValue
        record.createdAt = payload.createdAt
    }

    private func apply(
        _ payload: SyncRecordPayloadDecoder.PaymentPayload,
        modifiedAt: Date,
        to record: SubscriptionPaymentRecord
    ) throws {
        let input = payload.input
        record.subscriptionID = input.subscriptionID
        record.periodRecordID = input.periodRecordID
        record.kindRaw = input.kind.rawValue
        record.paymentDay = input.paymentDate.dayNumber
        record.amountMinor = input.money.minorUnits
        record.currencyCode = input.money.currency.rawValue
        record.currencyScale = input.money.currency.scale
        record.periodStartDay = input.periodStart?.dayNumber
        record.periodEndDay = input.periodEnd?.dayNumber
        record.note = input.note
        record.revision = try nextRevision(record.revision)
        record.createdAt = payload.createdAt
        record.updatedAt = modifiedAt
    }

    private func apply(
        _ payload: SyncRecordPayloadDecoder.TemplatePayload,
        modifiedAt: Date,
        to record: ServiceTemplateRecord
    ) throws {
        let input = payload.input
        record.name = input.name
        record.aliasesData = payload.aliasesData
        record.categoryRaw = input.category.rawValue
        record.customCategoryID = input.customCategoryID
        record.symbolName = input.symbolName
        record.iconResourceName = input.iconResourceName
        record.iconURLString = input.iconURLString
        record.suggestedBillingKindRaw = input.suggestedBillingKind.rawValue
        record.suggestedCycleMonths = input.suggestedCycleMonths
        record.suggestedAmountMinor = input.suggestedMoney?.minorUnits
        record.currencyCode = input.currency.rawValue
        record.currencyScale = input.currency.scale
        record.revision = try nextRevision(record.revision)
        record.createdAt = payload.createdAt
        record.updatedAt = modifiedAt
    }

    private func apply(
        _ payload: SyncRecordPayloadDecoder.CategoryPayload,
        modifiedAt: Date,
        to record: TemplateCategoryRecord
    ) throws {
        record.name = payload.input.name
        record.revision = try nextRevision(record.revision)
        record.createdAt = payload.createdAt
        record.updatedAt = modifiedAt
    }

    private func apply(
        _ envelope: CloudRecordEnvelope,
        serverRecordData: Data,
        to state: SyncRecordStateRecord
    ) {
        state.revision = envelope.revision
        state.modifiedAt = envelope.modifiedAt
        state.modifiedByDeviceID = envelope.modifiedByDeviceID
        state.isDeleted = envelope.isDeleted
        state.deletedAt = envelope.deletedAt
        state.serverRecordData = serverRecordData
    }

    private func snapshot(
        for state: SyncRecordStateRecord
    ) async throws -> SyncRecordSnapshot {
        guard let recordType = SyncRecordType(
            rawValue: state.recordTypeRaw
        ) else {
            throw ApplyError.invalidStoredValue("recordTypeRaw")
        }
        let values: [String: SyncValue]
        if state.isDeleted {
            values = [:]
        } else {
            values = try await payload(
                recordType: recordType,
                recordID: state.recordID
            )
        }
        return SyncRecordSnapshot(
            recordType: recordType,
            recordID: state.recordID,
            revision: state.revision,
            modifiedAt: state.modifiedAt,
            modifiedByDeviceID: state.modifiedByDeviceID,
            isDeleted: state.isDeleted,
            deletedAt: state.deletedAt,
            fieldValues: values,
            serverRecordData: state.serverRecordData
        )
    }

    private func payload(
        recordType: SyncRecordType,
        recordID: String
    ) async throws -> [String: SyncValue] {
        let sharingPersistence = SubscriptionSharingPersistence(
            context: modelContext
        )
        switch recordType {
        case .subscription:
            let id = try uuid(recordID)
            guard let record = try fetchSubscription(id) else {
                throw ApplyError.invalidStoredValue("subscription")
            }
            return try SyncRecordPayload.subscription(
                record,
                sharing: sharingPersistence.plan(subscriptionID: id)
            )
        case .subscriptionPeriod:
            let id = try uuid(recordID)
            guard let record = try fetchPeriod(id) else {
                throw ApplyError.invalidStoredValue("subscriptionPeriod")
            }
            return try SyncRecordPayload.period(
                record,
                sharing: sharingPersistence.plan(
                    subscriptionID: record.subscriptionID,
                    periodID: id
                )
            )
        case .subscriptionPayment:
            let id = try uuid(recordID)
            guard let record = try fetchPayment(id) else {
                throw ApplyError.invalidStoredValue("subscriptionPayment")
            }
            return SyncRecordPayload.payment(
                record,
                attachmentReferences: try paymentAttachmentReferences(
                    paymentID: id
                )
            )
        case .serviceTemplate:
            let id = try uuid(recordID)
            guard let record = try fetchTemplate(id) else {
                throw ApplyError.invalidStoredValue("serviceTemplate")
            }
            return try SyncRecordPayload.template(record)
        case .templateCategory:
            let id = try uuid(recordID)
            guard let record = try fetchCategory(id) else {
                throw ApplyError.invalidStoredValue("templateCategory")
            }
            return SyncRecordPayload.category(record)
        case .builtinTemplateCategoryAssignment:
            guard let record = try fetchBuiltinAssignment(recordID) else {
                throw ApplyError.invalidStoredValue(
                    "builtinTemplateCategoryAssignment"
                )
            }
            return SyncRecordPayload.builtinCategoryAssignment(record)
        case .iconAsset:
            guard CloudAssetRepository.isSupportedReference(recordID),
                  let assetRepository else {
                throw ApplyError.invalidStoredValue("iconAsset")
            }
            return SyncRecordPayload.iconAsset(
                reference: recordID,
                metadata: try await assetRepository.metadata(
                    reference: recordID
                )
            )
        }
    }

    private func existingPayload(
        recordType: SyncRecordType,
        recordID: String
    ) async throws -> [String: SyncValue]? {
        let sharingPersistence = SubscriptionSharingPersistence(
            context: modelContext
        )
        switch recordType {
        case .subscription:
            let id = try uuid(recordID)
            guard let record = try fetchSubscription(id) else { return nil }
            return try SyncRecordPayload.subscription(
                record,
                sharing: sharingPersistence.plan(subscriptionID: id)
            )
        case .subscriptionPeriod:
            let id = try uuid(recordID)
            guard let record = try fetchPeriod(id) else { return nil }
            return try SyncRecordPayload.period(
                record,
                sharing: sharingPersistence.plan(
                    subscriptionID: record.subscriptionID,
                    periodID: id
                )
            )
        case .subscriptionPayment:
            let id = try uuid(recordID)
            guard let record = try fetchPayment(id) else { return nil }
            return SyncRecordPayload.payment(
                record,
                attachmentReferences: try paymentAttachmentReferences(
                    paymentID: id
                )
            )
        case .serviceTemplate:
            let id = try uuid(recordID)
            guard let record = try fetchTemplate(id) else { return nil }
            return try SyncRecordPayload.template(record)
        case .templateCategory:
            let id = try uuid(recordID)
            guard let record = try fetchCategory(id) else { return nil }
            return SyncRecordPayload.category(record)
        case .builtinTemplateCategoryAssignment:
            guard let record = try fetchBuiltinAssignment(recordID) else {
                return nil
            }
            return SyncRecordPayload.builtinCategoryAssignment(record)
        case .iconAsset:
            guard CloudAssetRepository.isSupportedReference(recordID),
                  let assetRepository,
                  let metadata = try await assetRepository.metadataIfPresent(
                    reference: recordID
                  ) else {
                return nil
            }
            return SyncRecordPayload.iconAsset(
                reference: recordID,
                metadata: metadata
            )
        }
    }

    private func localChangeSet(
        snapshot: SyncRecordSnapshot,
        mutations: [SyncMutationRecord]
    ) throws -> SyncChangeSet {
        let ordered = mutations.sorted {
            ($0.targetRevision, $0.createdAt, $0.mutationID.uuidString)
                < ($1.targetRevision, $1.createdAt, $1.mutationID.uuidString)
        }
        guard let first = ordered.first, let last = ordered.last else {
            throw ApplyError.invalidMutationChain
        }
        var expectedBase = first.baseRevision
        var changedFields: Set<String> = []
        for (index, mutation) in ordered.enumerated() {
            guard mutation.baseRevision == expectedBase,
                  mutation.targetRevision > mutation.baseRevision else {
                throw ApplyError.invalidMutationChain
            }
            if index > 0,
               mutation.targetRevision != mutation.baseRevision + 1 {
                throw ApplyError.invalidMutationChain
            }
            expectedBase = mutation.targetRevision
            changedFields.formUnion(
                try SyncMutationJournal.changedFields(from: mutation)
            )
        }
        guard snapshot.revision == last.targetRevision else {
            throw ApplyError.invalidMutationChain
        }
        let operation: SyncMutationOperation
        if snapshot.isDeleted {
            operation = .delete
        } else if first.baseRevision == 0 {
            operation = .create
        } else {
            operation = .update
        }
        return SyncChangeSet(
            recordType: snapshot.recordType,
            recordID: snapshot.recordID,
            baseRevision: first.baseRevision,
            targetRevision: snapshot.revision,
            operation: operation,
            fieldValues: snapshot.fieldValues.filter {
                changedFields.contains($0.key)
            },
            relationshipChanges: try collapsedRelationships(ordered)
        )
    }

    private func collapsedRelationships(
        _ mutations: [SyncMutationRecord]
    ) throws -> Set<SyncRelationshipChange> {
        var latest: [RelationshipIdentity: SyncRelationshipChange] = [:]
        for mutation in mutations {
            for change in try SyncMutationJournal.relationshipChanges(
                from: mutation
            ) {
                latest[RelationshipIdentity(change)] = change
            }
        }
        return Set(latest.values)
    }

    private func syntheticChange(
        from snapshot: SyncRecordSnapshot
    ) -> SyncChangeSet {
        SyncChangeSet(
            recordType: snapshot.recordType,
            recordID: snapshot.recordID,
            baseRevision: max(snapshot.revision - 1, 0),
            targetRevision: snapshot.revision,
            operation: snapshot.isDeleted
                ? .delete
                : (snapshot.revision == 1 ? .create : .update),
            fieldValues: snapshot.fieldValues,
            relationshipChanges: []
        )
    }

    private func persistConflict(
        sourceChangeID: String,
        localSnapshot: SyncRecordSnapshot,
        localChange: SyncChangeSet,
        remoteEnvelope: CloudRecordEnvelope,
        remoteServerRecordData: Data,
        reasons: [SyncMergeConflictReason],
        localMutations: [SyncMutationRecord],
        now: Date
    ) throws {
        var descriptor = FetchDescriptor<SyncConflictRecord>(
            predicate: #Predicate { $0.sourceChangeID == sourceChangeID }
        )
        descriptor.fetchLimit = 1
        if try modelContext.fetch(descriptor).isEmpty {
            let payload = SyncConflictPayload(
                localSnapshot: localSnapshot,
                localChange: localChange,
                remoteEnvelope: remoteEnvelope,
                reasons: reasons
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            modelContext.insert(
                SyncConflictRecord(
                    sourceChangeID: sourceChangeID,
                    recordType: remoteEnvelope.recordType,
                    recordID: remoteEnvelope.recordID,
                    payloadData: try encoder.encode(payload),
                    remoteServerRecordData: remoteServerRecordData,
                    now: now
                )
            )
        }
        for mutation in localMutations {
            mutation.stateRaw = SyncMutationState.conflicted.rawValue
            mutation.updatedAt = now
        }
    }

    private func activeMutations(
        recordType: SyncRecordType,
        recordID: String
    ) throws -> [SyncMutationRecord] {
        let recordTypeRaw = recordType.rawValue
        return try modelContext.fetch(
            FetchDescriptor<SyncMutationRecord>(
                predicate: #Predicate {
                    $0.recordTypeRaw == recordTypeRaw
                        && $0.recordID == recordID
                }
            )
        )
        .filter {
            $0.stateRaw != SyncMutationState.acknowledged.rawValue
        }
    }

    private func fetchRemoteChange(
        _ sourceChangeID: String
    ) throws -> SyncRemoteChangeRecord {
        var descriptor = FetchDescriptor<SyncRemoteChangeRecord>(
            predicate: #Predicate {
                $0.sourceChangeID == sourceChangeID
            }
        )
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first else {
            throw ApplyError.invalidStoredValue("sourceChangeID")
        }
        return record
    }

    private func fetchConflict(
        _ conflictID: UUID
    ) throws -> SyncConflictRecord {
        var descriptor = FetchDescriptor<SyncConflictRecord>(
            predicate: #Predicate {
                $0.conflictID == conflictID
            }
        )
        descriptor.fetchLimit = 1
        guard let record = try modelContext.fetch(descriptor).first else {
            throw ApplyError.conflictNotFound
        }
        return record
    }

    private func fetchState(
        recordType: SyncRecordType,
        recordID: String
    ) throws -> SyncRecordStateRecord? {
        let recordKey = SyncRecordStateRecord.key(
            recordType: recordType,
            recordID: recordID
        )
        var descriptor = FetchDescriptor<SyncRecordStateRecord>(
            predicate: #Predicate { $0.recordKey == recordKey }
        )
        descriptor.fetchLimit = 2
        let records = try modelContext.fetch(descriptor)
        guard records.count <= 1 else {
            throw ApplyError.invalidStoredValue("recordKey")
        }
        return records.first
    }

    private func hasUnresolvedConflict(
        recordType: SyncRecordType,
        recordID: String
    ) throws -> Bool {
        let recordTypeRaw = recordType.rawValue
        let unresolved = SyncConflictState.unresolved.rawValue
        var descriptor = FetchDescriptor<SyncConflictRecord>(
            predicate: #Predicate {
                $0.recordTypeRaw == recordTypeRaw
                    && $0.recordID == recordID
                    && $0.stateRaw == unresolved
            }
        )
        descriptor.fetchLimit = 1
        return try !modelContext.fetch(descriptor).isEmpty
    }

    private func fetchSubscription(
        _ id: UUID
    ) throws -> SubscriptionRecord? {
        var descriptor = FetchDescriptor<SubscriptionRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchPeriod(
        _ id: UUID
    ) throws -> SubscriptionPeriodRecord? {
        var descriptor = FetchDescriptor<SubscriptionPeriodRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchPayment(
        _ id: UUID
    ) throws -> SubscriptionPaymentRecord? {
        var descriptor = FetchDescriptor<SubscriptionPaymentRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchTemplate(
        _ id: UUID
    ) throws -> ServiceTemplateRecord? {
        var descriptor = FetchDescriptor<ServiceTemplateRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchCategory(
        _ id: UUID
    ) throws -> TemplateCategoryRecord? {
        var descriptor = FetchDescriptor<TemplateCategoryRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchBuiltinAssignment(
        _ templateKey: String
    ) throws -> BuiltinTemplateCategoryAssignmentRecord? {
        var descriptor = FetchDescriptor<
            BuiltinTemplateCategoryAssignmentRecord
        >(
            predicate: #Predicate { $0.templateKey == templateKey }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func hasPeriod(subscriptionID: UUID) throws -> Bool {
        var descriptor = FetchDescriptor<SubscriptionPeriodRecord>(
            predicate: #Predicate {
                $0.subscriptionID == subscriptionID
            }
        )
        descriptor.fetchLimit = 1
        return try !modelContext.fetch(descriptor).isEmpty
    }

    private func hasPayment(subscriptionID: UUID) throws -> Bool {
        var descriptor = FetchDescriptor<SubscriptionPaymentRecord>(
            predicate: #Predicate {
                $0.subscriptionID == subscriptionID
            }
        )
        descriptor.fetchLimit = 1
        return try !modelContext.fetch(descriptor).isEmpty
    }

    private func hasPayment(periodID: UUID) throws -> Bool {
        var descriptor = FetchDescriptor<SubscriptionPaymentRecord>(
            predicate: #Predicate {
                $0.periodRecordID == periodID
            }
        )
        descriptor.fetchLimit = 1
        return try !modelContext.fetch(descriptor).isEmpty
    }

    private func hasTemplate(categoryID: UUID) throws -> Bool {
        var descriptor = FetchDescriptor<ServiceTemplateRecord>(
            predicate: #Predicate {
                $0.customCategoryID == categoryID
            }
        )
        descriptor.fetchLimit = 1
        return try !modelContext.fetch(descriptor).isEmpty
    }

    private func hasBuiltinAssignment(categoryID: UUID) throws -> Bool {
        var descriptor = FetchDescriptor<
            BuiltinTemplateCategoryAssignmentRecord
        >(
            predicate: #Predicate {
                $0.customCategoryID == categoryID
            }
        )
        descriptor.fetchLimit = 1
        return try !modelContext.fetch(descriptor).isEmpty
    }

    private func requireAsset(
        _ reference: String?,
        relationship: String
    ) async throws {
        guard let reference,
              CloudAssetRepository.isSupportedReference(reference) else {
            return
        }
        guard let assetRepository else {
            throw ApplyError.missingReferencedRecord(relationship)
        }
        if let state = try fetchState(
            recordType: .iconAsset,
            recordID: reference
        ), state.isDeleted {
            throw ApplyError.missingReferencedRecord(relationship)
        }
        guard try await assetRepository.metadataIfPresent(
            reference: reference
        ) != nil else {
            throw ApplyError.missingReferencedRecord(relationship)
        }
    }

    private func isAssetReferenced(_ reference: String) throws -> Bool {
        var subscriptionDescriptor = FetchDescriptor<SubscriptionRecord>(
            predicate: #Predicate {
                $0.iconURLString == reference
            }
        )
        subscriptionDescriptor.fetchLimit = 1
        if try !modelContext.fetch(subscriptionDescriptor).isEmpty {
            return true
        }

        var templateDescriptor = FetchDescriptor<ServiceTemplateRecord>(
            predicate: #Predicate {
                $0.iconURLString == reference
            }
        )
        templateDescriptor.fetchLimit = 1
        if try !modelContext.fetch(templateDescriptor).isEmpty {
            return true
        }

        var attachmentDescriptor = FetchDescriptor<
            SubscriptionPaymentAttachmentItemRecord
        >(
            predicate: #Predicate {
                $0.reference == reference
            }
        )
        attachmentDescriptor.fetchLimit = 1
        if try !modelContext.fetch(attachmentDescriptor).isEmpty {
            return true
        }

        var legacyDescriptor = FetchDescriptor<
            SubscriptionPaymentAttachmentRecord
        >(
            predicate: #Predicate {
                $0.reference == reference
            }
        )
        legacyDescriptor.fetchLimit = 1
        return try !modelContext.fetch(legacyDescriptor).isEmpty
    }

    private func paymentAttachmentReferences(
        paymentID: UUID
    ) throws -> [String] {
        let current = try modelContext.fetch(
            FetchDescriptor<SubscriptionPaymentAttachmentItemRecord>(
                predicate: #Predicate { $0.paymentID == paymentID },
                sortBy: [
                    SortDescriptor(\.sortOrder, order: .forward),
                ]
            )
        ).map(\.reference)
        guard current.isEmpty else { return current }
        return try modelContext.fetch(
            FetchDescriptor<SubscriptionPaymentAttachmentRecord>(
                predicate: #Predicate { $0.paymentID == paymentID }
            )
        ).map(\.reference)
    }

    private func replacePaymentAttachments(
        paymentID: UUID,
        references: [String]
    ) throws {
        try removePaymentAttachments(paymentID: paymentID)
        for (sortOrder, reference) in references.enumerated() {
            modelContext.insert(
                SubscriptionPaymentAttachmentItemRecord(
                    paymentID: paymentID,
                    reference: reference,
                    sortOrder: sortOrder
                )
            )
        }
    }

    private func removePaymentAttachments(paymentID: UUID) throws {
        let current = try modelContext.fetch(
            FetchDescriptor<SubscriptionPaymentAttachmentItemRecord>(
                predicate: #Predicate { $0.paymentID == paymentID }
            )
        )
        current.forEach(modelContext.delete)
        let legacy = try modelContext.fetch(
            FetchDescriptor<SubscriptionPaymentAttachmentRecord>(
                predicate: #Predicate { $0.paymentID == paymentID }
            )
        )
        legacy.forEach(modelContext.delete)
    }

    private func markHistoryChanged(
        _ record: SubscriptionRecord?
    ) throws {
        guard let record else { return }
        record.revision = try nextRevision(record.revision)
        record.updatedAt = .now
    }

    private func nextRevision(_ revision: Int64) throws -> Int64 {
        let (next, overflow) = revision.addingReportingOverflow(1)
        guard !overflow else {
            throw ApplyError.revisionOverflow
        }
        return next
    }

    private func snapshotsMatch(
        _ local: SyncRecordSnapshot,
        _ remote: CloudRecordEnvelope
    ) -> Bool {
        local.recordType == remote.recordType
            && local.recordID == remote.recordID
            && local.isDeleted == remote.isDeleted
            && local.fieldValues == remote.fieldValues
    }

    private func uuid(_ rawValue: String) throws -> UUID {
        guard let value = UUID(uuidString: rawValue) else {
            throw ApplyError.invalidStoredValue("recordID")
        }
        return value
    }

    private func supportsApplication(
        _ recordType: SyncRecordType
    ) -> Bool {
        switch recordType {
        case .subscription,
             .subscriptionPeriod,
             .subscriptionPayment,
             .serviceTemplate,
             .templateCategory,
             .builtinTemplateCategoryAssignment,
             .iconAsset:
            true
        }
    }

    private func remoteChangeSort(
        _ lhs: SyncRemoteChangeRecord,
        _ rhs: SyncRemoteChangeRecord
    ) -> Bool {
        (
            recordPriority(
                lhs.recordTypeRaw,
                isDeleted: storedEnvelopeIsDeleted(lhs)
            ),
            lhs.receivedAt,
            lhs.sourceChangeID
        ) < (
            recordPriority(
                rhs.recordTypeRaw,
                isDeleted: storedEnvelopeIsDeleted(rhs)
            ),
            rhs.receivedAt,
            rhs.sourceChangeID
        )
    }

    private func storedEnvelopeIsDeleted(
        _ record: SyncRemoteChangeRecord
    ) -> Bool {
        (try? JSONDecoder().decode(
            CloudRecordEnvelope.self,
            from: record.envelopeData
        ).isDeleted) ?? false
    }

    private func recordPriority(
        _ recordTypeRaw: String,
        isDeleted: Bool
    ) -> Int {
        switch SyncRecordType(rawValue: recordTypeRaw) {
        case .subscription:
            isDeleted ? 4 : 0
        case .subscriptionPeriod:
            isDeleted ? 3 : 1
        case .subscriptionPayment:
            isDeleted ? 0 : 2
        case .serviceTemplate,
             .builtinTemplateCategoryAssignment:
            isDeleted ? 0 : 1
        case .templateCategory:
            isDeleted ? 3 : 0
        case .iconAsset:
            isDeleted ? 5 : -1
        case nil:
            6
        }
    }

    private func failureCode(for error: any Error) -> String {
        switch error {
        case is SyncRecordPayloadDecoder.PayloadError:
            "invalidPayload"
        case is DecodingError:
            "invalidEnvelope"
        case is SubscriptionSharingError:
            "invalidSharing"
        case is ApplyError:
            "invalidLocalState"
        default:
            "applyFailed"
        }
    }

    private struct RelationshipIdentity: Hashable {
        let relationship: String
        let relatedRecordType: SyncRecordType
        let relatedRecordID: String

        init(_ change: SyncRelationshipChange) {
            relationship = change.relationship
            relatedRecordType = change.relatedRecordType
            relatedRecordID = change.relatedRecordID
        }
    }
}
