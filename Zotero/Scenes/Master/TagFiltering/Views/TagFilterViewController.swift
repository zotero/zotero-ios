//
//  TagFilterViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 08.03.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RealmSwift
import RxSwift
import TagsFlowLayout

protocol TagFilterDelegate: AnyObject {
    func tagSelectionDidChange(selected: Set<String>)
}

class TagFilterViewController: UIViewController {
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, Tag>!
    weak var delegate: TagFilterDelegate?

    var selectedTags: Set<String> {
        return self.viewModel.state.selectedTags
    }

    private static let cellId = "TagFilterCell"
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

    func changeLibrary(to libraryId: LibraryIdentifier) {
        self.viewModel.process(action: .changeLibrary(libraryId))
    }

    private func update(to state: TagPickerState) {
        if state.changes.contains(.selection) {
            self.delegate?.tagSelectionDidChange(selected: state.selectedTags)
        }

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

    private func setupViews() {
        let layout = TagsFlowLayout(maxWidth: self.view.frame.width, minimumInteritemSpacing: 8, minimumLineSpacing: 8,
                                    sectionInset: UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10))
        let collectionView = UICollectionView(frame: CGRect(), collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.delegate = self
        collectionView.allowsMultipleSelection = true
        collectionView.register(UINib(nibName: "TagFilterCell", bundle: nil), forCellWithReuseIdentifier: TagFilterViewController.cellId)
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
        self.dataSource = UICollectionViewDiffableDataSource(collectionView: self.collectionView, cellProvider: { collectionView, indexPath, tag in
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TagFilterViewController.cellId, for: indexPath)
            if let cell = cell as? TagFilterCell {
                cell.maxWidth = collectionView.bounds.width - 20
                let color: UIColor = tag.color.isEmpty ? .label : UIColor(hex: tag.color)
                cell.setup(with: tag.name, color: color)
            }
            return cell
        })
    }
}

extension TagFilterViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.row < self.viewModel.state.tags.count else { return }

        let tag = self.viewModel.state.tags[indexPath.row]
        self.viewModel.process(action: .select(tag.name))

        (collectionView.cellForItem(at: indexPath) as? TagFilterCell)?.set(selected: true)
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        guard indexPath.row < self.viewModel.state.tags.count else { return }
        
        let tag = self.viewModel.state.tags[indexPath.row]
        self.viewModel.process(action: .deselect(tag.name))

        (collectionView.cellForItem(at: indexPath) as? TagFilterCell)?.set(selected: false)
    }
}
