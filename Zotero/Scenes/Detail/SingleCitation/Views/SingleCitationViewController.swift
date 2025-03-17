//
//  SingleCitationViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 15.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import WebKit

import CocoaLumberjackSwift
import RxSwift

final class SingleCitationViewController: UIViewController {
    enum Section {
        case data
        case preview
    }

    enum Row {
        case locator
        case author
        case preview
    }

    static let width: CGFloat = 500
    private let viewModel: ViewModel<SingleCitationActionHandler>
    private let disposeBag: DisposeBag

    private weak var collectionView: UICollectionView!
    private weak var previewWebView: WKWebView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Row>!
    weak var coordinatorDelegate: DetailCitationCoordinatorDelegate?

    private lazy var locatorRegistration: UICollectionView.CellRegistration<CitationLocatorCell, (String, String)> = {
        return UICollectionView.CellRegistration<CitationLocatorCell, (String, String)> { [weak self] cell, _, data in
            cell.contentConfiguration = CitationLocatorCell.ContentConfiguration(
                locator: data.0,
                value: data.1,
                locatorChanged: { [weak self] newLocator in
                    guard let self else { return }
                    viewModel.process(action: .setLocator(locator: newLocator))
                }
            )
            if let valueObservable = cell.valueObservable {
                valueObservable
                    .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
                    .subscribe(onNext: { [weak self] newValue in
                        guard let self else { return }
                        viewModel.process(action: .setLocatorValue(value: newValue))
                    })
                    .disposed(by: cell.disposeBag)
            }
        }
    }()
    private lazy var authorRegistration: UICollectionView.CellRegistration<CitationAuthorCell, Bool> = {
        return UICollectionView.CellRegistration<CitationAuthorCell, Bool> { [weak self] cell, _, omitAuthor in
            cell.contentConfiguration = CitationAuthorCell.ContentConfiguration(omitAuthor: omitAuthor, omitAuthorChanged: { [weak self] newOmitAuthor in
                guard let self else { return }
                viewModel.process(action: .setOmitAuthor(omitAuthor: newOmitAuthor))
            })
        }
    }()
    private lazy var previewRegistration: UICollectionView.CellRegistration<CitationPreviewCell, (String, CGFloat)> = {
        return UICollectionView.CellRegistration<CitationPreviewCell, (String, CGFloat)> { cell, _, data in
            cell.contentConfiguration = CitationPreviewCell.ContentConfiguration(preview: data.0, height: data.1)
        }
    }()

    // MARK: - Object Lifecycle
    init(viewModel: ViewModel<SingleCitationActionHandler>) {
        self.viewModel = viewModel
        disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        viewModel.process(action: .cleanup)
    }

    // MARK: - View Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()

        title = L10n.Citation.title
        setupNavigationBar()
        setupCollectionView()
        setupDataSource()
        setupWebView()

        viewModel.stateObservable
            .subscribe(onNext: { [weak self] state in
                self?.update(state: state)
            })
            .disposed(by: disposeBag)

