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
    }

    let viewModel: ViewModel<ReaderSettingsActionHandler>
    private let rows: [Row]
    private let disposeBag: DisposeBag

    private var dataSource: UICollectionViewDiffableDataSource<Int, Row>!

    init(rows: [Row], viewModel: ViewModel<ReaderSettingsActionHandler>) {
        self.rows = rows
        self.viewModel = viewModel
        disposeBag = DisposeBag()

        super.init(collectionViewLayout: UICollectionViewFlowLayout())
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        setupNavigationBarIfNeeded()
        collectionView.allowsSelection = false
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

    // MARK: - Actions

    private func update(state: ReaderSettingsState) {
        (navigationController ?? self).overrideUserInterfaceStyle = state.appearance.userInterfaceStyle
    }

    @objc private func done() {
        presentingViewController?.dismiss(animated: true, completion: nil)
    }

    // MARK: - Data Source

    private func createDataSource(for collectionView: UICollectionView) -> UICollectionViewDiffableDataSource<Int, Row> {
        let segmentedRegistration = self.segmentedRegistration
        return UICollectionViewDiffableDataSource<Int, Row>(collectionView: collectionView, cellProvider: { collectionView, indexPath, row in
            return collectionView.dequeueConfiguredReusableCell(using: segmentedRegistration, for: indexPath, item: row)
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
            let getSelectedIndex: () -> Int

            switch row {
            case .pageTransition:
                title = L10n.Pdf.Settings.PageTransition.title
                getSelectedIndex = { [weak self] in
                    guard let self else { return 0 }
                    return Int(viewModel.state.transition.rawValue)
                }
                actions = [UIAction(title: L10n.Pdf.Settings.PageTransition.jump, handler: { [weak self] _ in self?.viewModel.process(action: .setTransition(.scrollPerSpread)) }),
                           UIAction(title: L10n.Pdf.Settings.PageTransition.continuous, handler: { [weak self] _ in self?.viewModel.process(action: .setTransition(.scrollContinuous)) })]

            case .pageMode:
                title = L10n.Pdf.Settings.PageMode.title
                getSelectedIndex = { [weak self] in
                    guard let self else { return 0 }
                    return Int(viewModel.state.pageMode.rawValue)
                }
                actions = [UIAction(title: L10n.Pdf.Settings.PageMode.single, handler: { [weak self] _ in self?.viewModel.process(action: .setPageMode(.single)) }),
                           UIAction(title: L10n.Pdf.Settings.PageMode.double, handler: { [weak self] _ in self?.viewModel.process(action: .setPageMode(.double)) }),
                           UIAction(title: L10n.Pdf.Settings.PageMode.automatic, handler: { [weak self] _ in self?.viewModel.process(action: .setPageMode(.automatic)) })]

            case .scrollDirection:
                title = L10n.Pdf.Settings.ScrollDirection.title
                getSelectedIndex = { [weak self] in
                    guard let self else { return 0 }
                    return Int(viewModel.state.scrollDirection.rawValue)
                }
                actions = [UIAction(title: L10n.Pdf.Settings.ScrollDirection.horizontal, handler: { [weak self] _ in self?.viewModel.process(action: .setDirection(.horizontal)) }),
                           UIAction(title: L10n.Pdf.Settings.ScrollDirection.vertical, handler: { [weak self] _ in self?.viewModel.process(action: .setDirection(.vertical)) })]

            case .pageFitting:
                title = L10n.Pdf.Settings.PageFitting.title
                getSelectedIndex = { [weak self] in
                    guard let self else { return 0 }
                    return viewModel.state.pageFitting.rawValue
                }
                actions = [UIAction(title: L10n.Pdf.Settings.PageFitting.fit, handler: { [weak self] _ in self?.viewModel.process(action: .setPageFitting(.fit)) }),
                           UIAction(title: L10n.Pdf.Settings.PageFitting.fill, handler: { [weak self] _ in self?.viewModel.process(action: .setPageFitting(.fill)) }),
                           UIAction(title: L10n.Pdf.Settings.PageFitting.automatic, handler: { [weak self] _ in self?.viewModel.process(action: .setPageFitting(.adaptive)) })]

            case .pageSpreads:
                title = L10n.Pdf.Settings.PageSpreads.title
                getSelectedIndex = { [weak self] in
                    guard let self else { return 0 }
                    return viewModel.state.isFirstPageAlwaysSingle ? 1 : 0
                }
                actions = [UIAction(title: L10n.Pdf.Settings.PageSpreads.odd, handler: { [weak self] _ in self?.viewModel.process(action: .setPageSpreads(isFirstPageAlwaysSingle: false)) }),
                           UIAction(title: L10n.Pdf.Settings.PageSpreads.even, handler: { [weak self] _ in self?.viewModel.process(action: .setPageSpreads(isFirstPageAlwaysSingle: true)) })]

            case .appearance:
                title = L10n.Pdf.Settings.Appearance.title
                getSelectedIndex = { [weak self] in
                    guard let self else { return 0 }
                    return Int(viewModel.state.appearance.rawValue)
                }
                actions = [UIAction(title: L10n.Pdf.Settings.Appearance.lightMode, handler: { [weak self] _ in self?.viewModel.process(action: .setAppearance(.light)) }),
                           UIAction(title: L10n.Pdf.Settings.Appearance.darkMode, handler: { [weak self] _ in self?.viewModel.process(action: .setAppearance(.dark)) }),
                           UIAction(title: L10n.Pdf.Settings.Appearance.sepiaMode, handler: { [weak self] _ in self?.viewModel.process(action: .setAppearance(.sepia)) }),
                           UIAction(title: L10n.Pdf.Settings.Appearance.auto, handler: { [weak self] _ in self?.viewModel.process(action: .setAppearance(.automatic)) })]
            }

            let configuration = ReaderSettingsSegmentedCell.ContentConfiguration(title: title, actions: actions, getSelectedIndex: getSelectedIndex)
            cell.contentConfiguration = configuration
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
}
