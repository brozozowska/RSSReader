extension SettingsScreenPresentationBuilder {
    static func readingSection(from input: SettingsScreenInput) -> SettingsScreenSectionPresentation {
        SettingsScreenSectionPresentation(
            id: .reading,
            title: SettingsLocalization.readingSectionTitle,
            footer: SettingsLocalization.readingSectionFooter,
            items: [
                .picker(
                    SettingsPickerItemPresentation(
                        id: .articleOpeningMode,
                        title: SettingsLocalization.openArticlesTitle,
                        subtitle: nil,
                        selectedValueTitle: SettingsScreenPresentationFormatter.articleOpeningModeTitle(input.articleOpeningMode),
                        options: ArticleOpeningMode.allCases.map { mode in
                            SettingsPickerOptionPresentation(
                                id: mode.rawValue,
                                title: SettingsScreenPresentationFormatter.articleOpeningModeTitle(mode),
                                isSelected: input.articleOpeningMode == mode
                            )
                        }
                    )
                ),
                .picker(
                    SettingsPickerItemPresentation(
                        id: .articleSourceLinkOpeningPolicy,
                        title: SettingsLocalization.openOriginalArticleTitle,
                        subtitle: nil,
                        selectedValueTitle: SettingsScreenPresentationFormatter.articleSourceLinkOpeningPolicyTitle(input.articleSourceLinkOpeningPolicy),
                        options: ArticleSourceLinkOpeningPolicy.allCases.map { policy in
                            SettingsPickerOptionPresentation(
                                id: policy.rawValue,
                                title: SettingsScreenPresentationFormatter.articleSourceLinkOpeningPolicyTitle(policy),
                                isSelected: input.articleSourceLinkOpeningPolicy == policy
                            )
                        }
                    )
                ),
                .picker(
                    SettingsPickerItemPresentation(
                        id: .articleBodyLinkOpeningPolicy,
                        title: SettingsLocalization.openArticleLinksTitle,
                        subtitle: nil,
                        selectedValueTitle: SettingsScreenPresentationFormatter.articleBodyLinkOpeningPolicyTitle(input.articleBodyLinkOpeningPolicy),
                        options: ArticleBodyLinkOpeningPolicy.allCases.map { policy in
                            SettingsPickerOptionPresentation(
                                id: policy.rawValue,
                                title: SettingsScreenPresentationFormatter.articleBodyLinkOpeningPolicyTitle(policy),
                                isSelected: input.articleBodyLinkOpeningPolicy == policy
                            )
                        }
                    )
                ),
                .picker(
                    SettingsPickerItemPresentation(
                        id: .readerAdjacentNavigationControlsMode,
                        title: SettingsLocalization.adjacentNavigationTitle,
                        subtitle: nil,
                        selectedValueTitle: SettingsScreenPresentationFormatter.readerAdjacentNavigationControlsModeTitle(input.readerAdjacentNavigationControlsMode),
                        options: ReaderAdjacentNavigationControlsMode.allCases.map { mode in
                            SettingsPickerOptionPresentation(
                                id: mode.rawValue,
                                title: SettingsScreenPresentationFormatter.readerAdjacentNavigationControlsModeTitle(mode),
                                isSelected: input.readerAdjacentNavigationControlsMode == mode
                            )
                        }
                    )
                ),
                .toggle(
                    SettingsToggleItemPresentation(
                        id: .markAsReadOnOpen,
                        title: SettingsLocalization.markReadOnOpenTitle,
                        subtitle: SettingsLocalization.markReadOnOpenSubtitle,
                        isOn: input.markAsReadOnOpen
                    )
                )
            ]
        )
    }
}
