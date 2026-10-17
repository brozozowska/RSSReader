import SwiftUI
import UIKit

/// Owns only the existing List's viewport. Queries and pagination stay with the screen controller.
@MainActor
final class ArticleListReaderScrollCoordinator {
    private weak var list: UICollectionView?
    private weak var layoutView: UIView?
    private var sessionID: UUID?
    private var sections: [ArticlesDaySection] = []
    private var target: (id: UUID, direction: ReaderAdjacentArticleNavigationDirection)?
    private var isReconciling = false

    func reset() {
        sessionID = nil
        sections = []
        target = nil
    }

    func updateSnapshot(sessionID: UUID, sections: [ArticlesDaySection]) {
        if self.sessionID != sessionID {
            target = nil
        }
        self.sessionID = sessionID
        self.sections = sections
        if let target, sections.contains(where: { $0.articles.contains(where: { $0.id == target.id }) }) == false {
            self.target = nil
        }
    }

    func attach(to list: UICollectionView, layoutView: UIView) {
        self.list = list
        self.layoutView = layoutView
        reconcile()
    }

    func detach(from list: UICollectionView?) {
        if self.list === list {
            self.list = nil
            layoutView = nil
        }
    }

    func reveal(
        _ articleID: UUID,
        direction: ReaderAdjacentArticleNavigationDirection,
        sessionID: UUID,
        sections: [ArticlesDaySection]
    ) {
        updateSnapshot(sessionID: sessionID, sections: sections)
        target = nil
        guard sections.contains(where: { $0.articles.contains(where: { $0.id == articleID }) }) else { return }
        target = (articleID, direction)
        reconcile()
    }

    private func nativeSnapshotMatches(_ list: UICollectionView) -> Bool {
        list.numberOfSections >= sections.count
            && sections.indices.allSatisfy { list.numberOfItems(inSection: $0) == sections[$0].articles.count }
    }

    func reconcile() {
        guard isReconciling == false, let list, let target else { return }
        let revealSessionID = sessionID
        isReconciling = true
        defer { isReconciling = false }
        if list.window == nil || nativeSnapshotMatches(list) == false {
            // A covered SwiftUI List defers updates, including appended pages.
            // Public UIView measurement flushes its hosting layout even off-screen.
            // No query, temporary window, native datasource write or timed retry.
            var ancestor = list.superview
            while let current = ancestor {
                _ = current.sizeThatFits(current.bounds.size)
                current.setNeedsLayout()
                current.layoutIfNeeded()
                if current === layoutView { break }
                ancestor = current.superview
            }
        }
        guard sessionID == revealSessionID, self.target?.id == target.id, self.list === list,
              let sectionIndex = sections.firstIndex(where: { $0.articles.contains(where: { $0.id == target.id }) }),
              let rowIndex = sections[sectionIndex].articles.firstIndex(where: { $0.id == target.id }) else { return }
        // SwiftUI may not have committed an appended page yet. Never address a
        // native index path unless its entire section shape matches this snapshot.
        // The bridge retries during layout, before the returning list is displayed.
        guard nativeSnapshotMatches(list) else { return }
        let path = IndexPath(item: rowIndex, section: sectionIndex)
        // Self-sizing cells can refine estimated geometry after the first move.
        // Keep correction bounded and use actual layout attributes each time.
        for _ in 0..<3 {
            list.layoutIfNeeded()
            guard let attributes = list.layoutAttributesForItem(at: path) else { return }
            let insets = list.adjustedContentInset
            var viewport = list.bounds.inset(by: insets)
            if let header = list.collectionViewLayout.layoutAttributesForSupplementaryView(
                ofKind: UICollectionView.elementKindSectionHeader,
                at: IndexPath(item: 0, section: sectionIndex)
            ), header.frame.minY <= viewport.minY + 1 {
                viewport.origin.y += header.frame.height
                viewport.size.height = max(0, viewport.height - header.frame.height)
            }
            let delta = ArticleListReaderRevealPolicy.scrollDelta(
                row: attributes.frame, viewport: viewport, direction: target.direction
            )
            guard abs(delta) > 0.5 else {
                self.target = nil
                return
            }
            let minimumY = -insets.top
            let maximumY = max(minimumY, list.contentSize.height - list.bounds.height + insets.bottom)
            let offsetY = min(maximumY, max(minimumY, list.contentOffset.y + delta))
            guard abs(offsetY - list.contentOffset.y) > 0.5 else {
                self.target = nil
                return
            }
            UIView.performWithoutAnimation {
                list.setContentOffset(CGPoint(x: list.contentOffset.x, y: offsetY), animated: false)
                list.layoutIfNeeded()
            }
        }
    }
}

enum ArticleListReaderRevealPolicy {
    static func scrollDelta(
        row: CGRect,
        viewport: CGRect,
        direction: ReaderAdjacentArticleNavigationDirection
    ) -> CGFloat {
        guard row.height > 0, viewport.height > 0 else { return 0 }
        if row.height > viewport.height {
            // A row taller than the viewport cannot be fully visible.
            return direction == .previous
                ? row.minY - viewport.minY
                : row.maxY - viewport.maxY
        }
        if row.minY < viewport.minY { return row.minY - viewport.minY }
        if row.maxY > viewport.maxY { return row.maxY - viewport.maxY }
        return 0
    }
}

struct ArticleListReaderScrollBridge: UIViewControllerRepresentable {
    let coordinator: ArticleListReaderScrollCoordinator
    let sessionID: UUID
    let sections: [ArticlesDaySection]

    func makeUIViewController(context: Context) -> Controller {
        Controller(coordinator: coordinator)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        coordinator.updateSnapshot(sessionID: sessionID, sections: sections)
        controller.install()
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: Void) {
        controller.detach()
    }

    final class Controller: UIViewController {
        let coordinator: ArticleListReaderScrollCoordinator
        private weak var list: UICollectionView?

        init(coordinator: ArticleListReaderScrollCoordinator) {
            self.coordinator = coordinator
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { nil }

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            install()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            install()
        }

        // Retain the weak link while Reader covers the list. A disappearance is
        // not the end of the list session, including an interactive Back cancel.
        func install() {
            var ancestor = parent
            while let current = ancestor {
                if current.navigationController?.viewControllers.contains(where: { $0 === current }) == true {
                    if let list = Self.findList(in: current.view) {
                        self.list = list
                        coordinator.attach(to: list, layoutView: current.view)
                    }
                    return
                }
                ancestor = current.parent
            }
        }

        func detach() {
            coordinator.detach(from: list)
            list = nil
        }

        private static func findList(in view: UIView) -> UICollectionView? {
            if let list = view as? UICollectionView { return list }
            for child in view.subviews {
                if let list = findList(in: child) { return list }
            }
            return nil
        }
    }
}
