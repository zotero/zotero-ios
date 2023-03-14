//
//  TagFilterViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 08.03.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class TagFilterViewController: UIViewController {
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, Tag>!

    private let viewModel: ViewModel<TagPickerActionHandler>
    private let disposeBag: DisposeBag

    init(viewModel: ViewModel<TagPickerActionHandler>) {
        self.viewModel = viewModel
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupViews()
        self.setupDataSource()

        self.viewModel.stateObservable
                      .observe(on: MainScheduler.instance)
                      .subscribe(onNext: { [weak self] state in
                          self?.update(to: state)
                      })
                      .disposed(by: self.disposeBag)

        self.viewModel.process(action: .load)
    }

    private func update(to state: TagPickerState) {
//        self.title = L10n.TagPicker.title(state.selectedTags.count)

        if state.changes.contains(.tags) {
            var snapshot = NSDiffableDataSourceSnapshot<Int, Tag>()
            snapshot.appendSections([0])
            snapshot.appendItems(state.tags)
            self.dataSource.apply(snapshot)
        }

        if let error = state.error {
            // TODO: - show error
        }
    }

    private lazy var tagRegistration: UICollectionView.CellRegistration<TagFilterCell, Tag> = {
        return UICollectionView.CellRegistration { cell, indexPath, tag in
            let color: UIColor = tag.color.isEmpty ? .clear : UIColor(hex: tag.color)
            cell.contentConfiguration = TagFilterCell.ContentConfiguration(text: tag.name, color: color)
        }
    }()

    private func createCollectionViewLayout() -> UICollectionViewLayout {
        return UICollectionViewCompositionalLayout { index, environment in
            let itemSize = NSCollectionLayoutSize(widthDimension: .estimated(100), heightDimension: .absolute(40))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 1, bottom: 0, trailing: 1)

            let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(40))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

            let section = NSCollectionLayoutSection(group: group)
            return section
        }
    }

    private func setupViews() {
        let collectionView = UICollectionView(frame: CGRect(), collectionViewLayout: self.createCollectionViewLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        self.collectionView = collectionView

        self.view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            self.collectionView.topAnchor.constraint(equalTo: self.view.topAnchor),
            self.collectionView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            self.collectionView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.collectionView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor)
        ])
    }

    private func setupDataSource() {
        let tagRegistration = self.tagRegistration

        self.dataSource = UICollectionViewDiffableDataSource(collectionView: self.collectionView, cellProvider: { collectionView, indexPath, tag in
            collectionView.dequeueConfiguredReusableCell(using: tagRegistration, for: indexPath, item: tag)
        })
    }
}
