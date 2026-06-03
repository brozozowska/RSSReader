import SwiftUI

enum ReaderChromeUnderlayLayout {
    static let contentMargin: CGFloat = 16
    static let indicatorChromeSpacing: CGFloat = 12
    static let indicatorVisibilityThreshold: CGFloat = 0.18
}

extension ReaderAdjacentNavigationControlsMode {
    var showsToolbarControls: Bool {
        switch self {
        case .toolbarControlsOnly, .swipesAndToolbarControls:
            true
        case .swipesOnly:
            false
        }
    }

    var allowsAdjacentArticleSwipes: Bool {
        switch self {
        case .swipesOnly, .swipesAndToolbarControls:
            true
        case .toolbarControlsOnly:
            false
        }
    }
}
