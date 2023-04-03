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
    @IBOutlet private weak var tagFilterContainer: UIView!
    @IBOutlet private weak var tagFilterTitleLabel: UILabel!
    @IBOutlet private weak var tagFilterButton: UIView!
    @IBOutlet private weak var tagFilterChevron: UIImageView!
    @IBOutlet private weak var tagFilterButtonTitle: UILabel!
    @IBOutlet private weak var tagFilterClearButton: UIButton!

    private static let width: CGFloat = 320
    private let viewModel: ViewModel<ItemsActionHandler>
    private let disposeBag: DisposeBag
    private unowned let dbStorage: DbStorage

    weak var coordinatorDelegate: ItemsFilterCoordinatorDelegate?
    private var downloadsFilterEnabled: Bool {
        return self.viewModel.state.filters.contains(where: { filter in
            switch filter {
            case .downloadedFiles: return true
            default: return false
            }
        })
    }

    init(viewModel: ViewModel<ItemsActionHandler>, dbStorage: DbStorage) {
        self.viewModel = viewModel
        self.dbStorage = dbStorage
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

        guard UIDevice.current.userInterfaceIdiom == .pad else { return }

        var preferredSize = self.container.systemLayoutSizeFitting(CGSize(width: ItemsFilterViewController.width, height: .greatestFiniteMagnitude))
        preferredSize.width = ItemsFilterViewController.width
        preferredSize.height += 10
        self.preferredContentSize = preferredSize
        self.navigationController?.preferredContentSize = preferredSize
    }

    // MARK: - Actions

    private func update(state: ItemsState) {
        if state.changes.contains(.filters) && UIDevice.current.userInterfaceIdiom == .phone {
            self.update(tagNames: state.tagsFilter)
        }
    }

    private func update(tagNames: Set<String>?) {
        if let tagNames = tagNames {
            do {
                let request = ReadTagsWithNamesDbRequest(names: tagNames, libraryId: self.viewModel.state.library.identifier)
                let tags = try self.dbStorage.perform(request: request, on: .main)
                self.tagFilterButtonTitle.attributedText = AttributedTagStringGenerator.attributedString(fromUnsortedResults: tags, limit: 5)
            } catch {
                self.tagFilterButtonTitle.text = tagNames.sorted().joined(separator: ", ")
            }

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
        let tags = self.viewModel.state.tagsFilter
        self.coordinatorDelegate?.showTagPicker(libraryId: self.viewModel.state.library.identifier, selected: (tags ?? []), picked: { [weak self] newTags in
            if newTags.isEmpty {
                if let tags = tags {
                    self?.viewModel.process(action: .disableFilter(.tags(tags)))
                }
            } else {
                self?.viewModel.process(action: .enableFilter(.tags(Set(newTags.map({ $0.name })))))
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
        self.tagFilterContainer.isHidden = UIDevice.current.userInterfaceIdiom == .pad
        self.tagFilterTitleLabel.text = L10n.Items.Filters.tags
        self.tagFilterChevron.image = UIImage(systemName: "chevron.right")?.withAlignmentRectInsets(UIEdgeInsets(top: 0, left: 0, bottom: 0, right: -16))
        self.tagFilterClearButton.setTitle("", for: .normal)
        self.tagFilterClearButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 16)

        self.downloadsSwitch.isOn = self.downloadsFilterEnabled
        self.update(tagNames: self.viewModel.state.tagsFilter)
    }
}
