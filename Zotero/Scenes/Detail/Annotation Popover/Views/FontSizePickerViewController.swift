//
//  FontSizePickerViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 01.08.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class FontSizePickerViewController: UIViewController {
    private static let sizes: [CGFloat] = [
        10,
        12,
        14,
        18,
        24,
        36,
        48,
        64,
        72,
        96,
        144,
        192
    ]

    private let pickAction: (CGFloat) -> Void
    private let disposeBag: DisposeBag

    private weak var tableView: UITableView!
    private var dataSource: UITableViewDiffableDataSource<Int, CGFloat>!

    init(pickAction: @escaping (CGFloat) -> Void) {
        self.pickAction = pickAction
        disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupNavigationBarIfNeeded()
        setupViews()
        setupSizes()

        func setupSizes() {
            var snapshot = NSDiffableDataSourceSnapshot<Int, CGFloat>()
            snapshot.appendSections([0])
            snapshot.appendItems(FontSizePickerViewController.sizes)
            dataSource.apply(snapshot, animatingDifferences: false)
        }

        func setupViews() {
            let tableView = UITableView()
            tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
            dataSource = UITableViewDiffableDataSource(tableView: tableView, cellProvider: { tableView, indexPath, size in
                let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
                var configuration = cell.defaultContentConfiguration()
                configuration.text = "\(size)pt"
                cell.contentConfiguration = configuration
                return cell
            })
            tableView.dataSource = dataSource
            tableView.delegate = self
            tableView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(tableView)

            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: tableView.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: tableView.trailingAnchor),
                view.topAnchor.constraint(equalTo: tableView.topAnchor),
                view.bottomAnchor.constraint(equalTo: tableView.bottomAnchor)
            ])
        }

        func setupNavigationBarIfNeeded() {
            // Check whether this controller is used in UINavigationController container which only contains this controller. Otherwise if this controller was pushed into navigation stack we don't
            // need the cancel button.
            guard let navigationController, navigationController.viewControllers.count == 1 else { return }
            let cancel = UIBarButtonItem(systemItem: .cancel)
            cancel
                .rx
                .tap
                .subscribe(onNext: { [weak self] _ in
                    self?.navigationController?.presentingViewController?.dismiss(animated: true)
                })
                .disposed(by: disposeBag)
            navigationItem.leftBarButtonItem = cancel
        }
    }

    override func loadView() {
        view = UIView()
    }
}

extension FontSizePickerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let size = dataSource.itemIdentifier(for: indexPath) else { return }
        pickAction(size)
        if let controller = navigationController {
            if controller.viewControllers.count == 1 {
                controller.presentingViewController?.dismiss(animated: true)
            } else {
                controller.popViewController(animated: true)
            }
        } else {
            presentingViewController?.dismiss(animated: true)
        }
    }
}
