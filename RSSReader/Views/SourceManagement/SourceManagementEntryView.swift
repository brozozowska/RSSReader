import SwiftUI

enum SourceManagementEntryScenario: String, CaseIterable, Hashable, Identifiable {
    case addFeed
    case createFolder
    case moveSource

    var id: Self { self }

    var title: String {
        switch self {
        case .addFeed:
            "Add Feed"
        case .createFolder:
            "Create Folder"
        case .moveSource:
            "Move Sources"
        }
    }

    var subtitle: String {
        switch self {
        case .addFeed:
            "Paste a feed URL, preview the source, and choose where it should live before saving."
        case .createFolder:
            "Create a folder first when you want to organize feeds before adding or moving them."
        case .moveSource:
            "Move existing feeds between folders or return them to the Ungrouped area without repeating the add flow."
        }
    }

    var systemImageName: String {
        switch self {
        case .addFeed:
            "dot.radiowaves.left.and.right"
        case .createFolder:
            "folder.badge.plus"
        case .moveSource:
            "arrow.left.arrow.right.circle"
        }
    }

    var badgeTitle: String {
        switch self {
        case .addFeed:
            "New Feed"
        case .createFolder:
            "New Folder"
        case .moveSource:
            "Existing Sources"
        }
    }

    var detailTitle: String {
        switch self {
        case .addFeed:
            "Feed Setup"
        case .createFolder:
            "Folder Setup"
        case .moveSource:
            "Source Organization"
        }
    }

    var detailSummary: String {
        switch self {
        case .addFeed:
            "This flow is dedicated to adding a new feed from URL input through preview and confirmation."
        case .createFolder:
            "This flow is dedicated to creating a reusable folder before any feed is assigned to it."
        case .moveSource:
            "This flow is dedicated to reorganizing existing feeds after they are already in the library."
        }
    }

    var upcomingSteps: [String] {
        switch self {
        case .addFeed:
            [
                "accept and normalize a feed URL before any network request starts",
                "preview feed metadata so the user can confirm the source before saving",
                "choose a destination folder or keep the feed ungrouped"
            ]
        case .createFolder:
            [
                "collect a folder name with validation and uniqueness checks",
                "reserve a compatible sort order for the sidebar grouping model",
                "return the new folder as a destination for later source assignment"
            ]
        case .moveSource:
            [
                "pick an existing feed instead of starting a new add-feed flow",
                "move the feed into another folder or back to the ungrouped state",
                "keep organization work separate from feed creation and URL validation"
            ]
        }
    }

    static let primaryScenarios: [SourceManagementEntryScenario] = [
        .addFeed,
        .createFolder
    ]

    static let organizationScenarios: [SourceManagementEntryScenario] = [
        .moveSource
    ]
}

struct SourceManagementEntryView: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    entrySummary
                }

                Section {
                    ForEach(SourceManagementEntryScenario.primaryScenarios) { scenario in
                        NavigationLink(value: scenario) {
                            SourceManagementEntryCard(scenario: scenario)
                        }
                    }
                } header: {
                    Text("Start Something New")
                } footer: {
                    Text("Adding a feed and creating a folder stay separate, so URL preview and folder creation do not collapse into one mixed form.")
                }

                Section {
                    ForEach(SourceManagementEntryScenario.organizationScenarios) { scenario in
                        NavigationLink(value: scenario) {
                            SourceManagementEntryCard(scenario: scenario)
                        }
                    }
                } header: {
                    Text("Organize Existing Sources")
                } footer: {
                    Text("Folder assignment and move actions are presented as their own flow instead of being hidden inside the initial add-source path.")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(appThemeVariant.primaryBackground)
            .navigationTitle("Add Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: dismiss)
                }
            }
            .navigationDestination(for: SourceManagementEntryScenario.self) { scenario in
                SourceManagementScenarioPlaceholderView(scenario: scenario)
            }
        }
    }

    private var entrySummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose the source task you want to start.")
                .font(.headline)

            Text("Source Management now opens with separate paths for adding feeds, creating folders, and organizing existing sources.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct SourceManagementEntryCard: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    let scenario: SourceManagementEntryScenario

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(appThemeVariant.secondaryBackground)
                    .frame(width: 40, height: 40)

                Image(systemName: scenario.systemImageName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(scenario.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(scenario.badgeTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(appThemeVariant.secondaryBackground)
                        .clipShape(Capsule())
                }

                Text(scenario.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct SourceManagementScenarioPlaceholderView: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    let scenario: SourceManagementEntryScenario

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(scenario.detailTitle)
                        .font(.headline)

                    Text(scenario.detailSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("What This Flow Will Cover") {
                ForEach(scenario.upcomingSteps, id: \.self) { step in
                    Text(step)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(appThemeVariant.primaryBackground)
        .navigationTitle(scenario.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Source Management Entry") {
    SourceManagementEntryView(dismiss: {})
        .environment(\.appThemeVariant, .light)
}

#Preview("Source Management Entry · Move Sources") {
    NavigationStack {
        SourceManagementScenarioPlaceholderView(scenario: .moveSource)
            .environment(\.appThemeVariant, .light)
    }
}
