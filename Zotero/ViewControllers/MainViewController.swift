//
//  MainViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 11/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import MobileCoreServices
import UIKit
import SafariServices
import SwiftUI

import RxSwift

#if PDFENABLED
import PSPDFKit
import PSPDFKitUI
#endif

fileprivate enum PrimaryColumnState {
    case minimum
    case dynamic(CGFloat)
}

class MainViewController: UISplitViewController, ConflictPresenter {
    // Constants
    private static let minPrimaryColumnWidth: CGFloat = 300
    private static let maxPrimaryColumnFraction: CGFloat = 0.4
    private static let averageCharacterWidth: CGFloat = 10.0
    private let defaultLibrary: Library
    private let defaultCollection: Collection
    private let controllers: Controllers
    private let disposeBag: DisposeBag
    // Variables
    private var syncToolbarController: SyncToolbarController?
    private var currentLandscapePrimaryColumnFraction: CGFloat = 0
    private var isViewingLibraries: Bool {
        return (self.viewControllers.first as? UINavigationController)?.viewControllers.count == 1
    }
    private var maxSize: CGFloat {
        return max(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
    }
    private var filesPickedAction: (([URL]) -> Void)?

    // MARK: - Lifecycle

    init(controllers: Controllers) {
        self.defaultLibrary = Library(identifier: .custom(.myLibrary),
                                      name: RCustomLibraryType.myLibrary.libraryName,
                                      metadataEditable: true,
                                      filesEditable: true)
        self.defaultCollection = Collection(custom: .all)
        self.controllers = controllers
        self.disposeBag = DisposeBag()

        super.init(nibName: nil, bundle: nil)

        self.setupControllers()

        self.preferredDisplayMode = .allVisible
        self.minimumPrimaryColumnWidth = MainViewController.minPrimaryColumnWidth
        self.maximumPrimaryColumnWidth = self.maxSize * MainViewController.maxPrimaryColumnFraction

        self.setupNotificationObservers()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.delegate = self
        self.setPrimaryColumn(state: .minimum, animated: false)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        let isLandscape = size.width > size.height
        coordinator.animate(alongsideTransition: { _ in
            if !isLandscape || self.isViewingLibraries {
                self.setPrimaryColumn(state: .minimum, animated: false)
                return
            }
            self.setPrimaryColumn(state: .dynamic(self.currentLandscapePrimaryColumnFraction), animated: false)
        }, completion: nil)
    }

    // MARK: - Actions

    private func presentUnknownAttachment(with url: URL) {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.modalPresentationStyle = .pageSheet
        controller.popoverPresentationController?.sourceView = self.view
        controller.popoverPresentationController?.sourceRect = CGRect(x: (self.view.frame.width / 3.0),
                                                                      y: (self.view.frame.height * 2.0 / 3.0),
                                                                      width: (self.view.frame.width / 3),
                                                                      height: (self.view.frame.height / 3))
        self.present(controller, animated: true, completion: nil)
    }

    private func presentTagPicker(with selectedIds: Set<String>, libraryId: LibraryIdentifier, saveAction: @escaping ([Tag]) -> Void) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }

        let view = TagPickerView(saveAction: saveAction) { [weak self] in
            self?.dismiss(animated: true, completion: nil)
        }
        .environmentObject(TagPickerStore(libraryId: libraryId, selectedTags: selectedIds, dbStorage: dbStorage))

