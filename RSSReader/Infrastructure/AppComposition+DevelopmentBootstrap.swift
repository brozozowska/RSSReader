import Foundation

extension AppComposition {
    @MainActor
    static func runDevelopmentSchemaBootstrapIfNeeded(
        logger: Logging
    ) {
        runDevelopmentSchemaBootstrapIfNeeded(
            logger: logger,
            guard: developmentSchemaBootstrapGuard
        ) { bootstrapLogger in
            CloudKitDevelopmentSchemaBootstrap.bootstrapIfNeeded(logger: bootstrapLogger)
        }
    }

    @MainActor
    static func runDevelopmentSchemaBootstrapIfNeeded(
        logger: Logging,
        guard bootstrapGuard: AppLaunchBootstrapGuard,
        bootstrap: (Logging) -> Void
    ) {
        guard bootstrapGuard.beginAttempt(identifier: "CloudKitDevelopmentSchemaBootstrap") else {
            logger.debug("Skipped CloudKit development schema bootstrap because app launch guard already attempted it")
            return
        }

        bootstrap(logger)
    }
}

@MainActor
final class AppLaunchBootstrapGuard {
    private var attemptedIdentifiers: Set<String> = []

    func beginAttempt(identifier: String) -> Bool {
        attemptedIdentifiers.insert(identifier).inserted
    }
}