        func setupCollectionView() {
            let layout = UICollectionViewCompositionalLayout { [weak self] index, environment in
                let snapshot = self?.dataSource.snapshot()
                let sectionType = snapshot.flatMap({ index < $0.sectionIdentifiers.count ? $0.sectionIdentifiers[index] : nil }) ?? .data
                let configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
                let section = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
                switch sectionType {
                case .data:
                    section.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 32, trailing: 16)

                case .preview:
                    section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16)
                    let header = NSCollectionLayoutBoundarySupplementaryItem(
                        layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(16)),
                        elementKind: UICollectionView.elementKindSectionHeader,
                        alignment: .topLeading
                    )
                    section.boundarySupplementaryItems = [header]
                }
                return section
            }
            let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
            collectionView.translatesAutoresizingMaskIntoConstraints = false
            collectionView.allowsSelection = false
            collectionView.register(SingleCitationSectionView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "header")
            view.addSubview(collectionView)
            self.collectionView = collectionView

            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: collectionView.topAnchor),
                view.bottomAnchor.constraint(equalTo: collectionView.bottomAnchor),
                view.leadingAnchor.constraint(equalTo: collectionView.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: collectionView.trailingAnchor)
            ])
        }

        func setupDataSource() {
            let locatorRegistration = locatorRegistration
            let authorRegistration = authorRegistration
            let previewRegistration = previewRegistration

            dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView!, cellProvider: { [weak self] collectionView, indexPath, row in
                guard let self else {
                    return collectionView.dequeueConfiguredReusableCell(using: authorRegistration, for: indexPath, item: false)
                }
                switch row {
                case .locator:
                    return collectionView.dequeueConfiguredReusableCell(using: locatorRegistration, for: indexPath, item: (viewModel.state.locator, viewModel.state.locatorValue))

                case .author:
                    return collectionView.dequeueConfiguredReusableCell(using: authorRegistration, for: indexPath, item: viewModel.state.omitAuthor)

                case .preview:
                    return collectionView.dequeueConfiguredReusableCell(using: previewRegistration, for: indexPath, item: (viewModel.state.preview ?? "", viewModel.state.previewHeight))
                }
            })

            dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
                guard let self, indexPath.section < dataSource.snapshot().sectionIdentifiers.count else { return nil }
                let section = dataSource.snapshot().sectionIdentifiers[indexPath.section]
                switch section {
                case .preview:
                    let view = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "header", for: indexPath)
                    if let view = view as? SingleCitationSectionView {
                        view.setup(with: L10n.Citation.preview.uppercased())
                    }
                    return view

                case .data:
                    return nil
                }
            }

            var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
            snapshot.appendSections([.data, .preview])
            snapshot.appendItems([.locator, .author], toSection: .data)
            snapshot.appendItems([.preview], toSection: .preview)
            dataSource.apply(snapshot) {
                self.updatePreferredContentSize()
            }
        }

        func setupWebView() {
            let webView = WKWebView()
            webView.translatesAutoresizingMaskIntoConstraints = false
            webView.isHidden = true
            view.addSubview(webView)
            previewWebView = webView

            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: view.topAnchor),
                view.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
                webView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
                view.trailingAnchor.constraint(equalTo: webView.trailingAnchor, constant: 32)
            ])

            viewModel.process(action: .preload(webView: webView))
        }

        func setupNavigationBar() {
            let cancel = UIBarButtonItem(title: L10n.cancel, style: .plain, target: nil, action: nil)
            cancel.rx.tap.subscribe(onNext: { [weak self] in
                self?.navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
            })
            .disposed(by: disposeBag)
            navigationItem.leftBarButtonItem = cancel

            setupRightButtonItem(isLoading: false)
            navigationItem.rightBarButtonItem?.isEnabled = false
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        previewWebView.configuration.userContentController.add(self, name: "heightHandler")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        previewWebView.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    // MARK: - Actions
    private func update(state: SingleCitationState) {
        setupRightButtonItem(isLoading: state.loadingCopy)
        navigationItem.rightBarButtonItem?.isEnabled = state.preview != nil

        if state.changes.contains(.preview) || state.changes.contains(.height) {
            var snapshot = dataSource.snapshot()
            snapshot.reloadSections([.preview])
            dataSource.apply(snapshot) {
                self.updatePreferredContentSize()
            }
        }

        if state.changes.contains(.copied) {
            navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
        }

        if let error = state.error, let coordinatorDelegate {
            switch error {
            case .styleMissing:
                coordinatorDelegate.showMissingStyleError(using: nil)

            case .cantPreloadWebView:
                if let navigationController {
                    coordinatorDelegate.showCitationPreviewError(using: navigationController, errorMessage: L10n.Errors.citationPreview)
                }
            }
        }
    }

    // MARK: - Helpers
    private func setupRightButtonItem(isLoading: Bool) {
        guard navigationItem.rightBarButtonItem == nil || isLoading == (navigationItem.rightBarButtonItem?.customView == nil) else { return }
        if isLoading {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.startAnimating()
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: indicator)
        } else {
            let copy = UIBarButtonItem(title: L10n.copy, style: .done, target: nil, action: nil)
            copy.rx.tap.subscribe(onNext: { [weak self] in
                guard let self else { return }
                viewModel.process(action: .copy)
            })
            .disposed(by: disposeBag)
            navigationItem.rightBarButtonItem = copy
        }
    }

    private func updatePreferredContentSize() {
        let width = SingleCitationViewController.width
        let height = collectionView.collectionViewLayout.collectionViewContentSize.height
        preferredContentSize = CGSize(width: width, height: height)
        navigationController?.preferredContentSize = preferredContentSize
    }
}

extension SingleCitationViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "heightHandler", let height = message.body as? CGFloat else { return }
        viewModel.process(action: .setPreviewHeight(height))
    }
}

final class SingleCitationSectionView: UICollectionReusableView {
    private weak var titleLabel: UILabel!

    override init(frame: CGRect) {
        super.init(frame: .zero)

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .systemGray
        addSubview(label)
        titleLabel = label

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            bottomAnchor.constraint(equalTo: label.bottomAnchor),
            trailingAnchor.constraint(equalTo: label.trailingAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setup(with title: String) {
        titleLabel.text = title
    }
}