        let controller = UINavigationController(rootViewController: UIHostingController(rootView: view))
        controller.isModalInPresentation = true
        self.present(controller, animated: true, completion: nil)
    }

    private func presentCreatorTypePicker(for itemType: String, creatorType: String, saveAction: @escaping (String) -> Void) {
        let store = CreatorTypePickerStore(itemType: itemType, selected: creatorType, schemaController: self.controllers.schemaController)
        self.presentTypePicker(for: creatorType, store: store, saveAction: saveAction)
    }

    private func presentItemTypePicker(for type: String, saveAction: @escaping (String) -> Void) {
        let store = ItemTypePickerStore(selected: type, schemaController: self.controllers.schemaController)
        self.presentTypePicker(for: type, store: store, saveAction: saveAction)
    }

    private func presentTypePicker<Store: ObservableObject&TypePickerStore>(for type: String,
                                                                            store: Store,
                                                                            saveAction: @escaping (String) -> Void) {
        let view = TypePickerView<Store>(saveAction: saveAction) { [weak self] in
            self?.dismiss(animated: true, completion: nil)
        }
        .environmentObject(store)

        let controller = UINavigationController(rootViewController: UIHostingController(rootView: view))
        controller.isModalInPresentation = true
        self.present(controller, animated: true, completion: nil)
    }

    private func presentNote(_ note: Binding<ItemDetailStore.State.Note>, saveAction: @escaping () -> Void) {
        let view = NoteEditorView(note: note, saveAction: saveAction)
        let controller = UIHostingController(rootView: view)
        controller.isModalInPresentation = true
        self.present(controller, animated: true, completion: nil)
    }

    private func showCollections(for library: Library) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }

        let store = CollectionsStore(library: library, dbStorage: dbStorage)
        let controller = CollectionsViewController(store: store,
                                                   dbStorage: dbStorage,
                                                   dragDropController: self.controllers.dragDropController)
        (self.viewControllers.first as? UINavigationController)?.pushViewController(controller, animated: true)
    }

    private func presentSettings() {
        let store = SettingsStore(sessionController: self.controllers.sessionController)
        let view = SettingsView(closeAction: { [weak self] in
            self?.dismiss(animated: true, completion: nil)
        })
        .environmentObject(store)

        let controller = UIHostingController(rootView: view)
        controller.isModalInPresentation = true
        self.present(controller, animated: true, completion: nil)
    }

    private func presentFilePicker() {
        let documentTypes = [String(kUTTypePDF), String(kUTTypePNG), String(kUTTypeJPEG)]
        let controller = UIDocumentPickerViewController(documentTypes: documentTypes, in: .import)
        controller.delegate = self
        controller.popoverPresentationController?.sourceView = view
        self.present(controller, animated: true, completion: nil)
    }

    private func presentSortTypePicker(field: Binding<ItemsSortType.Field>) {
        let view = ItemSortTypePickerView(sortBy: field,
                                          closeAction: { [weak self] in
                                              self?.dismiss(animated: true, completion: nil)
                                          })
        let navigationController = UINavigationController(rootViewController: UIHostingController(rootView: view))
        navigationController.isModalInPresentation = true
        self.present(navigationController, animated: true, completion: nil)
    }

    private func presentCollectionsPicker(in library: Library, block: @escaping (Set<String>) -> Void) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }

        let view = CollectionsPickerView(selectedKeys: block,
                                         closeAction: { [weak self] in
                                             self?.dismiss(animated: true, completion: nil)
                                         })
                            .environmentObject(CollectionPickerStore(library: library, dbStorage: dbStorage))
        let navigationController = UINavigationController(rootViewController: UIHostingController(rootView: view))
        navigationController.isModalInPresentation = true
        self.present(navigationController, animated: true, completion: nil)
    }

    private func showDuplicateCreation(for key: String, library: Library, collectionKey: String?) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }

        do {
            let request = ReadItemDbRequest(libraryId: library.identifier, key: key)
            let item = try dbStorage.createCoordinator().perform(request: request)

            let store = ItemDetailStore(type: .duplication(item, collectionKey: collectionKey),
                                        userId: Defaults.shared.userId,
                                        apiClient: self.controllers.apiClient,
                                        fileStorage: self.controllers.fileStorage,
                                        dbStorage: dbStorage,
                                        schemaController: self.controllers.schemaController)
            let controller = ItemDetailViewController(store: store)
            (self.viewControllers.last as? UINavigationController)?.pushViewController(controller, animated: true)
        } catch let error {
            // TODO: - show some error
        }
    }

    private func presentPdf(with url: URL) {
        #if PDFENABLED
        let controller = PSPDFViewController(document: PSPDFDocument(url: url))
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = .fullScreen
        self.present(navigationController, animated: true, completion: nil)
        #endif
    }

    private func presentWeb(with url: URL) {
        let controller = SFSafariViewController(url: url)
        self.present(controller, animated: true, completion: nil)
    }

    private func showItems(in collection: Collection, library: Library) {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }
