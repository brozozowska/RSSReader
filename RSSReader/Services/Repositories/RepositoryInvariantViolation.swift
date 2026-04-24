import Foundation

enum RepositoryInvariantViolation: Error, Equatable, Sendable {
    case duplicateFeedURL(String)
    case duplicateFolderName(String)
}
