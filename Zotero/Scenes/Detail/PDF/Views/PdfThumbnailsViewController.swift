//
//  PdfThumbnailsViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 04.12.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class PdfThumbnailsViewController: UIViewController {
    private static var cellId: String = "CellId"

    private unowned let viewModel: ViewModel<PdfThumbnailsActionHandler>
    private let disposeBag: DisposeBag

    private weak var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, UInt>!

    private lazy var cellRegistration: UICollectionView.CellRegistration<PdfThumbnailsCell, UInt> = {
        return UICollectionView.CellRegistration<PdfThumbnailsCell, UInt> { [weak self] cell, _, pageIndex in
            let image = self?.viewModel.state.cache.object(forKey: NSNumber(value: pageIndex))
            if image == nil {
                self?.viewModel.process(action: .load(pageIndex))
            }
            cell.contentConfiguration = PdfThumbnailsCell.ContentConfiguration(image: image)
        }
    }()

    init(viewModel: ViewModel<PdfThumbnailsActionHandler>) {
        self.viewModel = viewModel
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        setupViews()

        viewModel.stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(with: self, onNext: { `self`, state in
                self.update(state: state)
            })
            .disposed(by: disposeBag)


        func setupViews() {
            let collectionView = UICollectionView()
            let registration = cellRegistration
            dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView, cellProvider: { collectionView, indexPath, itemIdentifier in
                return collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: itemIdentifier)
            })
            collectionView.dataSource = dataSource
            collectionView.delegate = self
            collectionView.prefetchDataSource = self
            self.collectionView = collectionView
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        self.viewModel.process(action: .setUserInterface(isDark: traitCollection.userInterfaceStyle == .dark))
    }

    private func update(state: PdfThumbnailsState) {
        if let index = state.loadedThumbnail {
            var snapshot = dataSource.snapshot()
            snapshot.reloadItems([index])
            dataSource.apply(snapshot)
        }

        if state.changes.contains(.userInterface) {
            var snapshot = dataSource.snapshot()
            snapshot.reloadSections([0])
            dataSource.apply(snapshot)
        }
    }
}

extension PdfThumbnailsViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let toFetch = indexPaths.compactMap({ dataSource.itemIdentifier(for: $0) }).map(UInt.init)
        viewModel.process(action: .prefetch(toFetch))
    }
}

extension PdfThumbnailsViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
    }
}