//        let view = ItemsView()
//                        .environment(\.dbStorage, self.controllers.dbStorage)
//                        .environment(\.apiClient, self.controllers.apiClient)
//                        .environment(\.fileStorage, self.controllers.fileStorage)
//                        .environment(\.schemaController, self.controllers.schemaController)
//                        .environmentObject(self.itemsStore(for: collection, library: library))
//        let controller = UIHostingController(rootView: view)
        let controller = ItemsViewController(store: self.itemsStore(for: collection, library: library, dbStorage: dbStorage),
                                             controllers: self.controllers)
        self.showSecondaryController(controller)
    }

    private func showSecondaryController(_ controller: UIViewController) {
        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            let navigationController = self.viewControllers.last as? UINavigationController
            navigationController?.setToolbarHidden(true, animated: false)
            navigationController?.setViewControllers([controller], animated: false)
        case .phone:
            (self.viewControllers.first as? UINavigationController)?.pushViewController(controller, animated: true)
        default: break
        }
    }

    private func itemsStore(for collection: Collection, library: Library, dbStorage: DbStorage) -> ItemsStore {
        let type: ItemsStore.State.ItemType

        switch collection.type {
        case .collection:
            type = .collection(collection.key, collection.name)
        case .search:
            type = .search(collection.key, collection.name)
        case .custom(let customType):
            switch customType {
            case .all:
                type = .all
            case .publications:
                type = .publications
            case .trash:
                type = .trash
            }
        }

        return ItemsStore(type: type,
                          library: library,
                          dbStorage: dbStorage,
                          fileStorage: self.controllers.fileStorage,
                          schemaController: self.controllers.schemaController)
    }

    // MARK: - Dynamic primary column

    private func reloadPrimaryColumnFraction(with data: [Collection], animated: Bool) {
        let newFraction = self.calculatePrimaryColumnFraction(from: data)
        self.currentLandscapePrimaryColumnFraction = newFraction
        if UIDevice.current.orientation.isLandscape {
            self.setPrimaryColumn(state: .dynamic(newFraction), animated: animated)
        }
    }

    private func setPrimaryColumn(state: PrimaryColumnState, animated: Bool) {
        let primaryColumnFraction: CGFloat
        switch state {
        case .minimum:
            primaryColumnFraction = 0.0
        case .dynamic(let fraction):
            primaryColumnFraction = fraction
        }

        guard primaryColumnFraction != self.preferredPrimaryColumnWidthFraction else { return }

        if !animated {
            self.preferredPrimaryColumnWidthFraction = primaryColumnFraction
            return
        }

        UIView.animate(withDuration: 0.2) {
            self.preferredPrimaryColumnWidthFraction = primaryColumnFraction
        }
    }

    private func calculatePrimaryColumnFraction(from collections: [Collection]) -> CGFloat {
        guard !collections.isEmpty else { return 0 }

        var maxCollection: Collection?
        var maxWidth: CGFloat = 0

        collections.forEach { data in
            let width = (CGFloat(data.level) * CollectionRow.levelOffset) +
                        (CGFloat(data.name.count) * MainViewController.averageCharacterWidth)
            if width > maxWidth {
                maxCollection = data
                maxWidth = width
            }
        }

        guard let collection = maxCollection else { return 0 }

        let titleSize = collection.name.size(withAttributes:[.font: UIFont.systemFont(ofSize: 18.0)])
        let actualWidth = titleSize.width + (CGFloat(collection.level) * CollectionRow.levelOffset) + (2 * CollectionRow.levelOffset)

        return min(1.0, (actualWidth / self.maxSize))
    }

    // MARK: - Setups

    private func setupControllers() {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return }

        let librariesView = LibrariesView(pushCollectionsView: { [weak self] library in
                                             self?.showCollections(for: library)
                                         })
                                .environment(\.dbStorage, dbStorage)
                                .environmentObject(LibrariesStore(dbStorage: dbStorage))
        let collectionsStore = CollectionsStore(library: self.defaultLibrary,
                                                dbStorage: dbStorage)
//        let collectionsView = CollectionsView()
//                                    .environment(\.dbStorage, self.controllers.dbStorage)
//                                    .environmentObject(collectionsStore)
        let collectionsController = CollectionsViewController(store: collectionsStore,
                                                              dbStorage: dbStorage,
                                                              dragDropController: self.controllers.dragDropController)

        let masterController = UINavigationController()
        masterController.viewControllers = [UIHostingController(rootView: librariesView),
                                            collectionsController]
//                                            UIHostingController(rootView: collectionsView)]

