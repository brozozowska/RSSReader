import CloudKit
import CoreData
import Foundation
import SwiftData

struct CloudKitStoreBootstrapRequest {
    let containerIdentifier: String
    let storeConfigurationName: String
    let storeURL: URL
    let modelTypes: [any PersistentModel.Type]
}

enum CloudKitStoreBootstrapDiagnostics {
    static func persistentStoreProbeFailureDescription(
        using request: CloudKitStoreBootstrapRequest
    ) -> String? {
        let accountStatus = CloudKitAccountStatusResolver.currentStatus(for: request.containerIdentifier)
        guard accountStatus == .available else {
            return "Persistent store probe skipped because CloudKit account status is \(String(describing: accountStatus))."
        }

        guard let managedObjectModel = NSManagedObjectModel.makeManagedObjectModel(for: request.modelTypes) else {
            return "Could not create managed object model for persistent store probe."
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

        guard let loadError else {
            if let store = container.persistentStoreCoordinator.persistentStores.first {
                try? container.persistentStoreCoordinator.remove(store)
            }
            return nil
        }

        return describeErrorChain(loadError).joined(separator: "\n")
    }

    static func describeErrorChain(_ error: Error) -> [String] {
        describeErrorChain(error, level: 0)
    }

    private static func describeErrorChain(_ error: Error, level: Int) -> [String] {
        let nsError = error as NSError
        let prefix = level == 0 ? "Error" : "Underlying error \(level)"
        var lines = ["\(prefix): \(describeNSError(nsError))"]

        for underlyingError in extractUnderlyingErrors(from: nsError) {
            lines.append(contentsOf: describeErrorChain(underlyingError, level: level + 1))
        }

        return lines
    }

    private static func describeNSError(_ error: NSError) -> String {
        let userInfoDescription = describeUserInfo(error.userInfo)
        return "domain=\(error.domain) code=\(error.code) localizedDescription=\(error.localizedDescription) userInfo=\(userInfoDescription)"
    }

    private static func describeUserInfo(_ userInfo: [String: Any]) -> String {
        guard userInfo.isEmpty == false else { return "{}" }

        let filteredEntries = userInfo
            .filter { $0.key != NSUnderlyingErrorKey }
            .sorted { $0.key < $1.key }

        guard filteredEntries.isEmpty == false else { return "{}" }

        let pairs = filteredEntries.map { key, value in
            "\(key)=\(String(describing: value))"
        }

        return "{\(pairs.joined(separator: ", "))}"
    }

    private static func extractUnderlyingErrors(from error: NSError) -> [Error] {
        if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? Error {
            return [underlyingError]
        }

        if let underlyingErrors = error.userInfo[NSUnderlyingErrorKey] as? [Error] {
            return underlyingErrors
        }

        return []
    }
}
