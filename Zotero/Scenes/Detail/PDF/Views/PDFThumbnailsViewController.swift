//
//  PDFThumbnailsViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 04.12.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class PDFThumbnailsViewController: UICollectionViewController {
    private static var cellId: String = "CellId"

    private let viewModel: ViewModel<PDFThumbnailsActionHandler>
    private let updateQueue: DispatchQueue
    private let disposeBag: DisposeBag

    private var dataSource: UICollectionViewDiffableDataSource<Int, PDFThumbnailsState.Page>!

    private lazy var cellRegistration: UICollectionView.CellRegistration<PDFThumbnailsCell, PDFThumbnailsState.Page> = {
        return UICollectionView.CellRegistration<PDFThumbnailsCell, PDFThumbnailsState.Page> { [weak self] cell, indexPath, page in
            let image = self?.viewModel.state.cache.object(forKey: NSNumber(value: indexPath.row))
            if image == nil {
                self?.viewModel.process(action: .load(UInt(indexPath.row)))
            }
            cell.contentConfiguration = PDFThumbnailsCell.ContentConfiguration(label: page.title, image: image)
        }
    }()

    init(viewModel: ViewModel<PDFThumbnailsActionHandler>) {
        self.viewModel = viewModel
        self.disposeBag = DisposeBag()
        updateQueue = DispatchQueue(label: "org.zotero.PDFThumbnailsViewController.UpdateQueue")

        let layout = UICollectionViewCompositionalLayout { _, environment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            configuration.showsSeparators = false
            let section = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
            section.contentInsets = PDFThumbnailsLayout.contentInsets
            return section
        }

        super.init(collectionViewLayout: layout)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemGray6
        setupCollectionView()

        viewModel.stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(with: self, onNext: { `self`, state in
                self.update(state: state)
            })
            .disposed(by: disposeBag)

        func setupCollectionView() {
            let registration = cellRegistration
            dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView, cellProvider: { collectionView, indexPath, itemIdentifier in
                return collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: itemIdentifier)
            })
            collectionView.dataSource = dataSource
            collectionView.delegate = self
            collectionView.prefetchDataSource = self
            collectionView.backgroundColor = .systemGray6
        }
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        viewModel.process(action: .loadPages)
    }

    func set(visiblePage: Int) {
        viewModel.process(action: .setSelectedPage(pageIndex: visiblePage, type: .fromDocument))
    }

    private func update(state: PDFThumbnailsState) {
        if state.changes.contains(.pages) && !state.pages.isEmpty {
            updateQueue.async { [weak self] in
                guard let self else { return }
                var snapshot = NSDiffableDataSourceSnapshot<Int, PDFThumbnailsState.Page>()
                snapshot.appendSections([0])
                snapshot.appendItems(state.pages)
                dataSource.apply(snapshot, animatingDifferences: false)

                let indexPath = IndexPath(row: viewModel.state.selectedPageIndex, section: 0)
                // Without .main.async the collection view cell is not actually selected, the collection view only scrolls to correct position. It doesn't help to have it in completion handler.
                DispatchQueue.main.async { [weak self] in
                    self?.collectionView.selectItem(at: indexPath, animated: false, scrollPosition: .centeredVertically)
                }
            }
            return
        }

        var snapshot = dataSource.snapshot()
        if let index = state.loadedThumbnail, index < snapshot.itemIdentifiers.count {
            updateQueue.async { [weak self] in
                guard let self else { return }
                let label = dataSource.snapshot().itemIdentifiers[index]
                snapshot.reconfigureItems([label])
                dataSource.apply(snapshot)
            }
            return
        }

        // The following updates should be ignored if the collection hasn't loaded yet for the first time.
        guard snapshot.numberOfSections > 0 else { return }

        if state.changes.contains(.appearance) || state.changes.contains(.reload) {
            updateQueue.async { [weak self] in
                guard let self else { return }
                var snapshot = dataSource.snapshot()
                snapshot.reconfigureItems(snapshot.itemIdentifiers)
                dataSource.apply(snapshot, animatingDifferences: false, completion: nil)
            }
            return
        }

        if state.changes.contains(.scrollToSelection) {
            let indexPath = IndexPath(row: state.selectedPageIndex, section: 0)
            collectionView.selectItem(at: indexPath, animated: true, scrollPosition: .centeredVertically)
        }
    }
}

extension PDFThumbnailsViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let toFetch = indexPaths.map({ $0.row }).map(UInt.init)
        viewModel.process(action: .prefetch(toFetch))
    }
}

extension PDFThumbnailsViewController {
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        viewModel.process(action: .setSelectedPage(pageIndex: indexPath.row, type: .fromSidebar))
    }
}
