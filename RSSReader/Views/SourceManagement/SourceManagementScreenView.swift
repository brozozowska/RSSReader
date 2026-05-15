import SwiftUI
import UIKit

struct SourceManagementScreenView: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    @Environment(\.appDependencies) private var dependencies
    @Environment(AppState.self) private var appState
    @State private var controller: SourceManagementScreenController
    @State private var destinationPath: [SourceManagementScenarioID] = []
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
        let navigator = SourceManagementScreenNavigator(
            controller: controller,
            dependencies: dependencies,
            appState: appState,
            dismiss: dismiss,
            showsDirectLaunchCloseControl: launchContext.opensDirectDestination,
            destinationPath: $destinationPath
        )

        NavigationStack(path: destinationPathBinding) {
            List {
                Section {
                    summarySection(viewState.summary)
                }

                ForEach(viewState.sections) { section in
                    Section {
                        ForEach(section.items) { item in
                            Button {
                                navigator.selectScenario(item.id)
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
                    SourceManagementCloseButton(
                        accessibilityLabel: "Close Add Source",
                        action: navigator.dismiss
                    )
                }
            }
            .navigationDestination(for: SourceManagementScenarioID.self) { scenarioID in
                navigator.destinationView(for: scenarioID)
            }
            .task(id: launchContext) {
                navigator.handleLaunchContext(launchContext)
            }
        }
    }

    private var destinationPathBinding: Binding<[SourceManagementScenarioID]> {
        Binding(
            get: { destinationPath },
            set: { newPath in
                let oldPath = destinationPath
                destinationPath = newPath

                if newPath.count < oldPath.count {
                    controller.dismissPresentedScenario()
                }

                if let activeScenario = newPath.last {
                    controller.screenState.presentScenario(activeScenario)
                }
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

private struct SourceManagementScreenNavigator {
    let controller: SourceManagementScreenController
    let dependencies: AppDependencies
    let appState: AppState
    let dismiss: () -> Void
    let showsDirectLaunchCloseControl: Bool
    @Binding var destinationPath: [SourceManagementScenarioID]

    func handleLaunchContext(_ launchContext: SourceManagementScreenLaunchContext) {
        controller.handleLaunchContext(launchContext, dependencies: dependencies)
        switch launchContext {
        case .entry:
            return
        case .editFeed:
            destinationPath = [.addFeed]
        case .editFolder:
            destinationPath = [.createFolder]
        case .organizeFeed:
            destinationPath = [.moveSource]
        }
    }

    func selectScenario(_ scenarioID: SourceManagementScenarioID) {
        controller.handleScenarioSelection(
            scenarioID,
            dependencies: dependencies
        )
        destinationPath = [scenarioID]
    }

    func startCreateFolderFromAddFeed() {
        controller.startCreateFolderFromAddFeed(dependencies: dependencies)
        destinationPath.append(.createFolder)
    }

    func submitCreateFolder() {
        let wasNestedAddFeedFolderCreation = destinationPath == [.addFeed, .createFolder]
        controller.submitCreateFolder(
            dependencies: dependencies,
            appState: appState
        )

        if wasNestedAddFeedFolderCreation,
           controller.screenState.presentedDestination?.id == .addFeed {
            destinationPath = [.addFeed]
        }
    }

    @ViewBuilder
    func destinationView(
        for scenarioID: SourceManagementScenarioID
    ) -> some View {
        let destination = controller.screenState.destinationPresentation(for: scenarioID)

        switch destination {
        case .addFeed(let addFeed):
            SourceManagementAddFeedView(
                presentation: addFeed,
                urlBinding: addFeedURLBinding,
                displayNameBinding: addFeedDisplayNameBinding,
                showsCloseControl: showsDirectLaunchCloseControl,
                selectPlacement: { placement in
                    controller.handleAddFeedFolderPlacementSelection(placement)
                },
                startCreateFolder: {
                    startCreateFolderFromAddFeed()
                },
                handlePrimaryAction: {
                    Task {
                        await controller.handleAddFeedPrimaryAction(
                            dependencies: dependencies,
                            appState: appState
                        )
                    }
                },
                handlePreviewAction: {
                    Task {
                        await controller.handleAddFeedPreviewAction(
                            dependencies: dependencies
                        )
                    }
                },
                dismiss: dismiss
            )
        case .createFolder(let createFolder):
            SourceManagementCreateFolderView(
                presentation: createFolder,
                nameBinding: createFolderNameBinding,
                showsCloseControl: showsDirectLaunchCloseControl,
                submit: {
                    submitCreateFolder()
                },
                dismiss: dismiss
            )
        case .moveSource(let moveSource):
            SourceManagementMoveSourceView(
                presentation: moveSource,
                showsCloseControl: showsDirectLaunchCloseControl,
                selectFeed: { feedID in
                    controller.handleMoveSourceFeedSelection(feedID)
                },
                selectPlacement: { placement in
                    controller.handleMoveSourcePlacementSelection(placement)
                },
                submit: {
                    controller.submitMoveSource(
                        dependencies: dependencies,
                        appState: appState
                    )
                },
                dismiss: dismiss
            )
        }
    }

    private var addFeedURLBinding: Binding<String> {
        Binding(
            get: { controller.screenState.addFeedURLInput() },
            set: { value in
                controller.handleAddFeedURLChange(value)
            }
        )
    }

    private var addFeedDisplayNameBinding: Binding<String> {
        Binding(
            get: { controller.screenState.addFeedDisplayNameInput() },
            set: { value in
                controller.handleAddFeedDisplayNameChange(value)
            }
        )
    }

    private var createFolderNameBinding: Binding<String> {
        Binding(
            get: { controller.screenState.createFolderNameInput() },
            set: { value in
                controller.handleCreateFolderNameChange(value)
            }
        )
    }
}

private struct SourceManagementCloseButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
        }
        .accessibilityLabel(accessibilityLabel)
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
    let displayNameBinding: Binding<String>
    let showsCloseControl: Bool
    let selectPlacement: (SourceManagementFolderPlacement) -> Void
    let startCreateFolder: () -> Void
    let handlePrimaryAction: () -> Void
    let handlePreviewAction: () -> Void
    let dismiss: () -> Void

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
                    prompt: Text("example.com/feed.xml")
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textContentType(.URL)
                .submitLabel(.done)
                .onSubmit(handlePreviewAction)

                if let validationMessage = presentation.validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Feed URL")
            } footer: {
                Text("Use a website address or a direct RSS / Atom feed link.")
            }

            if presentation.showsDisplayNameInput {
                Section {
                    TextField(
                        presentation.displayNamePrompt,
                        text: displayNameBinding,
                        prompt: Text("Source name")
                    )
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(handlePrimaryAction)
                } header: {
                    Text("Display Name")
                } footer: {
                    Text(presentation.displayNameFooter)
                }
            }

            if presentation.isLoadingPreview {
                Section {
                    SourceManagementCheckingSourceView()
                } header: {
                    Text("Source Preview")
                }
            } else if let preview = presentation.preview {
                Section("Source Preview") {
                    SourceManagementAddFeedPreviewCard(preview: preview)
                }
            } else if let status = presentation.status,
                      status.kind == .failure {
                Section {
                    SourceManagementFeedbackCard(
                        feedback: .init(status: status)
                    )
                } header: {
                    Text("Source Preview")
                } footer: {
                    Text("Try a different website address or a direct RSS / Atom feed link.")
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
                    Text("Create a folder now if this source should live in a new group.")
                }
            }

            if let status = presentation.status,
               status.kind != .failure || presentation.preview != nil {
                Section {
                    SourceManagementFeedbackCard(
                        feedback: .init(status: status)
                    )
                }
            }

            if presentation.isLoadingPreview == false,
               presentation.preview == nil,
               presentation.status?.kind != .failure {
                Section {
                    Button(action: handlePreviewAction) {
                        Text("Preview Feed")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(presentation.validationMessage != nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(appThemeVariant.primaryBackground)
        .navigationTitle(presentation.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(showsCloseControl)
        .toolbar {
            if showsCloseControl {
                ToolbarItem(placement: .cancellationAction) {
                    SourceManagementCloseButton(
                        accessibilityLabel: "Close \(presentation.title)",
                        action: dismiss
                    )
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(action: handlePrimaryAction) {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
                .accessibilityLabel(presentation.primaryActionTitle)
                .disabled(presentation.isConfirmationActionEnabled == false)
            }
        }
    }
}

private struct SourceManagementCheckingSourceView: View {
    var body: some View {
        HStack {
            Spacer()
            HStack(spacing: 8) {
                SourceManagementActivityIndicator()
                    .frame(width: 18, height: 18)

                Text("Checking Source...")
            }
            .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct SourceManagementActivityIndicator: UIViewRepresentable {
    func makeUIView(context: Context) -> UIActivityIndicatorView {
        let view = UIActivityIndicatorView(style: .medium)
        view.color = .secondaryLabel
        view.hidesWhenStopped = false
        view.startAnimating()
        return view
    }

    func updateUIView(_ uiView: UIActivityIndicatorView, context: Context) {
        if uiView.isAnimating == false {
            uiView.startAnimating()
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

            if let trailingValue = option.trailingValue {
                Text(trailingValue)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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

            LabeledContent("Feed Type", value: preview.kindTitle)

            if let subtitle = preview.subtitle {
                LabeledContent("Description", value: subtitle)
            }

            LabeledContent("Feed Address", value: preview.resolvedFeedURL)

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

private struct SourceManagementCreateFolderView: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    let presentation: SourceManagementCreateFolderPresentation
    let nameBinding: Binding<String>
    let showsCloseControl: Bool
    let submit: () -> Void
    let dismiss: () -> Void

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
                Text("Use a name that is easy to recognize in the source list.")
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
            } else if presentation.existingFolders.isEmpty == false {
                Section {
                    ForEach(presentation.existingFolders) { folder in
                        HStack(alignment: .firstTextBaseline) {
                            Text(folder.name)
                                .font(.body.weight(.semibold))

                            Spacer()

                            Text(folder.feedCount == 1 ? "1 feed" : "\(folder.feedCount) feeds")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Existing Folders")
                }
            }

            if let feedback = presentation.feedback {
                Section {
                    SourceManagementFeedbackCard(
                        feedback: .init(createFolderFeedback: feedback)
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(appThemeVariant.primaryBackground)
        .navigationTitle(presentation.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(showsCloseControl)
        .toolbar {
            if showsCloseControl {
                ToolbarItem(placement: .cancellationAction) {
                    SourceManagementCloseButton(
                        accessibilityLabel: "Close \(presentation.title)",
                        action: dismiss
                    )
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(action: submit) {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
                .accessibilityLabel(presentation.primaryActionTitle)
                .disabled(presentation.isPrimaryActionEnabled == false)
            }
        }
    }
}

private struct SourceManagementMoveSourceView: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    let presentation: SourceManagementMoveSourcePresentation
    let showsCloseControl: Bool
    let selectFeed: (UUID) -> Void
    let selectPlacement: (SourceManagementFolderPlacement) -> Void
    let submit: () -> Void
    let dismiss: () -> Void

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
                }
            }

            if let feedback = presentation.feedback {
                Section {
                    SourceManagementFeedbackCard(
                        feedback: .init(moveSourceFeedback: feedback)
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(appThemeVariant.primaryBackground)
        .navigationTitle(presentation.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(showsCloseControl)
        .toolbar {
            if showsCloseControl {
                ToolbarItem(placement: .cancellationAction) {
                    SourceManagementCloseButton(
                        accessibilityLabel: "Close \(presentation.title)",
                        action: dismiss
                    )
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(action: submit) {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
                .accessibilityLabel(presentation.primaryActionTitle)
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

private struct SourceManagementFeedbackCard: View {
    let feedback: SourceManagementFeedbackCardPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: feedback.tone.systemImageName)
                .foregroundStyle(feedback.tone.color)

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

private struct SourceManagementFeedbackCardPresentation {
    let title: String
    let detail: String?
    let tone: SourceManagementFeedbackTone

    init(status: SourceManagementAddFeedStatusPresentation) {
        self.title = status.title
        self.detail = status.detail
        switch status.kind {
        case .success:
            self.tone = .success
        case .warning:
            self.tone = .warning
        case .failure:
            self.tone = .failure
        }
    }

    init(createFolderFeedback: SourceManagementCreateFolderFeedbackPresentation) {
        self.title = createFolderFeedback.title
        self.detail = createFolderFeedback.detail
        switch createFolderFeedback.kind {
        case .success:
            self.tone = .success
        case .failure:
            self.tone = .failure
        }
    }

    init(moveSourceFeedback: SourceManagementMoveSourceFeedbackPresentation) {
        self.title = moveSourceFeedback.title
        self.detail = moveSourceFeedback.detail
        switch moveSourceFeedback.kind {
        case .success:
            self.tone = .success
        case .failure:
            self.tone = .failure
        }
    }
}

private enum SourceManagementFeedbackTone {
    case success
    case warning
    case failure

    var color: Color {
        switch self {
        case .success:
            .green
        case .warning:
            .orange
        case .failure:
            .red
        }
    }

    var systemImageName: String {
        switch self {
        case .success:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .failure:
            "xmark.octagon.fill"
        }
    }
}
