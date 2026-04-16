//
//  ReaderSettingsViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 02.03.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import PSPDFKitUI
import RxSwift

final class ReaderSettingsViewController: UICollectionViewController {
    enum Row {
        case pageTransition
        case pageMode
        case scrollDirection
        case pageFitting
        case appearance
        case pageSpreads
        case fontManagement
    }

    let viewModel: ViewModel<ReaderSettingsActionHandler>
    private let rows: [Row]
    private let minimumPreferredContentSize: CGSize
    private let disposeBag: DisposeBag

    private var dataSource: UICollectionViewDiffableDataSource<Int, Row>!

    init(rows: [Row], minimumPreferredContentSize: CGSize, viewModel: ViewModel<ReaderSettingsActionHandler>) {
        self.rows = rows
        self.minimumPreferredContentSize = minimumPreferredContentSize
        self.viewModel = viewModel
        disposeBag = DisposeBag()

        super.init(collectionViewLayout: UICollectionViewFlowLayout())
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        preferredContentSize = minimumPreferredContentSize
        navigationController?.preferredContentSize = minimumPreferredContentSize

        setupNavigationBarIfNeeded()
        collectionView.allowsSelection = true
        collectionView.delegate = self
        collectionView.collectionViewLayout = createCollectionViewLayout()
        dataSource = createDataSource(for: collectionView)
        applySnapshot()

        viewModel.stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                self?.update(state: state)
            })
            .disposed(by: disposeBag)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePreferredContentSizeIfNeeded()

        func updatePreferredContentSizeIfNeeded() {
            // Use 80% of screen height to allow live preview of settings
            let screenHeight = UIScreen.main.bounds.height
            let maxHeight = screenHeight * 0.8
            let contentHeight = min(collectionView.collectionViewLayout.collectionViewContentSize.height, maxHeight)
            let finalHeight = max(contentHeight, minimumPreferredContentSize.height)
            let contentWidth = minimumPreferredContentSize.width
            let newPreferredContentSize = CGSize(width: contentWidth, height: finalHeight)
            guard preferredContentSize != newPreferredContentSize else { return }
            preferredContentSize = newPreferredContentSize
            navigationController?.preferredContentSize = newPreferredContentSize
        }
    }

    // MARK: - Actions

    private func update(state: ReaderSettingsState) {
        (navigationController ?? self).overrideUserInterfaceStyle = state.appearance.userInterfaceStyle
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        dataSource.apply(snapshot)
    }

    @objc private func done() {
        presentingViewController?.dismiss(animated: true, completion: nil)
    }

    // MARK: - Data Source

    private func createDataSource(for collectionView: UICollectionView) -> UICollectionViewDiffableDataSource<Int, Row> {
        let segmentedRegistration = self.segmentedRegistration
        let fontManagementRegistration = self.fontManagementRegistration
        return UICollectionViewDiffableDataSource<Int, Row>(collectionView: collectionView, cellProvider: { collectionView, indexPath, row in
            if row == .fontManagement {
                return collectionView.dequeueConfiguredReusableCell(using: fontManagementRegistration, for: indexPath, item: row)
            } else {
                return collectionView.dequeueConfiguredReusableCell(using: segmentedRegistration, for: indexPath, item: row)
            }
        })
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, Row>()
        snapshot.appendSections([0])
        snapshot.appendItems(rows, toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: - Collection View

    private lazy var segmentedRegistration: UICollectionView.CellRegistration<ReaderSettingsSegmentedCell, Row> = {
        return UICollectionView.CellRegistration<ReaderSettingsSegmentedCell, Row> { [weak self] cell, _, row in
            guard let self else { return }

            let title: String
            let actions: [UIAction]
            let selectedIndex: Int

            switch row {
            case .pageTransition:
                title = L10n.Pdf.Settings.PageTransition.title
                selectedIndex = Int(viewModel.state.transition.rawValue)
                actions = [
                    UIAction(
                        title: L10n.Pdf.Settings.PageTransition.jump,
                        state: viewModel.state.transition == .scrollPerSpread ? .on : .off,
                        handler: { [weak self] _ in self?.viewModel.process(action: .setTransition(.scrollPerSpread)) }
                    ),
                    UIAction(
                        title: L10n.Pdf.Settings.PageTransition.continuous,
                        state: viewModel.state.transition == .scrollContinuous ? .on : .off,
                        handler: { [weak self] _ in self?.viewModel.process(action: .setTransition(.scrollContinuous)) }
                    )
                ]

            case .pageMode:
                title = L10n.Pdf.Settings.PageMode.title
                selectedIndex = Int(viewModel.state.pageMode.rawValue)
                actions = [
                    UIAction(
                        title: L10n.Pdf.Settings.PageMode.single,
                        state: viewModel.state.pageMode == .single ? .on : .off,
                        handler: { [weak self] _ in self?.viewModel.process(action: .setPageMode(.single)) }
                    ),
                    UIAction(
                        title: L10n.Pdf.Settings.PageMode.double,
                        state: viewModel.state.pageMode == .double ? .on : .off,
                        handler: { [weak self] _ in self?.viewModel.process(action: .setPageMode(.double)) }
                    ),
                    UIAction(
                        title: L10n.Pdf.Settings.PageMode.automatic,
                        state: viewModel.state.pageMode == .automatic ? .on : .off,
                        handler: { [weak self] _ in self?.viewModel.process(action: .setPageMode(.automatic)) }
                    )
                ]

            case .scrollDirection:
                title = L10n.Pdf.Settings.ScrollDirection.title
                selectedIndex = Int(viewModel.state.scrollDirection.rawValue)
                actions = [
                    UIAction(
                        title: L10n.Pdf.Settings.ScrollDirection.horizontal,
                        state: viewModel.state.scrollDirection == .horizontal ? .on : .off,
                        handler: { [weak self] _ in self?.viewModel.process(action: .setDirection(.horizontal)) }
                    ),
                    UIAction(
                        title: L10n.Pdf.Settings.ScrollDirection.vertical,
                        state: viewModel.state.scrollDirection == .vertical ? .on : .off,
                        handler: { [weak self] _ in self?.viewModel.process(action: .setDirection(.vertical)) }
                    )
                ]

            case .pageFitting:
                title = L10n.Pdf.Settings.PageFitting.title
                selectedIndex = viewModel.state.pageFitting.rawValue
                actions = [
                    UIAction(
                        title: L10n.Pdf.Settings.PageFitting.fit,
                        state: viewModel.state.pageFitting == .fit ? .on : .off,
                        handler: { [weak self] _ in self?.viewModel.process(action: .setPageFitting(.fit)) }
                    ),
                    UIAction(
                        title: L10n.Pdf.Settings.PageFitting.fill,
                        state: viewModel.state.pageFitting == .fill ? .on : .off,
                        handler: { [weak self] _ in self?.viewModel.process(action: .setPageFitting(.fill)) }
                    ),
                    UIAction(
                        title: L10n.Pdf.Settings.PageFitting.automatic,
                        state: viewModel.state.pageFitting == .adaptive ? .on : .off,
                        handler: { [weak self] _ in self?.viewModel.process(action: .setPageFitting(.adaptive)) }
                    )
                ]

            case .pageSpreads:
                title = L10n.Pdf.Settings.PageSpreads.title
                selectedIndex = viewModel.state.isFirstPageAlwaysSingle ? 1 : 0
                actions = [
                    UIAction(
                        title: L10n.Pdf.Settings.PageSpreads.odd,
                        state: !viewModel.state.isFirstPageAlwaysSingle ? .on : .off,
                        handler: { [weak self] _ in self?.viewModel.process(action: .setPageSpreads(isFirstPageAlwaysSingle: false)) }
                    ),
                    UIAction(
                        title: L10n.Pdf.Settings.PageSpreads.even,
                        state: viewModel.state.isFirstPageAlwaysSingle ? .on : .off,
                        handler: { [weak self] _ in self?.viewModel.process(action: .setPageSpreads(isFirstPageAlwaysSingle: true)) }
                    )
                ]

            case .appearance:
                title = L10n.Pdf.Settings.Appearance.title
                selectedIndex = Int(viewModel.state.appearance.rawValue)
                actions = [
                    UIAction(
                        title: L10n.Pdf.Settings.Appearance.lightMode,
                        state: viewModel.state.appearance == .light ? .on : .off,
                        handler: { [weak self] _ in self?.viewModel.process(action: .setAppearance(.light)) }
                    ),
                    UIAction(
                        title: L10n.Pdf.Settings.Appearance.darkMode,
                        state: viewModel.state.appearance == .dark ? .on : .off,
                        handler: { [weak self] _ in self?.viewModel.process(action: .setAppearance(.dark)) }
                    ),
                    UIAction(
                        title: L10n.Pdf.Settings.Appearance.sepiaMode,
                        state: viewModel.state.appearance == .sepia ? .on : .off,
                        handler: { [weak self] _ in self?.viewModel.process(action: .setAppearance(.sepia)) }
                    ),
                    UIAction(
                        title: L10n.Pdf.Settings.Appearance.auto,
                        state: viewModel.state.appearance == .automatic ? .on : .off,
                        handler: { [weak self] _ in self?.viewModel.process(action: .setAppearance(.automatic)) }
                    )
                ]
            
            case .fontManagement:
                // Font management uses a different cell registration
                fatalError("Font management should be handled by fontManagementRegistration")
            }

            let configuration = ReaderSettingsSegmentedCell.ContentConfiguration(title: title, actions: actions, selectedIndex: selectedIndex)
            cell.contentConfiguration = configuration
        }
    }()

    private lazy var fontManagementRegistration: UICollectionView.CellRegistration<UICollectionViewListCell, Row> = {
        return UICollectionView.CellRegistration<UICollectionViewListCell, Row> { [weak self] cell, _, _ in
            guard let self else { return }
            
            var content = cell.defaultContentConfiguration()
            content.text = "Custom Fonts"
            content.secondaryText = "Import and manage fonts"
            
            cell.contentConfiguration = content
            cell.accessories = [.disclosureIndicator()]
        }
    }()

    private func createCollectionViewLayout() -> UICollectionViewCompositionalLayout {
        return UICollectionViewCompositionalLayout { _, environment in
            let configuration = UICollectionLayoutListConfiguration(appearance: .plain)
            return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
        }
    }

    // MARK: - Setups

    private func setupNavigationBarIfNeeded() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        let button = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(Self.done))
        navigationItem.rightBarButtonItem = button
    }
    
    // MARK: - UICollectionViewDelegate
    
    override func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let row = dataSource.itemIdentifier(for: indexPath) else { return false }
        return row == .fontManagement
    }
    
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let row = dataSource.itemIdentifier(for: indexPath) else { return }
        
        if row == .fontManagement {
            showFontManagement()
        }
    }
    
    private func showFontManagement() {
        let fontVC = FontManagementViewController(documentKey: nil)
        navigationController?.pushViewController(fontVC, animated: true)
    }
}
