import SwiftUI

struct SourceManagementScreenActionHandlers {
    let dismiss: () -> Void
    let selectScenario: (SourceManagementScenarioID) -> Void
    let dismissPresentedScenario: () -> Void
    let updateAddFeedURL: (String) -> Void
    let selectAddFeedFolderPlacement: (SourceManagementFolderPlacement) -> Void
    let startCreateFolderFromAddFeed: () -> Void
    let handleAddFeedPrimaryAction: () -> Void
    let updateCreateFolderName: (String) -> Void
    let submitCreateFolder: () -> Void
    let selectMoveSourceFeed: (UUID) -> Void
    let selectMoveSourcePlacement: (SourceManagementFolderPlacement) -> Void
    let submitMoveSource: () -> Void
}

struct SourceManagementScreenView: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    @Environment(\.appDependencies) private var dependencies
    @Environment(AppState.self) private var appState
    @State private var controller: SourceManagementScreenController
    let dismiss: () -> Void
    let launchContext: SourceManagementScreenLaunchContext

    init(
        dismiss: @escaping () -> Void,
        launchContext: SourceManagementScreenLaunchContext = .entry,
        previewScreenState: SourceManagementScreenState? = nil
    ) {
        self.dismiss = dismiss
        self.launchContext = launchContext
        self._controller = State(
            initialValue: SourceManagementScreenController(previewScreenState: previewScreenState)
        )
    }

    var body: some View {
        let viewState = controller.viewState()

        NavigationStack {
            List {
                Section {
                    summarySection(viewState.summary)
                }

                ForEach(viewState.sections) { section in
                    Section {
                        ForEach(section.items) { item in
                            Button {
                                actionHandlers.selectScenario(item.id)
                            } label: {
                                SourceManagementScreenItemCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(section.title)
                    } footer: {
                        if let footer = section.footer {
                            Text(footer)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(appThemeVariant.primaryBackground)
            .navigationTitle("Add Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: actionHandlers.dismiss)
                }
            }
            .navigationDestination(item: presentedDestinationBinding) { destination in
                switch destination {
                case .addFeed(let addFeed):
                    SourceManagementAddFeedView(
                        presentation: addFeed,
                        urlBinding: addFeedURLBinding,
                        selectPlacement: actionHandlers.selectAddFeedFolderPlacement,
                        startCreateFolder: actionHandlers.startCreateFolderFromAddFeed,
                        handlePrimaryAction: actionHandlers.handleAddFeedPrimaryAction
                    )
                case .createFolder(let createFolder):
                    SourceManagementCreateFolderView(
                        presentation: createFolder,
                        nameBinding: createFolderNameBinding,
                        submit: actionHandlers.submitCreateFolder
                    )
                case .moveSource(let moveSource):
                    SourceManagementMoveSourceView(
                        presentation: moveSource,
                        selectFeed: actionHandlers.selectMoveSourceFeed,
                        selectPlacement: actionHandlers.selectMoveSourcePlacement,
                        submit: actionHandlers.submitMoveSource
                    )
                case .placeholder(let placeholder):
                    SourceManagementScenarioPlaceholderView(destination: placeholder)
                }
            }
            .task(id: launchContext) {
                controller.handleLaunchContext(launchContext, dependencies: dependencies)
            }
        }
    }

    private var actionHandlers: SourceManagementScreenActionHandlers {
        SourceManagementScreenActionHandlers(
            dismiss: dismiss,
            selectScenario: { scenarioID in
                controller.handleScenarioSelection(
                    scenarioID,
                    dependencies: dependencies
                )
            },
            dismissPresentedScenario: {
                controller.dismissPresentedScenario()
            },
            updateAddFeedURL: { value in
                controller.handleAddFeedURLChange(value)
            },
            selectAddFeedFolderPlacement: { placement in
                controller.handleAddFeedFolderPlacementSelection(placement)
            },
            startCreateFolderFromAddFeed: {
                controller.startCreateFolderFromAddFeed(dependencies: dependencies)
            },
            handleAddFeedPrimaryAction: {
                Task {
                    await controller.handleAddFeedPrimaryAction(
                        dependencies: dependencies,
                        appState: appState
                    )
                }
            },
            updateCreateFolderName: { value in
                controller.handleCreateFolderNameChange(value)
            },
            submitCreateFolder: {
                controller.submitCreateFolder(
                    dependencies: dependencies,
                    appState: appState
                )
            },
            selectMoveSourceFeed: { feedID in
                controller.handleMoveSourceFeedSelection(feedID)
            },
            selectMoveSourcePlacement: { placement in
                controller.handleMoveSourcePlacementSelection(placement)
            },
            submitMoveSource: {
                controller.submitMoveSource(dependencies: dependencies)
            }
        )
    }

    private var presentedDestinationBinding: Binding<SourceManagementScreenDestinationPresentation?> {
        Binding(
            get: { controller.screenState.presentedDestination },
            set: { destination in
                if let destination {
                    controller.handleScenarioSelection(destination.id, dependencies: dependencies)
                } else {
                    controller.dismissPresentedScenario()
                }
            }
        )
    }

    private var addFeedURLBinding: Binding<String> {
        Binding(
            get: {
                switch controller.viewState().presentedDestination {
                case .addFeed(let presentation):
                    return presentation.urlInput
                case .moveSource, .placeholder, .createFolder, .none:
                    return ""
                }
            },
            set: { value in
                actionHandlers.updateAddFeedURL(value)
            }
        )
    }

    private var createFolderNameBinding: Binding<String> {
        Binding(
            get: {
                switch controller.viewState().presentedDestination {
                case .addFeed, .moveSource, .placeholder, .none:
                    return ""
                case .createFolder(let presentation):
                    return presentation.nameInput
                }
            },
            set: { value in
                actionHandlers.updateCreateFolderName(value)
            }
        )
    }

    private func summarySection(_ summary: SourceManagementScreenSummaryPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(summary.title)
                .font(.headline)

            Text(summary.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct SourceManagementScreenItemCard: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    let item: SourceManagementScreenItemPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(appThemeVariant.secondaryBackground)
                    .frame(width: 40, height: 40)

                Image(systemName: item.systemImageName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(item.badgeTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(appThemeVariant.secondaryBackground)
                        .clipShape(Capsule())
                }

                Text(item.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct SourceManagementAddFeedView: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    let presentation: SourceManagementAddFeedPresentation
    let urlBinding: Binding<String>
    let selectPlacement: (SourceManagementFolderPlacement) -> Void
    let startCreateFolder: () -> Void
    let handlePrimaryAction: () -> Void

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(presentation.summaryTitle)
                        .font(.headline)

                    Text(presentation.summaryDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                TextField(
                    presentation.urlPrompt,
                    text: urlBinding,
                    prompt: Text("https://example.com/feed.xml")
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textContentType(.URL)
                .submitLabel(.done)
                .onSubmit(handlePrimaryAction)

                if let validationMessage = presentation.validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Feed URL")
            } footer: {
                Text("The URL is validated locally before any network preview starts.")
            }

            if let normalizedURL = presentation.normalizedURL {
                Section("Normalized URL") {
                    Text(normalizedURL)
                        .textSelection(.enabled)
                }
            }

            if let preview = presentation.preview {
                Section("Preview Metadata") {
                    SourceManagementAddFeedPreviewCard(preview: preview)
                }
            }

            if presentation.placementOptions.isEmpty == false {
                Section {
                    ForEach(presentation.placementOptions) { option in
                        Button {
                            selectPlacement(option.placement)
                        } label: {
                            SourceManagementFolderPlacementRow(option: option)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(presentation.placementTitle)
                } footer: {
                    Text(presentation.placementDescription)
                }
            }

            if let createFolderActionTitle = presentation.createFolderActionTitle {
                Section {
                    Button(createFolderActionTitle, action: startCreateFolder)
                } footer: {
                    Text("Create a new folder first when the destination you need does not exist yet.")
                }
            }

            if let status = presentation.status {
                Section {
                    SourceManagementAddFeedStatusCard(status: status)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(appThemeVariant.primaryBackground)
        .navigationTitle(presentation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(presentation.primaryActionTitle, action: handlePrimaryAction)
                    .disabled(presentation.isPrimaryActionEnabled == false)
            }
        }
    }
}

private struct SourceManagementFolderPlacementRow: View {
    let option: SourceManagementFolderPlacementOptionPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: option.isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(option.isSelected ? Color.accentColor : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(option.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                if let subtitle = option.subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct SourceManagementAddFeedPreviewCard: View {
    let preview: SourceManagementAddFeedPreviewPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(preview.title)
                .font(.body.weight(.semibold))

            LabeledContent("Kind", value: preview.kindTitle)

            if let subtitle = preview.subtitle {
                LabeledContent("Subtitle", value: subtitle)
            }

            LabeledContent("Resolved Feed URL", value: preview.resolvedFeedURL)

            if let siteURL = preview.siteURL {
                LabeledContent("Site URL", value: siteURL)
            }

            if let iconURL = preview.iconURL {
                LabeledContent("Icon URL", value: iconURL)
            }

            if let existingFeedNotice = preview.existingFeedNotice {
                Text(existingFeedNotice)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            if let diagnosticsSummary = preview.diagnosticsSummary {
                Text(diagnosticsSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SourceManagementAddFeedStatusCard: View {
    let status: SourceManagementAddFeedStatusPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusIconName)
                .foregroundStyle(statusColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(status.title)
                    .font(.body.weight(.semibold))

                if let detail = status.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch status.kind {
        case .success:
            .green
        case .warning:
            .orange
        case .failure:
            .red
        }
    }

    private var statusIconName: String {
        switch status.kind {
        case .success:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .failure:
            "xmark.octagon.fill"
        }
    }
}

private struct SourceManagementCreateFolderView: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    let presentation: SourceManagementCreateFolderPresentation
    let nameBinding: Binding<String>
    let submit: () -> Void

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(presentation.summaryTitle)
                        .font(.headline)

                    Text(presentation.summaryDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                TextField(
                    presentation.namePrompt,
                    text: nameBinding,
                    prompt: Text("Examples: News, Tech, Design")
                )
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(submit)

                if let validationMessage = presentation.validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Folder Name")
            } footer: {
                Text("Folder names stay unique within the current sidebar grouping.")
            }

            Section {
                Text(presentation.placementDescription)
            } header: {
                Text("Sidebar Placement")
            }

            if let feedback = presentation.feedback {
                Section {
                    SourceManagementCreateFolderFeedbackCard(feedback: feedback)
                }
            }

            if presentation.existingFolders.isEmpty == false {
                Section("Existing Folders") {
                    ForEach(presentation.existingFolders) { folder in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(folder.name)
                                    .font(.body.weight(.semibold))

                                Text("Sidebar position #\(folder.sortOrder + 1)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(folder.feedCount == 1 ? "1 feed" : "\(folder.feedCount) feeds")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(appThemeVariant.primaryBackground)
        .navigationTitle(presentation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(presentation.primaryActionTitle, action: submit)
                    .disabled(presentation.isPrimaryActionEnabled == false)
            }
        }
    }
}

private struct SourceManagementMoveSourceView: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    let presentation: SourceManagementMoveSourcePresentation
    let selectFeed: (UUID) -> Void
    let selectPlacement: (SourceManagementFolderPlacement) -> Void
    let submit: () -> Void

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(presentation.summaryTitle)
                        .font(.headline)

                    Text(presentation.summaryDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if let emptyStateTitle = presentation.emptyStateTitle,
               let emptyStateDescription = presentation.emptyStateDescription {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(emptyStateTitle)
                            .font(.body.weight(.semibold))

                        Text(emptyStateDescription)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Section("Select Source") {
                    ForEach(presentation.feeds) { feed in
                        Button {
                            selectFeed(feed.id)
                        } label: {
                            SourceManagementMoveSourceFeedRow(feed: feed)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    ForEach(presentation.placementOptions) { option in
                        Button {
                            selectPlacement(option.placement)
                        } label: {
                            SourceManagementFolderPlacementRow(option: option)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(presentation.placementTitle)
                } footer: {
                    Text(presentation.placementDescription)
                }
            }

            if let feedback = presentation.feedback {
                Section {
                    SourceManagementMoveSourceFeedbackCard(feedback: feedback)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(appThemeVariant.primaryBackground)
        .navigationTitle(presentation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(presentation.primaryActionTitle, action: submit)
                    .disabled(presentation.isPrimaryActionEnabled == false)
            }
        }
    }
}

private struct SourceManagementMoveSourceFeedRow: View {
    let feed: SourceManagementMoveSourceFeedPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: feed.isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(feed.isSelected ? Color.accentColor : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(feed.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(feed.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("Current location: \(feed.currentPlacementTitle)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct SourceManagementMoveSourceFeedbackCard: View {
    let feedback: SourceManagementMoveSourceFeedbackPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: feedback.kind == .success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(feedback.kind == .success ? .green : .red)

            VStack(alignment: .leading, spacing: 4) {
                Text(feedback.title)
                    .font(.body.weight(.semibold))

                if let detail = feedback.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SourceManagementCreateFolderFeedbackCard: View {
    let feedback: SourceManagementCreateFolderFeedbackPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: feedback.kind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(feedback.kind == .success ? .green : .orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(feedback.title)
                    .font(.body.weight(.semibold))

                if let detail = feedback.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SourceManagementScenarioPlaceholderView: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    let destination: SourceManagementScenarioPlaceholderPresentation

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(destination.summaryTitle)
                        .font(.headline)

                    Text(destination.summaryDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("What This Flow Will Cover") {
                ForEach(destination.steps, id: \.self) { step in
                    Text(step)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(appThemeVariant.primaryBackground)
        .navigationTitle(destination.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
