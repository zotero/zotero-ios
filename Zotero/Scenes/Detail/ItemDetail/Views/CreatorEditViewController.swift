//
//  CreatorEditViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 27/10/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

typealias CreatorEditSaveAction = (ItemDetailState.Creator) -> Void
typealias CreatorEditDeleteAction = (String) -> Void

final class CreatorEditViewController: UIViewController {
    private enum Section: Hashable {
        case type, name, delete
    }

    private enum Row: Hashable {
        case type, input1, input2, namePresentation, delete
    }

    private weak var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Row>!

    private static let width: CGFloat = 400

    private let viewModel: ViewModel<CreatorEditActionHandler>
    private let saveAction: CreatorEditSaveAction
    private let deleteAction: CreatorEditDeleteAction?
    private let disposeBag: DisposeBag

    weak var coordinatorDelegate: CreatorEditCoordinatorDelegate?

    // MARK: - Lifecycle

    init(viewModel: ViewModel<CreatorEditActionHandler>, saved: @escaping CreatorEditSaveAction, deleted: CreatorEditDeleteAction?) {
        self.viewModel = viewModel
        saveAction = saved
        deleteAction = deleted
        disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupCollectionView()
        setupNavigationItems()
        navigationItem.title = L10n.CreatorEditor.title
        applySnapshot()

        viewModel.stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                self?.update(to: state)
            })
            .disposed(by: self.disposeBag)

        func setupCollectionView() {
            let appearance: UICollectionLayoutListConfiguration.Appearance
            if #available(iOS 26.0, *) {
                appearance = .insetGrouped
            } else {
                appearance = .grouped
            }
            let configuration = UICollectionLayoutListConfiguration(appearance: appearance)
            let layout = UICollectionViewCompositionalLayout.list(using: configuration)
            let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
            collectionView.backgroundColor = .systemGroupedBackground
            collectionView.delegate = self
            collectionView.translatesAutoresizingMaskIntoConstraints = false
            view.backgroundColor = .systemGroupedBackground
            view.addSubview(collectionView)
            self.collectionView = collectionView
            if #available(iOS 26.0, *) {
                setContentScrollView(collectionView)
            }

            NSLayoutConstraint.activate([
                collectionView.topAnchor.constraint(equalTo: view.topAnchor),
                collectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                collectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                collectionView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
            ])

            let nameRegistration = UICollectionView.CellRegistration<CreatorNameCell, Row> { [weak self] cell, _, row in
                self?.configureNameCell(cell, for: row)
                cell.textChanged = { [weak self] text in
                    guard let self else { return }
                    if row == .input2 {
                        self.viewModel.process(action: .setFirstName(text))
                    } else if self.viewModel.state.creator.namePresentation == .full {
                        self.viewModel.process(action: .setFullName(text))
                    } else {
                        self.viewModel.process(action: .setLastName(text))
                    }
                }
            }
            let actionRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Row> { [weak self] cell, _, row in
                self?.configureActionCell(cell, for: row)
            }
            dataSource = UICollectionViewDiffableDataSource<Section, Row>(collectionView: collectionView) { collectionView, indexPath, row in
                switch row {
                case .input1, .input2:
                    return collectionView.dequeueConfiguredReusableCell(using: nameRegistration, for: indexPath, item: row)

                case .type, .namePresentation, .delete:
                    return collectionView.dequeueConfiguredReusableCell(using: actionRegistration, for: indexPath, item: row)
                }
            }
        }

        func setupNavigationItems() {
            let cancelPrimaryAction = UIAction(title: L10n.cancel) { [weak self] _ in
                self?.presentingViewController?.dismiss(animated: true)
            }
            let cancel: UIBarButtonItem
            if #available(iOS 26.0.0, *) {
                cancel = UIBarButtonItem(systemItem: .cancel, primaryAction: cancelPrimaryAction)
            } else {
                cancel = UIBarButtonItem(primaryAction: cancelPrimaryAction)
            }
            navigationItem.leftBarButtonItem = cancel

            let savePrimaryAction = UIAction { [weak self] _ in
                self?.save()
            }
            let save: UIBarButtonItem
            if #available(iOS 26.0.0, *) {
                save = UIBarButtonItem(systemItem: .done, primaryAction: savePrimaryAction)
                save.tintColor = Asset.Colors.zoteroBlue.color
                save.style = .prominent
            } else {
                savePrimaryAction.title = L10n.save
                save = UIBarButtonItem(primaryAction: savePrimaryAction)
                save.style = .done
            }
            save.isEnabled = viewModel.state.isValid
            navigationItem.rightBarButtonItem = save
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        focusNameField(for: .input1)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let height = collectionView.collectionViewLayout.collectionViewContentSize.height + view.safeAreaInsets.top + view.safeAreaInsets.bottom
        let size = CGSize(width: Self.width, height: height)
        guard preferredContentSize != size else { return }
        preferredContentSize = size
        navigationController?.preferredContentSize = size
    }

    // MARK: - Actions

    private func update(to state: CreatorEditState) {
        if state.changes.contains(.namePresentation) {
            let wasEditingName = nameCell(for: .input1)?.textField.isFirstResponder == true || nameCell(for: .input2)?.textField.isFirstResponder == true
            applySnapshot { [weak self] in
                guard let self else { return }
                collectionView.layoutIfNeeded()
                configureVisibleCells()
                view.setNeedsLayout()
                if wasEditingName {
                    focusNameField(for: .input1)
                }
            }
        }

        if state.changes.contains(.type) {
            configureVisibleCells()
        }

        if state.changes.contains(.name) {
            navigationItem.rightBarButtonItem?.isEnabled = state.isValid
        }
    }

    private func save() {
        guard viewModel.state.isValid else { return }
        saveAction(viewModel.state.creator)
        presentingViewController?.dismiss(animated: true, completion: nil)
    }

    // MARK: - Setups

    private func applySnapshot(completion: (() -> Void)? = nil) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        snapshot.appendSections([.type, .name])
        snapshot.appendItems([.type], toSection: .type)
        var nameRows: [Row] = [.input1]
        if viewModel.state.creator.namePresentation == .separate {
            nameRows.append(.input2)
        }
        nameRows.append(.namePresentation)
        snapshot.appendItems(nameRows, toSection: .name)
        if deleteAction != nil {
            snapshot.appendSections([.delete])
            snapshot.appendItems([.delete], toSection: .delete)
        }
        dataSource.apply(snapshot, animatingDifferences: false, completion: completion)
    }

    private func nameCell(for row: Row) -> CreatorNameCell? {
        guard let indexPath = dataSource.indexPath(for: row) else { return nil }
        return collectionView.cellForItem(at: indexPath) as? CreatorNameCell
    }

    private func focusNameField(for row: Row) {
        guard let indexPath = dataSource.indexPath(for: row) else { return }
        if collectionView.cellForItem(at: indexPath) == nil {
            collectionView.scrollToItem(at: indexPath, at: .top, animated: false)
            collectionView.layoutIfNeeded()
        }
        nameCell(for: row)?.textField.becomeFirstResponder()
    }

    private func configureVisibleCells() {
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let row = dataSource.itemIdentifier(for: indexPath), let cell = collectionView.cellForItem(at: indexPath) as? UICollectionViewListCell else { continue }
            if let cell = cell as? CreatorNameCell {
                configureNameCell(cell, for: row)
            } else {
                configureActionCell(cell, for: row)
            }
        }
    }

    private func configureNameCell(_ cell: CreatorNameCell, for row: Row) {
        let creator = viewModel.state.creator
        if row == .input2 {
            cell.set(title: L10n.CreatorEditor.firstName, text: creator.firstName)
        } else if creator.namePresentation == .full {
            cell.set(title: L10n.name, text: creator.fullName)
        } else {
            cell.set(title: L10n.CreatorEditor.lastName, text: creator.lastName)
        }
    }

    private func configureActionCell(_ cell: UICollectionViewListCell, for row: Row) {
        let creator = viewModel.state.creator
        var configuration = cell.defaultContentConfiguration()
        switch row {
        case .type:
            configuration.text = L10n.CreatorEditor.creator
            configuration.textProperties.font = .preferredFont(forTextStyle: .headline)
            configuration.textProperties.color = .systemGray
            configuration.secondaryText = creator.localizedType
            configuration.secondaryTextProperties.font = .preferredFont(forTextStyle: .body)
            configuration.secondaryTextProperties.color = .label
            configuration.prefersSideBySideTextAndSecondaryText = true
            configuration.textToSecondaryTextHorizontalPadding = 16
            cell.accessories = [.disclosureIndicator()]

        case .namePresentation:
            configuration.text = creator.namePresentation == .full ? L10n.CreatorEditor.switchToDual : L10n.CreatorEditor.switchToSingle
            configuration.textProperties.color = Asset.Colors.zoteroBlue.color
            cell.accessories = []

        case .delete:
            configuration.text = "\(L10n.delete) \(creator.localizedType)"
            configuration.textProperties.color = .systemRed
            cell.accessories = []

        case .input1, .input2:
            return
        }
        configuration.textProperties.numberOfLines = 0
        cell.contentConfiguration = configuration
    }
}

