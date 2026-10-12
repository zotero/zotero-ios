//
//  CarPlayCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 12.10.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import CarPlay
import Combine

import CocoaLumberjackSwift
import RealmSwift
import RxSwift

final class CarPlayCoordinator: NSObject {
    /// Row showing an attachment icon which follows the attachment's download state. Rows are replaced whenever their
    /// template reloads, so they're held weakly.
    private struct AttachmentRow {
        enum Slot {
            /// Accessory image of an item row, like the attachment button in the app's items list.
            case accessory
            /// Image of an attachment row.
            case image
        }

        weak var row: CPListItem?
        var attachment: Attachment
        let parentKey: String?
        let slot: Slot

        var style: FileAttachmentView.Style {
            switch slot {
            case .accessory:
                return .list

            case .image:
                return .detail
            }
        }
    }

    /// Maximum depth of the template stack for audio apps. Pushing past it raises an exception.
    private static let maximumTemplateDepth = 5
    /// Depth available for browsing, one level is left for the processing/Now Playing template.
    private static let maximumBrowsingDepth = maximumTemplateDepth - 1
    /// Content types which can be read aloud.
    private static let readableContentTypes: Set<String> = ["application/pdf", "application/epub+zip", "text/html"]
    /// CarPlay shows only the personal library.
    private static let libraryId: LibraryIdentifier = .custom(.myLibrary)

    private let interfaceController: CPInterfaceController
    private unowned let controllers: Controllers
    private var userInitializedCancellable: AnyCancellable?
    /// Database observations of templates in the stack. Removed when their template leaves the stack.
    private var observations: [ObjectIdentifier: [NotificationToken]] = [:]
    /// Rows showing attachments, keyed by attachment key.
    private var attachmentRows: [String: [AttachmentRow]] = [:]
    /// Attachment which is opened once its download finishes.
    private var attachmentToOpen: String?
    /// Download observing of the logged in user, replaced on login/logout.
    private var downloadDisposeBag = DisposeBag()
    private var readAloudSession: CarPlayReadAloudSession?
    /// Observing of the current read aloud session.
    private var readAloudDisposeBag = DisposeBag()
    /// Shown while the document of the read aloud session is being processed, replaced by Now Playing once reading starts.
    private var processingTemplate: CPListTemplate?

    init(interfaceController: CPInterfaceController, controllers: Controllers) {
        self.interfaceController = interfaceController
        self.controllers = controllers
        super.init()
        interfaceController.delegate = self
    }

    func start() {
        userInitializedCancellable = controllers.userInitialized
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                self?.showRoot(isLoggedIn: (try? result.get()) ?? false)
            }

