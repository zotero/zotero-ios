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

@MainActor
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

    /// Content types which can be read aloud.
    private static let readableContentTypes: Set<String> = ["application/pdf"]
    /// Maximum depth of the template stack for audio apps. Pushing past it raises an exception.
    private static let maximumTemplateDepth = 5

    private static let progressFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        return formatter
    }()
    /// CarPlay shows only the personal library.
    private static let libraryId: LibraryIdentifier = .custom(.myLibrary)

    private let interfaceController: CPInterfaceController
    private unowned let controllers: Controllers
    private var userInitializedCancellable: AnyCancellable?
    private var userWillLogOutCancellable: AnyCancellable?
    /// Database observations of templates in the stack. Removed when their template leaves the stack.
    private var observations: [ObjectIdentifier: [NotificationToken]] = [:]
    /// Rows showing attachments, keyed by attachment key.
    private var attachmentRows: [String: [AttachmentRow]] = [:]
    /// Attachment which is opened once its download finishes.
    private var attachmentToOpen: String?
    /// Download observing of the logged in user, replaced on login/logout.
    private var downloadDisposeBag = DisposeBag()
    private var readAloudSession: CarPlayReadAloudSession?
    /// Identifies the current attempt to start reading. Navigation is asynchronous, so its completions check it and do
    /// nothing once reading was stopped or replaced in the meantime.
    private var activeSessionId: UUID?
    /// Observing of the current read aloud session.
    private var readAloudDisposeBag = DisposeBag()
    /// Shown while the document of the read aloud session is being processed, replaced by Now Playing once reading starts.
    private var processingTemplate: CPListTemplate?
    /// Voice settings opened from Now Playing.
    private var voiceSettings: CarPlayVoiceSettings?
    /// Whether reading should resume once the voice settings close, like `ReadAloudViewHandler.wasPlayingBeforeVoiceChange`.
    private var wasPlayingBeforeVoiceSettings = false
    /// Whether Now Playing was shown for the current session, i.e. reading has started. Voice settings opened before that
    /// (from the alert shown when the voice has no credits left at startup) start reading again with the new voice.
    private var didShowNowPlaying = false

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
        // Read aloud depends on user controllers, so it's stopped synchronously, before they're released on logout.
        // `userInitialized` reports the logout only after they're released and the root is reset on the next main queue pass.
        userWillLogOutCancellable = controllers.userWillLogOut
            .sink { [weak self] in
                self?.stopReadAloud()
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

    /// Reads the downloaded attachment aloud.
    private func open(attachmentKey key: String, parentKey: String?) {
        guard let attachment = attachmentRows[key]?.first(where: { $0.row != nil })?.attachment else { return }
        guard FeatureGates.enabled.contains(.speech),
              case .file(let filename, let contentType, _, _, _) = attachment.type,
              Self.readableContentTypes.contains(contentType),
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
        let title = item?.displayTitle ?? attachment.title
        let authors = item?.creatorSummary.flatMap({ $0.isEmpty ? nil : $0 })
        let session = CarPlayReadAloudSession(
            key: attachment.key,
            libraryId: attachment.libraryId,
            file: file,
            title: title,
            authors: authors,
            dbStorage: userControllers.dbStorage,
            lastReadWatcher: userControllers.lastReadWatcher,
            speechPlaybackOwnership: controllers.speechPlaybackOwnership,
            documentWorkerController: userControllers.documentWorkerController,
            documentPreviewController: controllers.documentPreviewController,
            apiClient: controllers.apiClient
        )
        readAloudSession = session
        session.onPlaybackTakenOver = { [weak self] in
            self?.readAloudTakenOver()
        }
        observeState(of: session)
        startReadAloud(session: session)
    }

    /// Shows the processing screen and starts reading once it's shown. State changes of the session replace or remove the
    /// processing screen, so they can't arrive before it's pushed.
    private func startReadAloud(session: CarPlayReadAloudSession) {
        let sessionId = UUID()
        activeSessionId = sessionId
        showProcessing(title: session.documentTitle ?? "", session: session, sessionId: sessionId) { [weak self, weak session] in
            guard let self, activeSessionId == sessionId, let session else { return }
            session.start()
        }
    }

    private func observeState(of session: CarPlayReadAloudSession) {
        session.state
            // The current state of a session which wasn't started yet isn't a result of reading.
            .skip(1)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                guard let self else { return }
                switch state {
                case .speaking, .paused:
                    showNowPlayingIfProcessing()

                case .outOfCredits:
                    hideProcessing()
                    // Switching to another voice (e.g. a free local one) is the way to continue. When credits run out at
                    // startup, the Now Playing buttons with voice settings aren't shown yet, so they're offered here.
                    showAlert(title: L10n.Carplay.outOfCredits, offersVoiceSettings: readAloudSession?.voice != nil)

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

    // MARK: - Voice settings

    private func showVoiceSettings() {
        guard voiceSettings == nil, let session = readAloudSession, let voice = session.voice else { return }
        // Now Playing is normally right above the collection, but CarPlay's own Now Playing button can push it anywhere. The
        // settings and language screens have to fit under the template depth limit, pushing past it raises an exception.
        let depth = interfaceController.templates.count
        guard depth + 1 <= Self.maximumTemplateDepth else {
            DDLogWarn("CarPlayCoordinator: no room for voice settings at depth \(depth)")
            return
        }
        let state = session.state.value
        wasPlayingBeforeVoiceSettings = state.isSpeakingOrLoading || state.isOutOfCredits
        session.pause()

        let settings = CarPlayVoiceSettings(
            interfaceController: interfaceController,
            selectedVoice: voice,
            language: session.language,
            detectedLanguage: session.detectedLanguage,
            remoteVoicesController: session.remoteVoicesController,
            allowsLanguageScreen: depth + 2 <= Self.maximumTemplateDepth
        )
        voiceSettings = settings
        interfaceController.pushTemplate(settings.settingsTemplate, animated: true) { [weak self] _, error in
            guard let error else { return }
            DDLogError("CarPlayCoordinator: can't push voice settings - \(error)")
            self?.closeVoiceSettings()
        }
    }

    /// Applies the selected voice and resumes reading, like `ReadAloudViewHandler` does when the voice picker closes.
    private func closeVoiceSettings() {
        guard let settings = voiceSettings else { return }
        voiceSettings = nil
        settings.stopSamples()
        let change = settings.voiceChange
        if let change {
            readAloudSession?.apply(voiceChange: change)
        }
        guard wasPlayingBeforeVoiceSettings else { return }
        wasPlayingBeforeVoiceSettings = false
        if didShowNowPlaying {
            readAloudSession?.resume()
        } else if change != nil, let session = readAloudSession {
            // Reading didn't start (the voice had no credits), so it starts again with the new voice, the same way as when
            // the document was opened.
            startReadAloud(session: session)
        }
    }

    private func stopReadAloud() {
        voiceSettings?.stopSamples()
        voiceSettings = nil
        wasPlayingBeforeVoiceSettings = false
        didShowNowPlaying = false
        // Pending navigation of the stopped session is ignored.
        activeSessionId = nil
        processingTemplate = nil
        readAloudDisposeBag = DisposeBag()
        readAloudSession?.stop()
        readAloudSession = nil
    }

    /// Reading was started elsewhere (e.g. in the reader on the phone). That session takes over Now Playing, so only the UI
    /// of this session is closed.
    private func readAloudTakenOver() {
        DDLogInfo("CarPlayCoordinator: read aloud taken over")
        hideProcessing()
        // Custom Now Playing buttons control this session.
        CPNowPlayingTemplate.shared.updateNowPlayingButtons([])
        stopReadAloud()
    }

    /// Shows the processing screen, `completion` is called once it's pushed (unless reading was stopped or replaced).
    private func showProcessing(title: String, session: CarPlayReadAloudSession, sessionId: UUID, completion: @escaping () -> Void) {
        // CarPlay audio apps can't show custom views. A list without rows shows its empty view title and subtitle centered on
        // the screen, so it's used to show the processing message with progress below it. The only progress bar CarPlay has is
        // the one of a list row, which isn't centered, so the progress bar is drawn with text characters.
        let template = CPListTemplate(title: title, sections: [])
        template.emptyViewTitleVariants = [L10n.Carplay.processingDocument]
        template.emptyViewSubtitleVariants = []
        processingTemplate = template

        // Processing and Now Playing are shown right above the collection (the attachments screen is closed), so that voice
        // settings and its language screen fit under the template depth limit of CarPlay (5).
        let templates = interfaceController.templates
        if templates.count > 2 {
            interfaceController.pop(to: templates[1], animated: false) { [weak self] _, _ in
                guard let self, activeSessionId == sessionId else { return }
                push(processingTemplate: template, sessionId: sessionId, completion: completion)
            }
        } else {
            push(processingTemplate: template, sessionId: sessionId, completion: completion)
        }

        session.extractionProgress
            .observe(on: MainScheduler.instance)
            // Progress is unknown (`nil`) until extraction reports it, then only the message is shown.
            .map({ progress -> Int? in progress.flatMap({ Int((min(max($0, 0), 1) * 100).rounded(.down)) }) })
            // Extraction reports progress often, the template is updated only when the shown percentage changes.
            .distinctUntilChanged()
            .subscribe(onNext: { [weak template] percentage in
                template?.emptyViewSubtitleVariants = percentage.flatMap({ Self.progressVariants(percentage: $0) }) ?? []
            })
            .disposed(by: readAloudDisposeBag)
    }

    /// Progress bar drawn with text characters followed by the percentage, e.g. "▰▰▰▰▱▱▱▱▱▱  42 %". CarPlay picks the
    /// longest variant that fits, so the percentage alone is the fallback.
    private static func progressVariants(percentage: Int) -> [String] {
        let segmentCount = 10
        let filledCount = min(segmentCount, percentage * segmentCount / 100)
        let bar = String(repeating: "▰", count: filledCount) + String(repeating: "▱", count: segmentCount - filledCount)
        guard let text = progressFormatter.string(from: NSNumber(value: Double(percentage) / 100)) else { return [bar] }
        return ["\(bar)  \(text)", text]
    }

    private func push(processingTemplate template: CPListTemplate, sessionId: UUID, completion: @escaping () -> Void) {
        interfaceController.pushTemplate(template, animated: true) { [weak self] success, error in
            guard let self else { return }
            let didPush = success && error == nil
            if !didPush {
                DDLogError("CarPlayCoordinator: can't push processing template - \(String(describing: error))")
            }
            guard activeSessionId == sessionId, processingTemplate === template else {
                // Reading was stopped or replaced while the screen was being pushed, nothing else would remove it.
                if didPush && interfaceController.topTemplate === template {
                    interfaceController.popTemplate(animated: true, completion: nil)
                }
                return
            }
            guard didPush else {
                // Reading starts only with the processing screen shown, it's what Now Playing replaces and what cancels
                // reading when closed.
                stopReadAloud()
                showAlert(title: L10n.Carplay.processingFailed)
                return
            }
            completion()
        }
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
        didShowNowPlaying = true
        let nowPlaying = CPNowPlayingTemplate.shared
        var buttons: [CPNowPlayingButton] = []
        if let image = UIImage(systemName: "chevron.backward.2") {
            buttons.append(CPNowPlayingImageButton(image: image) { [weak self] _ in
                self?.readAloudSession?.startFromBeginning()
            })
        }
        if let image = UIImage(systemName: "gearshape") {
            buttons.append(CPNowPlayingImageButton(image: image) { [weak self] _ in
                self?.showVoiceSettings()
            })
        }
        nowPlaying.updateNowPlayingButtons(buttons)

        guard interfaceController.topTemplate === processingTemplate else {
            interfaceController.pushTemplate(nowPlaying, animated: true, completion: nil)
            return
        }
        let sessionId = activeSessionId
        interfaceController.popTemplate(animated: false) { [weak self] _, _ in
            guard let self, activeSessionId == sessionId else { return }
            interfaceController.pushTemplate(nowPlaying, animated: true, completion: nil)
        }
    }

    private func showAlert(title: String, offersVoiceSettings: Bool = false) {
        var actions: [CPAlertAction] = []
        if offersVoiceSettings {
            let sessionId = activeSessionId
            actions.append(CPAlertAction(title: L10n.Carplay.voiceSettings, style: .default) { [weak self] _ in
                self?.interfaceController.dismissTemplate(animated: true) { _, _ in
                    // Settings belong to the session which showed the alert.
                    guard let self, activeSessionId == sessionId else { return }
                    showVoiceSettings()
                }
            })
        }
        actions.append(CPAlertAction(title: L10n.ok, style: offersVoiceSettings ? .cancel : .default) { [weak self] _ in
            self?.interfaceController.dismissTemplate(animated: true, completion: nil)
        })
        interfaceController.presentTemplate(CPAlertTemplate(titleVariants: [title], actions: actions), animated: true, completion: nil)
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
            let collections = try dbStorage.perform(request: ReadCarPlayCollectionsDbRequest(libraryId: Self.libraryId), on: .main)
            bind(template, to: [token(for: collections)]) { [weak self] in
                guard let self else { return [] }
                // Collections marked to be shown in CarPlay are listed without hierarchy, between the custom collections
                // in the same order as in the app.
                let sortedCollections = collections
                    .sorted(by: { $0.name.compare($1.name, options: [.numeric], locale: Locale.autoupdatingCurrent) == .orderedAscending })
                    .map({ Collection(object: $0) })
                let rootCollections = [Collection(custom: .recentlyRead)] + sortedCollections + [Collection(custom: .publications)]
                return [CPListSection(items: collectionRows(for: rootCollections, dbStorage: dbStorage, limit: CPListTemplate.maximumItemCount))]
            }
        } catch let error {
            DDLogError("CarPlayCoordinator: can't load collections - \(error)")
        }

        return template
    }

    private func createCollectionTemplate(collection: Collection, dbStorage: DbStorage) -> CPListTemplate {
        let template = CPListTemplate(title: collection.name, sections: [])
        template.emptyViewTitleVariants = [L10n.Carplay.NoItems.title]
        template.emptyViewSubtitleVariants = [L10n.Carplay.NoItems.subtitle]

        do {
            let items: Results<RItem>
            switch collection.identifier {
            case .collection(let key):
                // Subcollections are not listed, so their items are always shown in the collection.
                let request = ReadCollectionItemsDbRequest(collectionKey: key, libraryId: Self.libraryId, includeSubcollections: true, sortType: Defaults.shared.itemsSortType)
                items = try dbStorage.perform(request: request, on: .main)

            case .custom, .search:
                let request = ReadItemsDbRequest(collectionId: collection.identifier, libraryId: Self.libraryId, sortType: Defaults.shared.itemsSortType)
                items = try dbStorage.perform(request: request, on: .main)
            }

            bind(template, to: [token(for: items)]) { [weak self] in
                guard let self else { return [] }
                let rows = itemRows(for: items, limit: CPListTemplate.maximumItemCount)
                return rows.isEmpty ? [] : [CPListSection(items: rows)]
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

    private func collectionRows(for collections: [Collection], dbStorage: DbStorage, limit: Int) -> [CPListItem] {
        return collections.prefix(limit).map { collection in
            let row = CPListItem(text: collection.name, detailText: nil, image: templateIconImage(named: collection.iconName), accessoryImage: nil, accessoryType: .disclosureIndicator)
            row.handler = { [weak self] _, completion in
                guard let self else {
                    completion()
                    return
                }
                push(createCollectionTemplate(collection: collection, dbStorage: dbStorage), completion: completion)
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
                image: iconImage(named: ItemCellModel.typeIconName(for: item)),
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

    /// Stored attachments of an item which can be read aloud, or the item itself if it's such a standalone attachment.
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
        let badge = assets.badge?.image(compatibleWith: traitCollection)

        // Drawn into the same area as `FileAttachmentView`: the main image centered and the badge centered on its bottom right
        // corner. CarPlay shows images in their own size, so all icons need the same size.
        let size = CGSize(width: FileAttachmentView.size, height: FileAttachmentView.size)
        return UIGraphicsImageRenderer(size: size, format: UIGraphicsImageRendererFormat(for: traitCollection)).image { _ in
            let mainOrigin = CGPoint(x: (size.width - main.size.width) / 2, y: (size.height - main.size.height) / 2)
            main.draw(at: mainOrigin)
            guard let badge else { return }
            let badgeCenter = CGPoint(x: mainOrigin.x + main.size.width - 0.5, y: mainOrigin.y + main.size.height - 0.5)
            badge.draw(at: CGPoint(x: badgeCenter.x - (badge.size.width / 2), y: badgeCenter.y - (badge.size.height / 2)))
        }
    }

    /// Item type icon drawn into the same area as in the app's lists (scaled to fit 28x28). CarPlay shows images in their own
    /// size and icons differ in size (PNG and SVG assets), so they'd show in different sizes otherwise.
    private func iconImage(named name: String) -> UIImage? {
        return iconImage(named: name, traitCollection: interfaceController.carTraitCollection, tintColor: nil)
    }

    /// Template (single color) icon, like collection icons, which the app tints. Their assets are black, so they'd be barely
    /// visible on CarPlay's dark background. They're tinted with the label color instead, with a variant for both light and
    /// dark appearance, so that CarPlay picks the matching one when the car switches between them (e.g. day and night mode).
    private func templateIconImage(named name: String) -> UIImage? {
        let carTraitCollection = interfaceController.carTraitCollection
        let asset = UIImageAsset()
        var registeredImage = false
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traitCollection = Self.traitCollection(carTraitCollection, with: style)
            guard let image = iconImage(named: name, traitCollection: traitCollection, tintColor: UIColor.label.resolvedColor(with: traitCollection)) else { continue }
            // The scale has to be registered too. Without it the asset resolves the image as 1x, so a 28pt @3x icon is shown as
            // 84pt.
            let assetTraitCollection = Self.traitCollection(UITraitCollection(displayScale: image.scale), with: style)
            asset.register(image, with: assetTraitCollection)
            registeredImage = true
        }
        guard registeredImage else { return nil }
        // CarPlay is dark unless the car tells otherwise.
        let style: UIUserInterfaceStyle = carTraitCollection.userInterfaceStyle == .light ? .light : .dark
        return asset.image(with: Self.traitCollection(carTraitCollection, with: style))
    }

    private static func traitCollection(_ traitCollection: UITraitCollection, with style: UIUserInterfaceStyle) -> UITraitCollection {
        if #available(iOS 17.0, *) {
            return traitCollection.modifyingTraits { $0.userInterfaceStyle = style }
        }
        return UITraitCollection(traitsFrom: [traitCollection, UITraitCollection(userInterfaceStyle: style)])
    }

    /// Icon drawn into 28x28 area. If `tintColor` is set, the icon is drawn as a template in given color.
    private func iconImage(named name: String, traitCollection: UITraitCollection, tintColor: UIColor?) -> UIImage? {
        guard var image = UIImage(named: name, in: nil, compatibleWith: traitCollection), image.size.width > 0, image.size.height > 0 else { return nil }
        if let tintColor {
            image = image.withTintColor(tintColor, renderingMode: .alwaysOriginal)
        }
        let size = CGSize(width: 28, height: 28)
        let scale = min(size.width / image.size.width, size.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size, format: UIGraphicsImageRendererFormat(for: traitCollection)).image { _ in
            image.draw(in: CGRect(origin: CGPoint(x: (size.width - drawSize.width) / 2, y: (size.height - drawSize.height) / 2), size: drawSize))
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

        // Voice settings close once both their screens are gone.
        if let voiceSettings,
           !interfaceController.templates.contains(voiceSettings.settingsTemplate),
           !(voiceSettings.languageTemplate.flatMap({ interfaceController.templates.contains($0) }) ?? false) {
            closeVoiceSettings()
        }
    }
}
