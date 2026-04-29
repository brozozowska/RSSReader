import CloudKit
import CoreData
import Foundation
import SwiftData

enum CloudKitDevelopmentSchemaBootstrapDecision {
    case run(CloudKitStoreBootstrapRequest)
    case skip(String)
}

enum CloudKitDevelopmentSchemaBootstrap {
    static func bootstrapIfNeeded(logger: Logging) {
#if DEBUG
        switch makeDecision() {
        case .run(let request):
            let accountStatus = CloudKitAccountStatusResolver.currentStatus(
                for: request.containerIdentifier
            )
            guard accountStatus == .available else {
                logger.info(
                    "Skipped CloudKit development schema bootstrap because account status is \(String(describing: accountStatus))"
                )
                return
            }
            do {
                try initializeDevelopmentSchema(using: request, logger: logger)
            } catch {
                logger.error("Failed to initialize CloudKit development schema: \(error)")
            }
        case .skip(let reason):
            logger.info("Skipped CloudKit development schema bootstrap: \(reason)")
        }
#endif
    }

    static func makeDecision(
        audit: CloudKitCompatibilityAudit = .currentSyncBackedModelSet,
        modelPartition: AppPersistenceModelPartition = .current,
        containerIdentifier: String = CloudKitContainerConfiguration.containerIdentifier,
        syncBackedPolicy: AppPersistenceCloudKitPolicy = CloudKitContainerConfiguration.syncBackedDatabasePolicy
    ) -> CloudKitDevelopmentSchemaBootstrapDecision {
        let blockingReports = audit.reports.filter(\.hasBlockingFindings)
        if blockingReports.isEmpty == false {
            let blockerSummary = blockingReports
                .map { report in
                    let paths = report.findings
                        .filter { $0.severity == .blocker }
                        .flatMap(\.affectedPaths)
                        .joined(separator: ", ")
                    return "\(report.model.rawValue): \(paths)"
                }
                .joined(separator: "; ")
            return .skip("sync-backed schema still has CloudKit blockers (\(blockerSummary))")
        }

        guard case .privateContainer(let explicitIdentifier) = syncBackedPolicy else {
            return .skip("sync-backed store does not use an explicit private CloudKit container policy")
        }

        let configurationPlan = AppPersistenceConfigurationPlan.make(
            modelPartition: modelPartition,
            isStoredInMemoryOnly: false,
            syncBackedCloudKitPolicy: syncBackedPolicy
        )
        let syncBackedStore = configurationPlan.syncBackedStore

        return .run(
            CloudKitStoreBootstrapRequest(
                containerIdentifier: explicitIdentifier.isEmpty ? containerIdentifier : explicitIdentifier,
                storeConfigurationName: syncBackedStore.name,
                storeURL: syncBackedStore.modelConfiguration.url,
                modelTypes: syncBackedStore.modelTypes
            )
        )
    }

    private static func initializeDevelopmentSchema(
        using request: CloudKitStoreBootstrapRequest,
        logger: Logging
    ) throws {
        try autoreleasepool {
            guard let managedObjectModel = NSManagedObjectModel.makeManagedObjectModel(for: request.modelTypes) else {
                throw CloudKitDevelopmentSchemaBootstrapError.couldNotCreateManagedObjectModel
            }

            let storeDescription = NSPersistentStoreDescription(url: request.storeURL)
            storeDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: request.containerIdentifier
            )
            storeDescription.shouldAddStoreAsynchronously = false

            let container = NSPersistentCloudKitContainer(
                name: request.storeConfigurationName,
                managedObjectModel: managedObjectModel
            )
            container.persistentStoreDescriptions = [storeDescription]

            var loadError: Error?
            container.loadPersistentStores { _, error in
                loadError = error
            }

            if let loadError {
                throw loadError
            }

            try container.initializeCloudKitSchema()

            if let store = container.persistentStoreCoordinator.persistentStores.first {
                try container.persistentStoreCoordinator.remove(store)
            }

            container.persistentStoreDescriptions = []
        }

        logger.info(
            "Initialized CloudKit development schema for \(request.containerIdentifier) using \(request.storeConfigurationName)"
        )
    }
}

enum CloudKitDevelopmentSchemaBootstrapError: Error {
    case couldNotCreateManagedObjectModel
}
