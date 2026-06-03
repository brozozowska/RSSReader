extension SettingsScreenPresentationBuilder {
    static func readingSection(from input: SettingsScreenInput) -> SettingsScreenSectionPresentation {
        SettingsScreenSectionPresentation(
            id: .reading,
            title: "Reading",
            footer: "Choose whether articles from the list open in the feed reader or SFSafariViewController. Open Original Article controls the source web page; Open Article Links controls links inside article text.",
            items: [
                .picker(
                    SettingsPickerItemPresentation(
                        id: .articleOpeningMode,
                        title: "Open Articles",
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
                        title: "Open Original Article",
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
                        title: "Open Article Links",
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
                        title: "Adjacent Navigation",
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
                        title: "Mark Read on Open",
                        subtitle: "Automatically mark an article as read when it is opened.",
                        isOn: input.markAsReadOnOpen
                    )
                )
            ]
        )
    }
}