extension CreatorEditViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let row = dataSource.itemIdentifier(for: indexPath) else { return }
        switch row {
        case .type:
            showTypePicker()

        case .input1, .input2:
            focusNameField(for: row)

        case .namePresentation:
            toggleNamePresentation()

        case .delete:
            delete()
        }

        func showTypePicker() {
            coordinatorDelegate?.showCreatorTypePicker(itemType: viewModel.state.itemType, selected: viewModel.state.creator.type, picked: { [weak self] newType in
                self?.viewModel.process(action: .setType(newType))
            })
        }

        func toggleNamePresentation() {
            var namePresentation = viewModel.state.creator.namePresentation
            namePresentation.toggle()
            viewModel.process(action: .setNamePresentation(namePresentation))
        }

        func delete() {
            let controller = UIAlertController(title: L10n.warning, message: L10n.CreatorEditor.deleteConfirmation, preferredStyle: .alert)
            controller.addAction(UIAlertAction(title: L10n.delete, style: .destructive, handler: { [weak self] _ in
                guard let self else { return }
                deleteAction?(viewModel.state.creator.id)
                presentingViewController?.dismiss(animated: true, completion: nil)
            }))
            controller.addAction(UIAlertAction(title: L10n.cancel, style: .cancel, handler: nil))
            present(controller, animated: true, completion: nil)
        }
    }
}

private final class CreatorNameCell: UICollectionViewListCell {
    private let titleLabel = UILabel()
    let textField = UITextField()
    var textChanged: ((String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .systemGray
        titleLabel.numberOfLines = 0
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.autocapitalizationType = .sentences
        textField.autocorrectionType = .no
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.addTarget(self, action: #selector(textDidChange), for: .editingChanged)
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        textField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        contentView.addSubview(textField)
        let minimumHeight = contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        minimumHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            titleLabel.widthAnchor.constraint(lessThanOrEqualTo: contentView.layoutMarginsGuide.widthAnchor, multiplier: 0.5),
            textField.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 16),
            textField.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            textField.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            textField.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            minimumHeight
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        textChanged = nil
    }

    func set(title: String, text: String) {
        titleLabel.text = title
        textField.accessibilityLabel = title
        if textField.text != text {
            textField.text = text
        }
    }

    @objc private func textDidChange() {
        textChanged?(textField.text ?? "")
    }
}
