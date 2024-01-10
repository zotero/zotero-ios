//
//  PDFSettingsViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 02.03.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import PSPDFKitUI
import RxSwift

final class PDFSettingsViewController: UICollectionViewController {
    private enum Row {
        case pageTransition
        case pageMode
        case scrollDirection
        case pageFitting
        case sleep
        case appearance
    }

    private let viewModel: ViewModel<PDFSettingsActionHandler>
    private let disposeBag: DisposeBag

    private var dataSource: UICollectionViewDiffableDataSource<Int, Row>!
    var changeHandler: ((PDFSettings) -> Void)?

    init(viewModel: ViewModel<PDFSettingsActionHandler>) {
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

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if UIDevice.current.userInterfaceIdiom == .phone {
            changeHandler?(viewModel.state.settings)
        }
    }

    // MARK: - Actions

    private func update(state: PDFSettingsState) {
        switch state.settings.appearanceMode {
        case .automatic:
            overrideUserInterfaceStyle = .unspecified

        case .light:
            overrideUserInterfaceStyle = .light

        case .dark:
            overrideUserInterfaceStyle = .dark
        }

        if UIDevice.current.userInterfaceIdiom == .pad {
            changeHandler?(state.settings)
        }
    }

    @objc private func done() {
        presentingViewController?.dismiss(animated: true, completion: nil)
    }

    // MARK: - Data Source

    private func createDataSource(for collectionView: UICollectionView) -> UICollectionViewDiffableDataSource<Int, Row> {
        let switchRegistration = self.switchRegistration
        let segmentedRegistration = self.segmentedRegistration
        return UICollectionViewDiffableDataSource<Int, Row>(collectionView: collectionView, cellProvider: { collectionView, indexPath, row in
            switch row {
            case .sleep:
                return collectionView.dequeueConfiguredReusableCell(using: switchRegistration, for: indexPath, item: ())

            default:
                return collectionView.dequeueConfiguredReusableCell(using: segmentedRegistration, for: indexPath, item: row)
            }
        })
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, Row>()
        snapshot.appendSections([0])
        snapshot.appendItems([.pageTransition, .pageMode, .scrollDirection, .pageFitting, .appearance, .sleep], toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: - Collection View

    private lazy var switchRegistration: UICollectionView.CellRegistration<UICollectionViewListCell, ()> = {
        return UICollectionView.CellRegistration<UICollectionViewListCell, ()> { [weak self] cell, _, _ in
            guard let self else { return }

            var configuration = cell.defaultContentConfiguration()
            configuration.text = L10n.Pdf.Settings.idleTimerTitle
            cell.contentConfiguration = configuration

            let toggle = UISwitch()
            toggle.setOn(!viewModel.state.settings.idleTimerDisabled, animated: false)
            toggle.addAction(UIAction(handler: { [weak self, weak toggle] _ in self?.viewModel.process(action: .setIdleTimerDisabled(!(toggle?.isOn ?? false))) }), for: .valueChanged)

            let customConfiguration = UICellAccessory.CustomViewConfiguration(customView: toggle, placement: .trailing(displayed: .always))
            cell.accessories = [.customView(configuration: customConfiguration)]
        }
    }()

    private lazy var segmentedRegistration: UICollectionView.CellRegistration<PDFSettingsSegmentedCell, Row> = {
        return UICollectionView.CellRegistration<PDFSettingsSegmentedCell, Row> { [weak self] cell, _, row in
            guard let self else { return }

            let title: String
            let actions: [UIAction]
            let getSelectedIndex: () -> Int

            switch row {
            case .pageTransition:
                title = L10n.Pdf.Settings.PageTransition.title
                getSelectedIndex = { [weak self] in
                    guard let self else { return 0 }
                    return Int(viewModel.state.settings.transition.rawValue)
                }
                actions = [UIAction(title: L10n.Pdf.Settings.PageTransition.jump, handler: { [weak self] _ in self?.viewModel.process(action: .setTransition(.scrollPerSpread)) }),
                           UIAction(title: L10n.Pdf.Settings.PageTransition.continuous, handler: { [weak self] _ in self?.viewModel.process(action: .setTransition(.scrollContinuous)) })]

            case .pageMode:
                title = L10n.Pdf.Settings.PageMode.title
                getSelectedIndex = { [weak self] in
                    guard let self else { return 0 }
                    return Int(viewModel.state.settings.pageMode.rawValue)
                }
                actions = [UIAction(title: L10n.Pdf.Settings.PageMode.single, handler: { [weak self] _ in self?.viewModel.process(action: .setPageMode(.single)) }),
                           UIAction(title: L10n.Pdf.Settings.PageMode.double, handler: { [weak self] _ in self?.viewModel.process(action: .setPageMode(.double)) }),
                           UIAction(title: L10n.Pdf.Settings.PageMode.automatic, handler: { [weak self] _ in self?.viewModel.process(action: .setPageMode(.automatic)) })]

            case .scrollDirection:
                title = L10n.Pdf.Settings.ScrollDirection.title
                getSelectedIndex = { [weak self] in
                    guard let self else { return 0 }
                    return Int(viewModel.state.settings.direction.rawValue)
                }
                actions = [UIAction(title: L10n.Pdf.Settings.ScrollDirection.horizontal, handler: { [weak self] _ in self?.viewModel.process(action: .setDirection(.horizontal)) }),
                           UIAction(title: L10n.Pdf.Settings.ScrollDirection.vertical, handler: { [weak self] _ in self?.viewModel.process(action: .setDirection(.vertical)) })]

            case .pageFitting:
                title = L10n.Pdf.Settings.PageFitting.title
                getSelectedIndex = { [weak self] in
                    guard let self else { return 0 }
                    return viewModel.state.settings.pageFitting.rawValue
                }
                actions = [UIAction(title: L10n.Pdf.Settings.PageFitting.fit, handler: { [weak self] _ in self?.viewModel.process(action: .setPageFitting(.fit)) }),
                           UIAction(title: L10n.Pdf.Settings.PageFitting.fill, handler: { [weak self] _ in self?.viewModel.process(action: .setPageFitting(.fill)) }),
                           UIAction(title: L10n.Pdf.Settings.PageFitting.automatic, handler: { [weak self] _ in self?.viewModel.process(action: .setPageFitting(.adaptive)) })]

            case .appearance:
                title = L10n.Pdf.Settings.Appearance.title
                getSelectedIndex = { [weak self] in
                    guard let self else { return 0 }
                    return Int(viewModel.state.settings.appearanceMode.rawValue)
                }
                actions = [UIAction(title: L10n.Pdf.Settings.Appearance.lightMode, handler: { [weak self] _ in self?.viewModel.process(action: .setAppearanceMode(.light)) }),
                           UIAction(title: L10n.Pdf.Settings.Appearance.darkMode, handler: { [weak self] _ in self?.viewModel.process(action: .setAppearanceMode(.dark)) }),
                           UIAction(title: L10n.Pdf.Settings.Appearance.auto, handler: { [weak self] _ in self?.viewModel.process(action: .setAppearanceMode(.automatic)) })]

            case .sleep:
                return
            }

            let configuration = PDFSettingsSegmentedCell.ContentConfiguration(title: title, actions: actions, getSelectedIndex: getSelectedIndex)
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

        let button = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(PDFSettingsViewController.done))
        navigationItem.rightBarButtonItem = button
    }
}
