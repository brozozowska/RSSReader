extension SettingsScreenPresentationBuilder {
    static func articleListSection(from input: SettingsScreenInput) -> SettingsScreenSectionPresentation {
        SettingsScreenSectionPresentation(
            id: .articleList,
            title: SettingsLocalization.articleListSectionTitle,
            footer: SettingsLocalization.articleListSectionFooter,
            items: [
                .picker(
                    SettingsPickerItemPresentation(
                        id: .unreadArticleSortOrder,
                        title: SettingsLocalization.sortUnreadArticlesTitle,
                        subtitle: nil,
                        selectedValueTitle: SettingsScreenPresentationFormatter.unreadArticleSortOrderTitle(input.unreadArticleSortOrder),
                        options: UnreadArticleSortOrder.allCases.map { order in
                            SettingsPickerOptionPresentation(
                                id: order.rawValue,
                                title: SettingsScreenPresentationFormatter.unreadArticleSortOrderTitle(order),
                                isSelected: input.unreadArticleSortOrder == order
                            )
                        }
                    )
                ),
                .toggle(
                    SettingsToggleItemPresentation(
                        id: .askBeforeMarkingAllAsRead,
                        title: SettingsLocalization.askBeforeMarkingAllReadTitle,
                        subtitle: SettingsLocalization.askBeforeMarkingAllReadSubtitle,
                        isOn: input.askBeforeMarkingAllAsRead
                    )
                ),
                .picker(
                    SettingsPickerItemPresentation(
                        id: .articleRetentionPolicy,
                        title: SettingsLocalization.keepArchivedArticlesTitle,
                        subtitle: nil,
                        selectedValueTitle: SettingsScreenPresentationFormatter.articleRetentionPolicyTitle(input.articleRetentionPolicy),
                        options: ArticleRetentionPolicy.allCases.map { policy in
                            SettingsPickerOptionPresentation(
                                id: policy.rawValue,
                                title: SettingsScreenPresentationFormatter.articleRetentionPolicyTitle(policy),
                                isSelected: input.articleRetentionPolicy == policy
                            )
                        }
                    )
                )
            ]
        )
    }
}
