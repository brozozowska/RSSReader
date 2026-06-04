extension SettingsScreenPresentationBuilder {
    static func articleListSection(from input: SettingsScreenInput) -> SettingsScreenSectionPresentation {
        SettingsScreenSectionPresentation(
            id: .articleList,
            title: "Article List",
            footer: "\"None\" removes an article from the list when it disappears from its feed. Other options keep the article for the selected time after it disappears.",
            items: [
                .picker(
                    SettingsPickerItemPresentation(
                        id: .unreadArticleSortOrder,
                        title: "Sort Unread Articles",
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
                        title: "Ask Before Marking All Read",
                        subtitle: "Show a confirmation before marking all visible articles as read.",
                        isOn: input.askBeforeMarkingAllAsRead
                    )
                ),
                .picker(
                    SettingsPickerItemPresentation(
                        id: .articleRetentionPolicy,
                        title: "Keep Archived Articles",
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
