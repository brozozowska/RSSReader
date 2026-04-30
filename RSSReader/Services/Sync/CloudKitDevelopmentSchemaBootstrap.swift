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
        bootstrapIfNeeded(
            logger: logger,
            resolveAccountStatus: { containerIdentifier in
                CloudKitAccountStatusResolver.currentStatus(for: containerIdentifier)
            },
            initializeSchema: { request, schemaLogger in
                try initializeDevelopmentSchema(using: request, logger: schemaLogger)
            }
        )
    }

    static func bootstrapIfNeeded(
        logger: Logging,
        decision: CloudKitDevelopmentSchemaBootstrapDecision? = nil,
        resolveAccountStatus: (String) -> CKAccountStatus,
        initializeSchema: (CloudKitStoreBootstrapRequest, Logging) throws -> Void
    ) {
#if DEBUG
        switch decision ?? makeDecision() {
        case .run(let request):
            logger.info(
                "Evaluating CloudKit development schema bootstrap request: containerIdentifier=\(request.containerIdentifier) storeConfigurationName=\(request.storeConfigurationName) storeURL=\(request.storeURL.path)"
            )
            let accountStatus = resolveAccountStatus(request.containerIdentifier)
            let availability = DefaultICloudAccountAvailabilityService.mapAccountAvailability(from: accountStatus)
            guard accountStatus == .available else {
                logger.info(
                    "Skipped CloudKit development schema bootstrap because account status is \(String(describing: accountStatus)) availability=\(availability.rawValue)"
                )
                return
            }
            do {
                logger.info(
                    "Running CloudKit development schema bootstrap: containerIdentifier=\(request.containerIdentifier) storeConfigurationName=\(request.storeConfigurationName)"
                )
                try initializeSchema(request, logger)
            } catch {
                logger.error(
                    "Failed to initialize CloudKit development schema: containerIdentifier=\(request.containerIdentifier) storeConfigurationName=\(request.storeConfigurationName) error=\(error)"
                )
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
            "Initialized CloudKit development schema for \(request.containerIdentifier) using \(request.storeConfigurationName) at \(request.storeURL.path)"
        )
    }
}

enum CloudKitDevelopmentSchemaBootstrapError: Error {
    case couldNotCreateManagedObjectModel
}
