//
//  ItemsFilterViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 16.04.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class ItemsFilterViewController: UIViewController {
    @IBOutlet private weak var container: UIStackView!
    @IBOutlet private weak var downloadsTitleLabel: UILabel!
    @IBOutlet private weak var downloadsSwitch: UISwitch!
    @IBOutlet private weak var tagFilterTitleLabel: UILabel!
    @IBOutlet private weak var tagFilterButton: UIView!
    @IBOutlet private weak var tagFilterChevron: UIImageView!
    @IBOutlet private weak var tagFilterButtonTitle: UILabel!
    @IBOutlet private weak var tagFilterClearButton: UIButton!

    private static let width: CGFloat = 320
    private let viewModel: ViewModel<ItemsActionHandler>
    private let disposeBag: DisposeBag

    weak var coordinatorDelegate: DetailItemsFilterCoordinatorDelegate?
    private var downloadsFilterEnabled: Bool {
        return self.viewModel.state.filters.contains(where: { filter in
            switch filter {
            case .downloadedFiles: return true
            default: return false
            }
        })
    }

    init(viewModel: ViewModel<ItemsActionHandler>) {
        self.viewModel = viewModel
        self.disposeBag = DisposeBag()
        super.init(nibName: "ItemsFilterViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupNavigationBar()
        self.setupUI()

        self.viewModel.stateObservable
                      .observe(on: MainScheduler.instance)
                      .subscribe(with: self, onNext: { `self`, state in
                          self.update(state: state)
                      })
                      .disposed(by: self.disposeBag)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        var preferredSize = self.container.systemLayoutSizeFitting(CGSize(width: ItemsFilterViewController.width, height: .greatestFiniteMagnitude))
        preferredSize.width = ItemsFilterViewController.width
        self.preferredContentSize = preferredSize
        self.navigationController?.preferredContentSize = preferredSize
    }

    func tagsFilter(from state: ItemsState) -> [Tag]? {
        let tagFilter = state.filters.first(where: { filter in
            switch filter {
            case .tags: return true
            default: return false
            }
        })

        guard let tagFilter = tagFilter, case .tags(let tags) = tagFilter else { return nil }
        return tags
    }

    // MARK: - Actions

    private func update(state: ItemsState) {
        if state.changes.contains(.filters) {
            self.update(tags: self.tagsFilter(from: state))
        }
    }

    private func update(tags: [Tag]?) {
        if let tags = tags {
            self.tagFilterButtonTitle.attributedText = AttributedTagStringGenerator.attributedString(from: tags, limit: 5)
            self.tagFilterChevron.isHidden = true
            self.tagFilterClearButton.isHidden = false
        } else {
            self.tagFilterButtonTitle.text = "-"
            self.tagFilterButtonTitle.textColor = .systemGray3
            self.tagFilterChevron.isHidden = false
            self.tagFilterClearButton.isHidden = true
        }
    }

    @IBAction private func clearTags() {
        let tagFilter = self.viewModel.state.filters.first(where: { filter in
            switch filter {
            case .tags: return true
            default: return false
            }
        })

        guard let filter = tagFilter else { return }
        self.viewModel.process(action: .disableFilter(filter))
    }

    @IBAction private func toggleDownloads(sender: UISwitch) {
        if sender.isOn {
            self.viewModel.process(action: .enableFilter(.downloadedFiles))
        } else {
            self.viewModel.process(action: .disableFilter(.downloadedFiles))
        }
    }

    @IBAction private func showTagPicker() {
        let tags = self.tagsFilter(from: self.viewModel.state)
        let selected = tags.flatMap({ tags in tags.compactMap({ $0.name }) }).flatMap(Set.init) ?? []
        self.coordinatorDelegate?.showTagPicker(libraryId: self.viewModel.state.library.identifier, selected: selected, picked: { [weak self] newTags in
            if newTags.isEmpty {
                if let tags = tags {
                    self?.viewModel.process(action: .disableFilter(.tags(tags)))
                }
            } else {
                self?.viewModel.process(action: .enableFilter(.tags(newTags)))
            }
        })
    }

    @objc private func done() {
        self.navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
    }

    // MARK: - Setups

    private func setupNavigationBar() {
        self.navigationItem.title = L10n.Items.Filters.title
        let done = UIBarButtonItem(title: L10n.done, style: .done, target: self, action: #selector(ItemsFilterViewController.done))
        self.navigationItem.rightBarButtonItem = done
    }

    private func setupUI() {
        self.downloadsTitleLabel.text = L10n.Items.Filters.downloads
        self.tagFilterTitleLabel.text = L10n.Items.Filters.tags
        self.tagFilterChevron.image = UIImage(systemName: "chevron.right")?.withAlignmentRectInsets(UIEdgeInsets(top: 0, left: 0, bottom: 0, right: -16))
        self.tagFilterClearButton.setTitle("", for: .normal)
        self.tagFilterClearButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 16)

        self.downloadsSwitch.isOn = self.downloadsFilterEnabled
        self.update(tags: self.tagsFilter(from: self.viewModel.state))
    }
}