        if controllers.userControllers != nil {
            showRoot(isLoggedIn: true)
        } else if controllers.didInitialize {
            showRoot(isLoggedIn: false)
        } else {
            // Session is still being initialized, `userInitialized` reports the result.
            setRoot(createMessageTemplate(title: L10n.Carplay.loading, subtitle: nil))
        }
    }

    // MARK: - Navigation

    private func showRoot(isLoggedIn: Bool) {
        stopReadAloud()
        downloadDisposeBag = DisposeBag()
        attachmentRows = [:]
        attachmentToOpen = nil

        guard isLoggedIn, let userControllers = controllers.userControllers else {
            setRoot(createMessageTemplate(title: L10n.Carplay.LoggedOut.title, subtitle: L10n.Carplay.LoggedOut.subtitle))
            return
        }

        userControllers.fileDownloader.observable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] update in
                self?.process(downloadUpdate: update)
            })
            .disposed(by: downloadDisposeBag)

        setRoot(createLibraryTemplate(dbStorage: userControllers.dbStorage))
    }

    private func setRoot(_ template: CPTemplate) {
        // Replacing the root removes all other templates from the stack.
        let identifier = ObjectIdentifier(template)
        observations = observations.filter({ $0.key == identifier })
        interfaceController.setRootTemplate(template, animated: false) { _, error in
            if let error {
                DDLogError("CarPlayCoordinator: can't set root template - \(error)")
            }
        }
    }

    private func push(_ template: CPTemplate, completion: @escaping () -> Void) {
        interfaceController.pushTemplate(template, animated: true) { [weak self] _, error in
            if let error {
                DDLogError("CarPlayCoordinator: can't push template - \(error)")
                self?.observations[ObjectIdentifier(template)] = nil
            }
            completion()
        }
    }

    /// Same as tapping an attachment in the app: cancels its download if it's in progress, otherwise downloads it if needed
    /// and opens it once it's ready.
    private func toggleDownload(attachment: Attachment, parentKey: String?) {
        guard let fileDownloader = controllers.userControllers?.fileDownloader else { return }
        // Rows keep the latest state of the attachment (a finished download makes it local).
        let attachment = attachmentRows[attachment.key]?.first(where: { $0.row != nil })?.attachment ?? attachment

        if fileDownloader.data(for: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId).progress != nil {
            if attachmentToOpen == attachment.key {
                attachmentToOpen = nil
            }
            fileDownloader.cancel(key: attachment.key, parentKey: parentKey, libraryId: attachment.libraryId)
        } else {
            attachmentToOpen = attachment.key
            fileDownloader.downloadIfNeeded(attachment: attachment, parentKey: parentKey, retryIfNeeded: false)
        }
    }

    // MARK: - Read aloud

    /// Reads the downloaded attachment aloud. Only PDFs are supported for now.
    private func open(attachmentKey key: String, parentKey: String?) {
        guard let attachment = attachmentRows[key]?.first(where: { $0.row != nil })?.attachment else { return }
        guard FeatureGates.enabled.contains(.speech),
              case .file(let filename, let contentType, _, _, _) = attachment.type,
              contentType == "application/pdf",
              let userControllers = controllers.userControllers,
              let file = Files.attachmentFile(in: attachment.libraryId, key: attachment.key, filename: filename, contentType: contentType) as? FileData
        else {
            showAlert(title: L10n.Carplay.readAloudUnavailable)
            return
        }

        DDLogInfo("CarPlayCoordinator: read aloud attachment \(key)")
        stopReadAloud()

        // Now Playing shows the parent item, a standalone attachment shows itself.
        let item = try? userControllers.dbStorage.perform(request: ReadItemDbRequest(libraryId: attachment.libraryId, key: parentKey ?? attachment.key), on: .main)
        let session = CarPlayReadAloudSession(
            key: attachment.key,
            libraryId: attachment.libraryId,
            file: file,
            title: item?.displayTitle ?? attachment.title,
            authors: item?.creatorSummary.flatMap({ $0.isEmpty ? nil : $0 }),
            dbStorage: userControllers.dbStorage,
            documentWorkerController: userControllers.documentWorkerController,
            apiClient: controllers.apiClient
        )
        readAloudSession = session
        showProcessing(title: session.documentTitle ?? attachment.title, session: session)
        session.start()

        session.speechManager.state
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                guard let self else { return }
                switch state {
                case .speaking, .paused:
                    showNowPlayingIfProcessing()

                case .outOfCredits:
                    hideProcessing()
                    showAlert(title: L10n.Carplay.outOfCredits)

                case .stopped:
                    // Stopping while the document is still being processed means it couldn't be read.
                    guard processingTemplate != nil else { return }
                    hideProcessing()
                    showAlert(title: L10n.Carplay.processingFailed)

                case .initializing, .loading:
                    break
                }
            })
            .disposed(by: readAloudDisposeBag)
    }

    private func stopReadAloud() {
        readAloudDisposeBag = DisposeBag()
        readAloudSession?.stop()
        readAloudSession = nil
    }

    private func showProcessing(title: String, session: CarPlayReadAloudSession) {
        let row = CPListItem(text: L10n.Carplay.processingDocument, detailText: nil)
        let template = CPListTemplate(title: title, sections: [CPListSection(items: [row])])
        processingTemplate = template
        interfaceController.pushTemplate(template, animated: true) { _, error in
            if let error {
                DDLogError("CarPlayCoordinator: can't push processing template - \(error)")
            }
        }

        session.speechManager.extractionProgress
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { progress in
                row.playbackProgress = CGFloat(progress ?? 0)
            })
            .disposed(by: readAloudDisposeBag)
    }

    private func hideProcessing() {
        guard let processingTemplate else { return }
        // Cleared first, so that disappearing of the template doesn't stop reading.
        self.processingTemplate = nil
        guard interfaceController.topTemplate === processingTemplate else { return }
        interfaceController.popTemplate(animated: true, completion: nil)
    }

    private func showNowPlayingIfProcessing() {
        guard let processingTemplate else { return }
        self.processingTemplate = nil
        let nowPlaying = CPNowPlayingTemplate.shared

        guard interfaceController.topTemplate === processingTemplate else {
            interfaceController.pushTemplate(nowPlaying, animated: true, completion: nil)
            return
        }
        interfaceController.popTemplate(animated: false) { [weak self] _, _ in
            self?.interfaceController.pushTemplate(nowPlaying, animated: true, completion: nil)
        }
    }

    private func showAlert(title: String) {
        let action = CPAlertAction(title: L10n.ok, style: .default) { [weak self] _ in
            self?.interfaceController.dismissTemplate(animated: true, completion: nil)
        }
        interfaceController.presentTemplate(CPAlertTemplate(titleVariants: [title], actions: [action]), animated: true, completion: nil)
    }

    // MARK: - Templates

    private func createMessageTemplate(title: String, subtitle: String?) -> CPListTemplate {
        let template = CPListTemplate(title: L10n.Libraries.myLibrary, sections: [])
        template.emptyViewTitleVariants = [title]
        template.emptyViewSubtitleVariants = subtitle.flatMap({ [$0] }) ?? []
        return template
    }

    private func createLibraryTemplate(dbStorage: DbStorage) -> CPListTemplate {
        let template = CPListTemplate(title: L10n.Libraries.myLibrary, sections: [])

        do {
            let collections = try dbStorage.perform(request: ReadCollectionsDbRequest(libraryId: Self.libraryId), on: .main)
            bind(template, to: [token(for: collections)]) { [weak self] in
                guard let self else { return [] }
                // Same order as the collections list in the app. Trash is left out.
                let rootCollections = [Collection(custom: .all), Collection(custom: .recentlyRead)]
                    + subcollections(of: nil, in: collections).map({ Collection(object: $0) })
                    + [Collection(custom: .publications), Collection(custom: .unfiled)]
                return [CPListSection(items: collectionRows(for: rootCollections, depth: 2, dbStorage: dbStorage, limit: CPListTemplate.maximumItemCount))]
            }
        } catch let error {
            DDLogError("CarPlayCoordinator: can't load collections - \(error)")
        }

        return template
    }

    /// - parameter depth: Depth of the template in the template stack, the root template is at depth 1.
    private func createCollectionTemplate(collection: Collection, depth: Int, dbStorage: DbStorage) -> CPListTemplate {
        let template = CPListTemplate(title: collection.name, sections: [])
        template.emptyViewTitleVariants = [L10n.Carplay.NoItems.title]
        template.emptyViewSubtitleVariants = [L10n.Carplay.NoItems.subtitle]

        do {
            let collections = try dbStorage.perform(request: ReadCollectionsDbRequest(libraryId: Self.libraryId), on: .main)
            let items: Results<RItem>
            // Key of the collection whose subcollections are listed, nil if they are not listed.
            let subcollectionsParentKey: String?

            switch collection.identifier {
            case .collection(let key):
                // A subcollection needs two more templates (its own and the attachments of its items). Deeper
                // subcollections are not shown, their items are listed in this collection instead.
                let showsSubcollections = depth + 2 <= Self.maximumBrowsingDepth
                subcollectionsParentKey = showsSubcollections ? key : nil
                let request = ReadCollectionItemsDbRequest(
                    collectionKey: key,
                    libraryId: Self.libraryId,
                    includeSubcollections: !showsSubcollections || Defaults.shared.showSubcollectionItems,
                    sortType: Defaults.shared.itemsSortType
                )
                items = try dbStorage.perform(request: request, on: .main)

            case .custom, .search:
                subcollectionsParentKey = nil
                let request = ReadItemsDbRequest(collectionId: collection.identifier, libraryId: Self.libraryId, sortType: Defaults.shared.itemsSortType)
                items = try dbStorage.perform(request: request, on: .main)
            }

            bind(template, to: [token(for: collections), token(for: items)]) { [weak self] in
                guard let self else { return [] }
                var sections: [CPListSection] = []
                var remaining = CPListTemplate.maximumItemCount

                if let subcollectionsParentKey {
                    let subcollections = subcollections(of: subcollectionsParentKey, in: collections).map({ Collection(object: $0) })
                    let rows = collectionRows(for: subcollections, depth: depth + 1, dbStorage: dbStorage, limit: remaining)
                    if !rows.isEmpty {
                        sections.append(CPListSection(items: rows, header: L10n.Carplay.subcollections, sectionIndexTitle: nil))
                        remaining -= rows.count
                    }
                }

                let rows = itemRows(for: items, limit: remaining)
                if !rows.isEmpty {
                    sections.append(CPListSection(items: rows, header: sections.isEmpty ? nil : L10n.Carplay.items, sectionIndexTitle: nil))
                }

                return sections
            }
        } catch let error {
            DDLogError("CarPlayCoordinator: can't load collection \(collection.identifier.id) - \(error)")
        }

        return template
    }

    private func createAttachmentsTemplate(title: String, attachments: [Attachment], parentKey: String?) -> CPListTemplate {
        let rows = attachments.prefix(CPListTemplate.maximumItemCount).map { attachment in
            let row = CPListItem(text: attachment.title, detailText: nil, image: nil)
            register(row, attachment: attachment, parentKey: parentKey, slot: .image)
            row.handler = { [weak self] _, completion in
                self?.toggleDownload(attachment: attachment, parentKey: parentKey)
                completion()
            }
            return row
        }
        return CPListTemplate(title: title, sections: [CPListSection(items: Array(rows))])
    }

    // MARK: - Rows

    private func collectionRows(for collections: [Collection], depth: Int, dbStorage: DbStorage, limit: Int) -> [CPListItem] {
        return collections.prefix(limit).map { collection in
            let row = CPListItem(text: collection.name, detailText: nil, image: UIImage(named: collection.iconName), accessoryImage: nil, accessoryType: .disclosureIndicator)
            row.handler = { [weak self] _, completion in
                guard let self else {
                    completion()
                    return
                }
                push(createCollectionTemplate(collection: collection, depth: depth, dbStorage: dbStorage), completion: completion)
            }
            return row
        }
    }

    private func itemRows(for items: Results<RItem>, limit: Int) -> [CPListItem] {
        var rows: [CPListItem] = []

        for item in items {
            guard rows.count < limit else { break }
            let attachments = readableAttachments(for: item)
            guard !attachments.isEmpty else { continue }

            // Like the items list in the app: item type icon, and the item's main attachment as accessory.
            let mainAttachment = AttachmentCreator.mainAttachment(for: item, fileStorage: controllers.fileStorage, urlDetector: nil)
                .flatMap({ main in attachments.first(where: { $0.key == main.key }) }) ?? attachments[0]
            let title = item.displayTitle
            // Standalone attachments have no parent.
            let parentKey = item.rawType == ItemTypes.attachment ? nil : item.key
            let row = CPListItem(
                text: title,
                detailText: item.creatorSummary.flatMap({ $0.isEmpty ? nil : $0 }),
                image: UIImage(named: ItemCellModel.typeIconName(for: item)),
                accessoryImage: nil,
                accessoryType: .none
            )
            register(row, attachment: mainAttachment, parentKey: parentKey, slot: .accessory)
            row.handler = { [weak self] _, completion in
                guard let self else {
                    completion()
                    return
                }
                if attachments.count == 1 {
                    toggleDownload(attachment: attachments[0], parentKey: parentKey)
                    completion()
                } else {
                    push(createAttachmentsTemplate(title: title, attachments: attachments, parentKey: parentKey), completion: completion)
                }
            }
            rows.append(row)
        }

        return rows
    }

    // MARK: - Helpers

    private func subcollections(of parentKey: String?, in collections: Results<RCollection>) -> [RCollection] {
        return collections.filter({ $0.parentKey == parentKey })
            .sorted(by: { $0.name.compare($1.name, options: [.numeric], locale: Locale.autoupdatingCurrent) == .orderedAscending })
    }

    /// Stored PDF, EPUB and HTML attachments of an item, or the item itself if it's such a standalone attachment.
    private func readableAttachments(for item: RItem) -> [Attachment] {
        let candidates: [RItem]
        if item.rawType == ItemTypes.attachment {
            candidates = [item]
        } else {
            candidates = item.children.filter({ $0.rawType == ItemTypes.attachment && $0.syncState != .dirty && !$0.trash && !$0.deleted })
        }

        return candidates
            .compactMap { child -> Attachment? in
                guard let attachment = AttachmentCreator.attachment(for: child, fileStorage: controllers.fileStorage, urlDetector: nil),
                      case .file(_, let contentType, _, let linkType, _) = attachment.type,
                      Self.readableContentTypes.contains(contentType),
                      linkType == .importedFile || linkType == .importedUrl
                else { return nil }
                return attachment
            }
            .sorted(by: { $0.title.compare($1.title, options: [.numeric], locale: Locale.autoupdatingCurrent) == .orderedAscending })
    }

    // MARK: - Downloads

    private func process(downloadUpdate update: AttachmentDownloader.Update) {
        guard update.libraryId == Self.libraryId else { return }

        switch update.kind {
        case .ready(let compressed):
            updateRows(of: update.key, change: { $0.changed(location: .local, compressed: compressed) })
            guard attachmentToOpen == update.key else { return }
            attachmentToOpen = nil
            open(attachmentKey: update.key, parentKey: update.parentKey)

        case .progress:
            // Extraction sends quick progress updates after the download is already finished, those are skipped (same as in
            // the app's items list).
            guard let progress = controllers.userControllers?.fileDownloader.data(for: update.key, parentKey: update.parentKey, libraryId: update.libraryId).progress,
                  progress < 1
            else { return }
            updateRows(of: update.key)

        case .cancelled:
            updateRows(of: update.key)
            if attachmentToOpen == update.key {
                attachmentToOpen = nil
            }

        case .failed(let error):
            DDLogError("CarPlayCoordinator: can't download attachment \(update.key) - \(error)")
            updateRows(of: update.key)
            guard attachmentToOpen == update.key else { return }
            attachmentToOpen = nil
            showAlert(title: L10n.Carplay.downloadFailed)
        }
    }

    private func register(_ row: CPListItem, attachment: Attachment, parentKey: String?, slot: AttachmentRow.Slot) {
        let attachmentRow = AttachmentRow(row: row, attachment: attachment, parentKey: parentKey, slot: slot)
        set(image: image(for: attachmentRow), for: attachmentRow)
        attachmentRows[attachment.key] = (attachmentRows[attachment.key] ?? []).filter({ $0.row != nil }) + [attachmentRow]
    }

    /// Updates icons of rows showing the attachment, changing the attachment first if `change` returns a new one.
    private func updateRows(of key: String, change: ((Attachment) -> Attachment?)? = nil) {
        guard var rows = attachmentRows[key]?.filter({ $0.row != nil }) else { return }
        for index in rows.indices {
            if let changed = change?(rows[index].attachment) {
                rows[index].attachment = changed
            }
            set(image: image(for: rows[index]), for: rows[index])
        }
        attachmentRows[key] = rows.isEmpty ? nil : rows
    }

    private func set(image: UIImage?, for attachmentRow: AttachmentRow) {
        switch attachmentRow.slot {
        case .accessory:
            attachmentRow.row?.setAccessoryImage(image)

        case .image:
            attachmentRow.row?.setImage(image)
        }
    }

    /// Attachment icon like in the app: progress while downloading, otherwise the file type icon with a badge when the file
    /// needs to be downloaded, is missing, or failed to download.
    private func image(for attachmentRow: AttachmentRow) -> UIImage? {
        let attachment = attachmentRow.attachment
        let traitCollection = interfaceController.carTraitCollection
        let (progress, error) = controllers.userControllers?.fileDownloader.data(for: attachment.key, parentKey: attachmentRow.parentKey, libraryId: attachment.libraryId) ?? (nil, nil)
        let state = FileAttachmentView.State.stateFrom(type: attachment.type, progress: progress, error: error)

        guard let assets = FileAttachmentView.assets(for: state, style: attachmentRow.style) else {
            return FileAttachmentView.progressImage(progress: progress ?? 0, traitCollection: traitCollection)
        }

        let main = assets.main.image(compatibleWith: traitCollection)
        guard let badge = assets.badge?.image(compatibleWith: traitCollection) else { return main }

        // The badge is centered on the bottom right corner of the main image, like in `FileAttachmentView`.
        let size = CGSize(width: main.size.width + (badge.size.width / 2), height: main.size.height + (badge.size.height / 2))
        return UIGraphicsImageRenderer(size: size, format: UIGraphicsImageRendererFormat(for: traitCollection)).image { _ in
            main.draw(at: .zero)
            badge.draw(at: CGPoint(x: main.size.width - (badge.size.width / 2), y: main.size.height - (badge.size.height / 2)))
        }
    }

    // MARK: - Observing

    /// Fills `template` with `sections` and refills it whenever any of the observed results change.
    private func bind(_ template: CPListTemplate, to tokens: [(@escaping () -> Void) -> NotificationToken], sections: @escaping () -> [CPListSection]) {
        template.updateSections(sections())
        observations[ObjectIdentifier(template)] = tokens.map { observe in
            observe { [weak template] in
                template?.updateSections(sections())
            }
        }
    }

    private func token<Element: RealmCollectionValue>(for results: Results<Element>) -> (@escaping () -> Void) -> NotificationToken {
        return { update in
            results.observe { changes in
                switch changes {
                case .update:
                    update()

                case .initial:
                    break

                case .error(let error):
                    DDLogError("CarPlayCoordinator: can't observe results - \(error)")
                }
            }
        }
    }
}

extension CarPlayCoordinator: CPInterfaceControllerDelegate {
    func templateDidDisappear(_ aTemplate: CPTemplate, animated: Bool) {
        // Covered templates stay in the stack, only popped ones stop being observed.
        guard !interfaceController.templates.contains(aTemplate) else { return }
        observations[ObjectIdentifier(aTemplate)] = nil

        // Leaving the processing screen cancels reading of the document.
        if aTemplate === processingTemplate {
            processingTemplate = nil
            stopReadAloud()
        }
    }
}
