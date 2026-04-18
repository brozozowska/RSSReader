import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appDependencies) private var dependencies
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    var body: some View {
        let detailDestination = ReadingShellDetailNavigationState.detailDestination(
            route: appState.selectedDetailRoute,
            selectedArticleID: appState.selectedArticleID
        )
        let sidebarSelection = Binding<SidebarSelection?>(
            get: { appState.selectedSidebarSelection },
            set: { appState.selectReadingSource($0) }
        )
        let articleSelection = Binding<UUID?>(
            get: { appState.selectedArticleID },
            set: { dependencies.selectArticle(id: $0, using: appState) }
        )

        NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
            SidebarView(selection: sidebarSelection)
        } content: {
            ArticleListView(
                selectedSidebarSelection: appState.selectedSidebarSelection,
                selectedSourcesFilter: appState.selectedSourcesFilter,
                reloadID: appState.articleListReloadID,
                showsBackButton: ReadingShellCompactNavigationState.showsArticlesBackButton(
                    horizontalSizeClass: horizontalSizeClass,
                    sourceSelection: appState.selectedSidebarSelection
                ),
                navigateBackToSources: { preferredCompactColumn = .sidebar },
                previewScreenState: nil,
                selection: articleSelection
            )
        } detail: {
            switch detailDestination {
            case .none:
                if horizontalSizeClass == .compact {
                    EmptyView()
                } else {
                    ReaderView(
                        articleID: nil,
                        showsBackButton: false,
                        navigateBackToArticles: {}
                    )
                }
            case .article(let articleID):
                ReaderView(
                    articleID: articleID,
                    showsBackButton: ArticleScreenNavigationState.showsBackButton(
                        horizontalSizeClass: horizontalSizeClass,
                        articleSelection: articleID
                    ),
                    navigateBackToArticles: { appState.selectedArticleID = nil }
                )
            case .webView(let route):
                WebViewScreenView(
                    route: route,
                    closeWebView: { appState.dismissPresentedWebView() }
                )
            }
        }
        .sheet(isPresented: settingsPresentationBinding) {
            SettingsScreenSheet(
                dismiss: { dependencies.dismissSettings(using: appState) }
            )
        }
        .onAppear(perform: syncPreferredCompactColumn)
        .onChange(of: appState.selectedSidebarSelection) { _, _ in
            syncPreferredCompactColumn()
        }
        .onChange(of: appState.selectedArticleID) { _, _ in
            syncPreferredCompactColumn()
        }
    }

    private var settingsPresentationBinding: Binding<Bool> {
        Binding(
            get: { appState.isPresentingSettingsScreen },
            set: { isPresented in
                if isPresented {
                    appState.presentSettingsScreen()
                } else {
                    appState.dismissSettingsScreen()
                }
            }
        )
    }

    private func syncPreferredCompactColumn() {
        preferredCompactColumn = ReadingShellCompactNavigationState.preferredCompactColumn(
            sourceSelection: appState.selectedSidebarSelection,
            articleSelection: appState.selectedArticleID
        )
    }
}

private struct SettingsScreenSheet: View {
    @Environment(\.appDependencies) private var dependencies
    let dismiss: () -> Void
    @State private var settingsSnapshot = AppSettingsSnapshot()

    var body: some View {
        let sections = SettingsScreenPresentationBuilder.buildSections(from: settingsSnapshot)

        NavigationStack {
            List {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.items) { item in
                            itemRow(item)
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
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: dismiss)
                }
            }
            .task {
                loadSettingsIfNeeded()
            }
        }
    }

    @ViewBuilder
    private func itemRow(_ item: SettingsScreenItemPresentation) -> some View {
        switch item {
        case .toggle(let toggleItem):
            Toggle(isOn: .constant(toggleItem.isOn)) {
                itemLabel(
                    title: toggleItem.title,
                    subtitle: toggleItem.subtitle
                )
            }
            .disabled(true)
        case .picker(let pickerItem):
            LabeledContent {
                Text(pickerItem.selectedValueTitle)
                    .foregroundStyle(.secondary)
            } label: {
                itemLabel(
                    title: pickerItem.title,
                    subtitle: pickerItem.subtitle
                )
            }
        case .navigationLink(let navigationItem):
            HStack(spacing: 12) {
                itemLabel(
                    title: navigationItem.title,
                    subtitle: navigationItem.subtitle
                )

                Spacer(minLength: 12)

                if let valueTitle = navigationItem.valueTitle {
                    Text(valueTitle)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .opacity(navigationItem.isEnabled ? 1 : 0.6)
        case .statusRow(let statusItem):
            LabeledContent {
                Text(statusItem.valueTitle)
                    .foregroundStyle(.secondary)
            } label: {
                itemLabel(
                    title: statusItem.title,
                    subtitle: statusItem.subtitle
                )
            }
        }
    }

    private func itemLabel(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .foregroundStyle(.primary)

            if let subtitle, subtitle.isEmpty == false {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadSettingsIfNeeded() {
        guard let appSettingsService = dependencies.appSettingsService else { return }

        do {
            settingsSnapshot = try appSettingsService.fetchSettings()
        } catch {
            dependencies.logger.error("Failed to load settings snapshot for settings sheet: \(error)")
        }
    }
}