//        let itemsView = ItemsView()
//                            .environment(\.dbStorage, self.controllers.dbStorage)
//                            .environment(\.apiClient, self.controllers.apiClient)
//                            .environment(\.fileStorage, self.controllers.fileStorage)
//                            .environment(\.schemaController, self.controllers.schemaController)
//                            .environmentObject(self.itemsStore(for: self.defaultCollection,
//                                                               library: self.defaultLibrary))
//        let controller = UIHostingController(rootView: itemsView)
        let controller = ItemsViewController(store: self.itemsStore(for: self.defaultCollection, library: self.defaultLibrary, dbStorage: dbStorage),
                                             controllers: self.controllers)

        let detailController = UINavigationController(rootViewController: controller)

        self.viewControllers = [masterController, detailController]
        self.reloadPrimaryColumnFraction(with: collectionsStore.state.collections, animated: false)

        if let progressObservable = self.controllers.userControllers?.syncScheduler.syncController.progressObservable {
            self.syncToolbarController = SyncToolbarController(parent: masterController, progressObservable: progressObservable)
        }
    }

    private func setupNotificationObservers() {
        let notifications: [Notification.Name] = [.presentPdf, .presentWeb, .splitViewDetailChanged, .showDuplicateCreation,
                                                  .presentCollectionsPicker, .presentSortTypePicker, .presentFilePicker,
                                                  .presentSettings, .presentNote, .presentTypePicker, .presentCreatorPicker,
                                                  .presentTagPicker, .presentUnknownAttachment]

        notifications.forEach { name in
            self.setup(notification: name) { [weak self] notification in
                switch name {
                case .presentPdf:
                    if let url = notification.object as? URL {
                        self?.presentPdf(with: url)
                    }
                case .presentWeb:
                    if let url = notification.object as? URL {
                       self?.presentWeb(with: url)
                    }
                case .splitViewDetailChanged:
                    if let (collection, library) = notification.object as? (Collection, Library) {
                        self?.showItems(in: collection, library: library)
                    }
                case .showDuplicateCreation:
                    if let (key, library, collectionKey) = notification.object as? (String, Library, String?) {
                        self?.showDuplicateCreation(for: key, library: library, collectionKey: collectionKey)
                    }
                case .presentCollectionsPicker:
                    if let (library, block) = notification.object as? (Library, (Set<String>) -> Void) {
                        self?.presentCollectionsPicker(in: library, block: block)
                    }
                case .presentSortTypePicker:
                    if let binding = notification.object as? Binding<ItemsSortType.Field> {
                        self?.presentSortTypePicker(field: binding)
                    }
                case .presentFilePicker:
                    if let action = notification.object as? (([URL]) -> Void) {
                        self?.filesPickedAction = action
                        self?.presentFilePicker()
                    }
                case .presentSettings:
                    self?.presentSettings()
                case .presentNote:
                    if let (note, block) = notification.object as? (Binding<ItemDetailStore.State.Note>, () -> Void) {
                        self?.presentNote(note, saveAction: block)
                    }
                case .presentTypePicker:
                    if let (selected, block) = notification.object as? (String, (String) -> Void) {
                        self?.presentItemTypePicker(for: selected, saveAction: block)
                    }
                case .presentCreatorPicker:
                    if let (itemType, selected, block) = notification.object as? (String, String, (String) -> Void) {
                        self?.presentCreatorTypePicker(for: itemType, creatorType: selected, saveAction: block)
                    }
                case .presentTagPicker:
                    if let (tags, libraryId, block) = notification.object as? (Set<String>, LibraryIdentifier, ([Tag]) -> Void) {
                       self?.presentTagPicker(with: tags, libraryId: libraryId, saveAction: block)
                    }
                case .presentUnknownAttachment:
                    if let url = notification.object as? URL {
                        self?.presentUnknownAttachment(with: url)
                    }

                default: break
                }
            }
        }
    }

    private func setup(notification: Notification.Name, received: @escaping (Notification) -> Void) {
        NotificationCenter.default.rx.notification(notification)
                                     .observeOn(MainScheduler.instance)
                                     .subscribe(onNext: { notification in
                                         received(notification)
                                     })
                                     .disposed(by: self.disposeBag)
    }
}

extension MainViewController: UISplitViewControllerDelegate {
    func splitViewController(_ splitViewController: UISplitViewController,
                             collapseSecondary secondaryViewController: UIViewController,
                             onto primaryViewController: UIViewController) -> Bool {
        return true
    }
}

extension MainViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        self.filesPickedAction?(urls)
        self.filesPickedAction = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.dismiss(animated: true, completion: nil)
        self.filesPickedAction = nil
    }
}
