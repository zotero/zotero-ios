//
//  HtmlEpubReaderActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 14.09.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import RealmSwift

final class HtmlEpubReaderActionHandler: ViewModelActionHandler, BackgroundDbProcessingActionHandler {
    typealias Action = HtmlEpubReaderAction
    typealias State = HtmlEpubReaderState

    unowned let dbStorage: DbStorage
    private unowned let schemaController: SchemaController
    private unowned let htmlAttributedStringConverter: HtmlAttributedStringConverter
    private unowned let dateParser: DateParser
    private unowned let fileStorage: FileStorage
    private unowned let idleTimerController: IdleTimerController
    let backgroundQueue: DispatchQueue

    init(
        dbStorage: DbStorage,
        schemaController: SchemaController,
        htmlAttributedStringConverter: HtmlAttributedStringConverter,
        dateParser: DateParser,
        fileStorage: FileStorage,
        idleTimerController: IdleTimerController
    ) {
        self.dbStorage = dbStorage
        self.schemaController = schemaController
        self.htmlAttributedStringConverter = htmlAttributedStringConverter
        self.dateParser = dateParser
        self.fileStorage = fileStorage
        self.idleTimerController = idleTimerController
        backgroundQueue = DispatchQueue(label: "org.zotero.Zotero.HtmlEpubReaderActionHandler.queue", qos: .userInteractive)
    }

    func process(action: HtmlEpubReaderAction, in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        switch action {
        case .toggleTool(let tool):
            toggle(tool: tool, in: viewModel)

        case .initialiseReader:
            initialise(in: viewModel)

        case .deinitialiseReader:
            deinitialise(in: viewModel)

        case .loadDocument:
            load(in: viewModel)

        case .removeAnnotation(let key):
            removeAnnotation(key: key, in: viewModel)

        case .saveAnnotations(let params):
            saveAnnotations(params: params, in: viewModel)

        case .searchAnnotations(let term):
            searchAnnotations(for: term, in: viewModel)

        case .searchDocument(let term):
            update(viewModel: viewModel) { state in
                state.documentSearchTerm = term
            }

        case .selectAnnotationFromSidebar(let key):
            update(viewModel: viewModel) { state in
                _select(key: key, didSelectInDocument: false, state: &state)
            }

        case .selectAnnotationFromDocument(let key):
            update(viewModel: viewModel) { state in
                _select(key: key, didSelectInDocument: true, state: &state)
            }

        case .showAnnotationPopover(let key, let rect):
            update(viewModel: viewModel) { state in
                state.annotationPopoverKey = key
                state.annotationPopoverRect = rect
                state.changes.insert(.popover)
            }

        case .hideAnnotationPopover:
            update(viewModel: viewModel) { state in
                state.annotationPopoverKey = nil
                state.annotationPopoverRect = nil
                state.changes.insert(.popover)
            }

        case .setComment(let key, let comment):
            set(comment: comment, key: key, viewModel: viewModel)

        case .setCommentActive(let isActive):
            update(viewModel: viewModel) { state in
                state.selectedAnnotationCommentActive = isActive
            }

        case .setTags(let key, let tags):
            set(tags: tags, to: key, in: viewModel)

        case .deselectSelectedAnnotation:
            update(viewModel: viewModel) { state in
                _select(key: nil, didSelectInDocument: false, state: &state)
            }

        case .parseAndCacheComment(key: let key, comment: let comment):
            update(viewModel: viewModel, notifyListeners: false) { state in
                state.comments[key] = self.htmlAttributedStringConverter.convert(text: comment, baseAttributes: [.font: viewModel.state.commentFont])
            }

        case .parseAndCacheText(let key, let text, let font):
            updateTextCache(key: key, text: text, font: font, viewModel: viewModel)

        case .updateAnnotationProperties(let key, let color, let lineWidth, let pageLabel, let updateSubsequentLabels, let highlightText):
            set(color: color, lineWidth: lineWidth, pageLabel: pageLabel, updateSubsequentLabels: updateSubsequentLabels, highlightText: highlightText, key: key, viewModel: viewModel)

        case .setColor(key: let key, color: let color):
            set(color: color, key: key, viewModel: viewModel)

        case .setViewState(let params):
            setViewState(params: params, in: viewModel)

        case .setToolOptions(let color, let size, let tool):
            setTool(color: color, size: size, tool: tool, in: viewModel)

        case .setSidebarEditingEnabled(let isEnabled):
            setSidebar(editing: isEnabled, in: viewModel)

        case .removeSelectedAnnotations:
            removeSelectedAnnotations(in: viewModel)

        case .selectAnnotationDuringEditing(let key):
            selectDuringEditing(key: key, in: viewModel)

        case .deselectAnnotationDuringEditing(let key):
            deselectDuringEditing(key: key, in: viewModel)

        case .changeFilter(let filter):
            set(filter: filter, in: viewModel)

        case .setSettings(let settings):
            set(settings: settings, in: viewModel)

        case .changeIdleTimerDisabled(let disabled):
            changeIdleTimer(disabled: disabled, in: viewModel)
        }
    }

    private func updateTextCache(key: String, text: String, font: UIFont, viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        update(viewModel: viewModel, notifyListeners: false) { state in
            var (cachedText, attributedTextByFont) = state.texts[key, default: (text, [:])]
            if cachedText != text {
                attributedTextByFont = [:]
            }
            attributedTextByFont[font] = htmlAttributedStringConverter.convert(text: text, baseAttributes: [.font: font])
            state.texts[key] = (text, attributedTextByFont)
        }
    }

    private func changeIdleTimer(disabled: Bool, in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        guard viewModel.state.settings.idleTimerDisabled != disabled else { return }
        var settings = viewModel.state.settings
        settings.idleTimerDisabled = disabled

        update(viewModel: viewModel) { state in
            state.settings = settings
            // Don't need to assign `changes` or update Defaults.shared.htmlEpubSettings, this setting is not stored and doesn't change anything else
        }

        if settings.idleTimerDisabled {
            idleTimerController.disable()
        } else {
            idleTimerController.enable()
        }
    }

    private func set(settings: HtmlEpubSettings, in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        if viewModel.state.settings.idleTimerDisabled != settings.idleTimerDisabled {
            if settings.idleTimerDisabled {
                idleTimerController.disable()
            } else {
                idleTimerController.enable()
            }
        }

        update(viewModel: viewModel) { state in
            state.settings = settings
            state.changes = .settings
        }

        Defaults.shared.htmlEpubSettings = settings
    }

    private func removeAnnotation(key: String, in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        if viewModel.state.selectedAnnotationKey == key {
            update(viewModel: viewModel) { state in
                _select(key: nil, didSelectInDocument: false, state: &state)
                state.annotationPopoverKey = nil
                state.annotationPopoverRect = nil
                state.changes.insert(.popover)
            }
        }
        remove(keys: [key], in: viewModel)
    }

    private func removeSelectedAnnotations(in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        guard !viewModel.state.selectedAnnotationsDuringEditing.isEmpty else { return }
        let keys = viewModel.state.selectedAnnotationsDuringEditing

        update(viewModel: viewModel) { state in
            state.deletionEnabled = false
            state.selectedAnnotationsDuringEditing = []
            state.changes = .sidebarEditingSelection
        }

        remove(keys: Array(keys), in: viewModel)
    }

    private func setSidebar(editing enabled: Bool, in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        update(viewModel: viewModel) { state in
            state.sidebarEditingEnabled = enabled
            state.changes = .sidebarEditing

            if enabled {
                // Deselect selected annotation before editing
                _select(key: nil, didSelectInDocument: false, state: &state)
            } else {
                // Deselect selected annotations during editing
                state.selectedAnnotationsDuringEditing = []
                state.deletionEnabled = false
            }
        }
    }

    private func selectDuringEditing(key: String, in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        guard let annotation = viewModel.state.annotations[key] else { return }

        let annotationDeletable = annotation.editability(currentUserId: viewModel.state.userId, library: viewModel.state.library) != .notEditable

        update(viewModel: viewModel) { state in
            if state.selectedAnnotationsDuringEditing.isEmpty {
                state.deletionEnabled = annotationDeletable
            } else {
                state.deletionEnabled = state.deletionEnabled && annotationDeletable
            }

            state.selectedAnnotationsDuringEditing.insert(key)
            state.changes = .sidebarEditingSelection
        }
    }

    private func deselectDuringEditing(key: String, in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        update(viewModel: viewModel) { state in
            state.selectedAnnotationsDuringEditing.remove(key)

            if state.selectedAnnotationsDuringEditing.isEmpty {
                if state.deletionEnabled {
                    state.deletionEnabled = false
                    state.changes = .sidebarEditingSelection
                }
            } else {
                // Check whether deletion state changed after removing this annotation
                let deletionEnabled = selectedAnnotationsDeletable(selected: state.selectedAnnotationsDuringEditing, in: viewModel)
                if state.deletionEnabled != deletionEnabled {
                    state.deletionEnabled = deletionEnabled
                    state.changes = .sidebarEditingSelection
                }
            }
        }

        func selectedAnnotationsDeletable(selected: Set<String>, in viewModel: ViewModel<HtmlEpubReaderActionHandler>) -> Bool {
            return !selected.contains(where: { key in
                guard let annotation = viewModel.state.annotations[key] else { return false }
                return annotation.editability(currentUserId: viewModel.state.userId, library: viewModel.state.library) == .notEditable
            })
        }
    }

    private func setTool(color: String?, size: CGFloat?, tool: AnnotationTool, in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        update(viewModel: viewModel) { state in
            state.toolColors[tool] = color.flatMap({ UIColor(hex: $0) })
            state.changes = .toolColor
        }
    }

    private func setViewState(params: [String: Any], in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        guard let state = params["state"] as? [String: Any] else {
            DDLogError("HtmlEpubReaderActionHandler: invalid params - \(params)")
            return
        }

        let page: String
        if let scrollPercent = state["scrollYPercent"] as? Double {
            page = "\(Decimal(scrollPercent).rounded(to: 1))"
        } else if let cfi = state["cfi"] as? String {
            page = cfi
        } else {
            return
        }

        let request = StorePageForItemDbRequest(key: viewModel.state.key, libraryId: viewModel.state.library.identifier, page: page)
        perform(request: request) { error in
            guard let error else { return }
            // TODO: - handle error
            DDLogError("HtmlEpubReaderActionHandler: can't store page - \(error)")
        }
    }

    private func remove(keys: [String], in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        DDLogInfo("HtmlEpubReaderActionHandler: annotations deleted - keys=\(keys)")

        guard !keys.isEmpty else { return }

        let request = MarkObjectsAsDeletedDbRequest<RItem>(keys: keys, libraryId: viewModel.state.library.identifier)
        perform(request: request) { [weak self, weak viewModel] error in
            guard let self, let error, let viewModel else { return }

            DDLogError("HtmlEpubReaderActionHandler: can't remove annotations \(keys) - \(error)")

            update(viewModel: viewModel) { state in
                state.error = .cantDeleteAnnotation
            }
        }
    }

    private func set(
        color: String,
        lineWidth: CGFloat,
        pageLabel: String,
        updateSubsequentLabels: Bool,
        highlightText: NSAttributedString,
        key: String,
        viewModel: ViewModel<HtmlEpubReaderActionHandler>
    ) {
        let text = htmlAttributedStringConverter.convert(attributedString: highlightText)
        let values = [
            KeyBaseKeyPair(key: FieldKeys.Item.Annotation.pageLabel, baseKey: nil): pageLabel,
            KeyBaseKeyPair(key: FieldKeys.Item.Annotation.text, baseKey: nil): text,
            KeyBaseKeyPair(key: FieldKeys.Item.Annotation.color, baseKey: nil): color,
            KeyBaseKeyPair(key: FieldKeys.Item.Annotation.Position.lineWidth, baseKey: FieldKeys.Item.Annotation.position): "\(Decimal(lineWidth).rounded(to: 3))"
        ]
        let request = EditItemFieldsDbRequest(key: key, libraryId: viewModel.state.library.identifier, fieldValues: values, dateParser: dateParser)
        perform(request: request) { [weak self, weak viewModel] error in
            guard let error, let self, let viewModel else { return }

            DDLogError("HtmlEpubReaderActionHandler: can't update annotation \(key) - \(error)")

            update(viewModel: viewModel) { state in
                state.error = .cantUpdateAnnotation
            }
        }
    }

    private func set(color: String, key: String, viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        let values = [KeyBaseKeyPair(key: FieldKeys.Item.Annotation.color, baseKey: nil): color]
        let request = EditItemFieldsDbRequest(key: key, libraryId: viewModel.state.library.identifier, fieldValues: values, dateParser: dateParser)
        self.perform(request: request) { [weak self, weak viewModel] error in
            guard let error, let self, let viewModel else { return }

            DDLogError("HtmlEpubReaderActionHandler: can't set color \(key) - \(error)")

            update(viewModel: viewModel) { state in
                state.error = .cantUpdateAnnotation
            }
        }
    }

    private func set(comment: NSAttributedString, key: String, viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        let htmlComment = htmlAttributedStringConverter.convert(attributedString: comment)

        update(viewModel: viewModel) { state in
            state.comments[key] = comment
        }

        let values = [KeyBaseKeyPair(key: FieldKeys.Item.Annotation.comment, baseKey: nil): htmlComment]
        let request = EditItemFieldsDbRequest(key: key, libraryId: viewModel.state.library.identifier, fieldValues: values, dateParser: dateParser)
        perform(request: request) { [weak self] error in
            guard let self, let error else { return }

            DDLogError("HtmlEpubReaderActionHandler: can't set comment \(key) - \(error)")

            update(viewModel: viewModel) { state in
                state.error = .cantUpdateAnnotation
            }
        }
    }

    private func toggle(tool: AnnotationTool, in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        update(viewModel: viewModel) { state in
            if state.activeTool == tool {
                state.activeTool = nil
            } else {
                state.activeTool = tool
            }
            state.changes = .activeTool
        }
    }

    private func set(tags: [Tag], to key: String, in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        let request = EditTagsForItemDbRequest(key: key, libraryId: viewModel.state.library.identifier, tags: tags)
        perform(request: request) { [weak self, weak viewModel] error in
            guard let error, let self, let viewModel else { return }

            DDLogError("HtmlEpubReaderActionHandler: can't set tags \(key) - \(error)")

            update(viewModel: viewModel) { state in
                state.error = .cantUpdateAnnotation
            }
        }
    }

    private func _select(key: String?, didSelectInDocument: Bool, state: inout HtmlEpubReaderState) {
        guard key != state.selectedAnnotationKey else { return }

        if let existing = state.selectedAnnotationKey {
            add(updatedAnnotationKey: existing, state: &state)
            if state.selectedAnnotationCommentActive {
                state.selectedAnnotationCommentActive = false
                state.changes.insert(.activeComment)
            }
        }

        state.changes.insert(.selection)

        guard let key else {
            state.selectedAnnotationKey = nil
            return
        }

        state.selectedAnnotationKey = key
        if !didSelectInDocument {
            state.focusDocumentKey = key
        } else {
            state.focusSidebarKey = key
        }
        add(updatedAnnotationKey: key, state: &state)

        func add(updatedAnnotationKey key: String, state: inout HtmlEpubReaderState) {
            if state.annotations.contains(where: { $0.key == key }) {
                var updatedAnnotationKeys = state.updatedAnnotationKeys ?? []
                updatedAnnotationKeys.append(key)
                state.updatedAnnotationKeys = updatedAnnotationKeys
            }
        }
    }

    private func set(filter: AnnotationsFilter?, in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        guard filter != viewModel.state.annotationFilter else { return }
        filterAnnotations(with: viewModel.state.annotationSearchTerm, filter: filter, in: viewModel)
    }

    private func searchAnnotations(for term: String, in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTerm = trimmedTerm.isEmpty ? nil : trimmedTerm
        guard newTerm != viewModel.state.annotationSearchTerm else { return }
        filterAnnotations(with: newTerm, filter: viewModel.state.annotationFilter, in: viewModel)
    }

    /// Filters annotations based on given term and filer parameters.
    /// - parameter term: Term to filter annotations.
    /// - parameter viewModel: ViewModel.
    private func filterAnnotations(with term: String?, filter: AnnotationsFilter?, in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        if term == nil && filter == nil {
            guard let snapshot = viewModel.state.snapshotKeys else { return }

            // TODO: - Unhide document annotations

            update(viewModel: viewModel) { state in
                state.snapshotKeys = nil
                state.sortedKeys = snapshot
                state.changes = .annotations

                if state.annotationFilter != nil {
                    state.changes.insert(.filter)
                }

                state.annotationSearchTerm = nil
                state.annotationFilter = nil
            }
            return
        }

        let snapshot = viewModel.state.snapshotKeys ?? viewModel.state.sortedKeys
        let filteredKeys = filteredKeys(from: snapshot, term: term, filter: filter, state: viewModel.state)

        // TODO: - Hide document annotations

        update(viewModel: viewModel) { state in
            if state.snapshotKeys == nil {
                state.snapshotKeys = state.sortedKeys
            }
            state.sortedKeys = filteredKeys
            state.changes = .annotations

            if filter != state.annotationFilter {
                state.changes.insert(.filter)
            }

            state.annotationSearchTerm = term
            state.annotationFilter = filter
        }
    }

    private func filteredKeys(from snapshot: [String], term: String?, filter: AnnotationsFilter?, state: HtmlEpubReaderState) -> [String] {
        if term == nil && filter == nil {
            return snapshot
        }
        return snapshot.filter({ key in
            guard let annotation = state.annotations[key] else { return false }
            return self.filter(annotation: annotation, with: term) && self.filter(annotation: annotation, with: filter)
        })
    }

    private func filter(annotation: HtmlEpubAnnotation, with term: String?) -> Bool {
        guard let term = term else { return true }
        return annotation.key.lowercased() == term.lowercased() ||
               annotation.author.localizedCaseInsensitiveContains(term) ||
               annotation.comment.localizedCaseInsensitiveContains(term) ||
               (annotation.text ?? "").localizedCaseInsensitiveContains(term) ||
               annotation.tags.contains(where: { $0.name.localizedCaseInsensitiveContains(term) })
    }

    private func filter(annotation: HtmlEpubAnnotation, with filter: AnnotationsFilter?) -> Bool {
        guard let filter = filter else { return true }
        let hasTag = filter.tags.isEmpty ? true : annotation.tags.contains(where: { filter.tags.contains($0.name) })
        let hasColor = filter.colors.isEmpty ? true : filter.colors.contains(annotation.color)
        return hasTag && hasColor
    }

    private func saveAnnotations(params: [String: Any], in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        guard let rawAnnotations = params["annotations"] as? [[String: Any]], !rawAnnotations.isEmpty else {
            DDLogError("HtmlEpubReaderActionHandler: annotations missing or empty - \(params["annotations"] ?? [])")
            return
        }

        let annotations = parse(annotations: rawAnnotations, author: viewModel.state.username, isAuthor: true)

        guard !annotations.isEmpty else {
            DDLogError("HtmlEpubReaderActionHandler: could not parse annotations")
            return
        }

        // Disable annotation tool
        if annotations.contains(where: { $0.type == .note }) {
            update(viewModel: viewModel) { state in
                state.activeTool = nil
                state.changes = .activeTool
            }
        }

        let request = CreateHtmlEpubAnnotationsDbRequest(
            attachmentKey: viewModel.state.key,
            libraryId: viewModel.state.library.identifier,
            annotations: annotations,
            userId: viewModel.state.userId,
            schemaController: schemaController
        )
        perform(request: request) { [weak self, weak viewModel] error in
            guard let self, let error, let viewModel else { return }

            DDLogError("HtmlEpubReaderActionHandler: could not store annotations - \(error)")

            update(viewModel: viewModel) { state in
                state.error = .cantAddAnnotations
            }
        }

        func parse(annotations: [[String: Any]], author: String, isAuthor: Bool) -> [HtmlEpubAnnotation] {
            return annotations.compactMap { data -> HtmlEpubAnnotation? in
                guard let id = data["id"] as? String,
                      let dateCreated = (data["dateCreated"] as? String).flatMap({ DateFormatter.iso8601WithFractionalSeconds.date(from: $0) }),
                      let dateModified = (data["dateModified"] as? String).flatMap({ DateFormatter.iso8601WithFractionalSeconds.date(from: $0) }),
                      let color = data["color"] as? String,
                      let comment = data["comment"] as? String,
                      let pageLabel = data["pageLabel"] as? String,
                      let position = data["position"] as? [String: Any],
                      let sortIndex = data["sortIndex"] as? String,
                      let text = data["text"] as? String,
                      let type = (data["type"] as? String).flatMap(AnnotationType.init),
                      let rawTags = data["tags"] as? [[String: Any]]
                else { return nil }
                let tags = rawTags.compactMap({ data -> Tag? in
                    guard let name = data["name"] as? String,
                          let color = data["color"] as? String
                    else { return nil }
                    return Tag(name: name, color: color)
                })
                return HtmlEpubAnnotation(
                    key: id,
                    type: type,
                    pageLabel: pageLabel,
                    position: position,
                    author: author,
                    isAuthor: isAuthor,
                    color: color,
                    comment: comment,
                    text: text,
                    sortIndex: sortIndex,
                    dateModified: dateModified,
                    dateCreated: dateCreated,
                    tags: tags
                )
            }
        }
    }

    private func initialise(in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        guard let readerUrl = Bundle.main.url(forResource: "view", withExtension: "html", subdirectory: "Bundled/reader") else {
            DDLogError("HtmlEpubReaderActionHandler: can't find reader view.html")
            return
        }

        // Create temporary directory where both reader files and document file live so that the reader can access everything.

        do {
            // Copy reader files to temporary directory
            let readerFiles: [File] = try fileStorage.contentsOfDirectory(at: Files.file(from: readerUrl).directory)
            for file in readerFiles {
                try fileStorage.copy(from: file, to: viewModel.state.readerFile.copy(withName: file.name, ext: file.ext))
            }
            // Copy document files (in case of snapshot there can be multiple files) to temporary sub-directory
            let documentFiles: [File] = try fileStorage.contentsOfDirectory(at: viewModel.state.originalFile.directory)
            for file in documentFiles {
                try fileStorage.copy(from: file, to: viewModel.state.documentFile.copy(withName: file.name, ext: file.ext))
            }

            update(viewModel: viewModel) { state in
                state.changes.insert(.readerInitialised)
            }
        } catch let error {
            DDLogError("HtmlEpubReaderActionHandler: can't initialise reader - \(error)")
        }
    }

    private func deinitialise(in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        try? fileStorage.remove(viewModel.state.readerFile.directory)
    }

    private func load(in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        do {
            let (sortedKeys, annotations, json, token, rawPage) = loadAnnotationsAndJson(in: viewModel)
            let type: String
            let page: HtmlEpubReaderState.DocumentData.Page?

            switch viewModel.state.documentFile.ext.lowercased() {
            case "epub":
                type = "epub"
                page = .epub(cfi: rawPage)

            case "html", "htm":
                type = "snapshot"
                if let scrollYPercent = Double(rawPage) {
                    page = .html(scrollYPercent: scrollYPercent)
                } else {
                    DDLogError("HtmlEPubReaderActionHandler: incompatible lastIndexPage stored for \(viewModel.state.key) - \(rawPage)")
                    page = nil
                }

            default:
                throw HtmlEpubReaderState.Error.incompatibleDocument
            }

            let documentData = HtmlEpubReaderState.DocumentData(type: type, url: viewModel.state.documentFile.createUrl(), annotationsJson: json, page: page)
            update(viewModel: viewModel) { state in
                state.sortedKeys = sortedKeys
                state.annotations = annotations
                state.documentData = documentData
                state.notificationToken = token
                state.changes = .annotations
            }
        } catch let error {
            DDLogError("HtmlEpubReaderActionHandler: could not load document - \(error)")
        }
    }

    private func loadAnnotationsAndJson(in viewModel: ViewModel<HtmlEpubReaderActionHandler>) -> ([String], [String: HtmlEpubAnnotation], String, NotificationToken?, String) {
        do {
            let pageIndexRequest = ReadDocumentDataDbRequest(attachmentKey: viewModel.state.key, libraryId: viewModel.state.library.identifier)
            let pageIndex = try dbStorage.perform(request: pageIndexRequest, on: .main)
            let annotationsRequest = ReadAnnotationsDbRequest(attachmentKey: viewModel.state.key, libraryId: viewModel.state.library.identifier)
            let items = try dbStorage.perform(request: annotationsRequest, on: .main)
            var sortedKeys: [String] = []
            var annotations: [String: HtmlEpubAnnotation] = [:]
            var jsons: [[String: Any]] = []

            for item in items {
                guard let (annotation, json) = item.htmlEpubAnnotation else { continue }
                jsons.append(json)
                sortedKeys.append(annotation.key)
                annotations[item.key] = annotation
            }

            let jsonString = WebViewEncoder.encodeAsJSONForJavascript(jsons)

            let token = items.observe { [weak self, weak viewModel] change in
                guard let self, let viewModel else { return }
                switch change {
                case .update(let objects, let deletions, let insertions, let modifications):
                    update(objects: objects, deletions: deletions, insertions: insertions, modifications: modifications, viewModel: viewModel)

                case .error, .initial: break
                }
            }

            return (sortedKeys, annotations, jsonString, token, pageIndex)
        } catch let error {
            DDLogError("HtmlEpubReaderActionHandler: can't load annotations - \(error)")
            return ([], [:], "[]", nil, "")
        }
    }

    private func update(objects: Results<RItem>, deletions: [Int], insertions: [Int], modifications: [Int], viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        DDLogInfo("HtmlEpubReaderActionHandler: annotations changed in database")

        // Get sorted database keys
        var keys = viewModel.state.snapshotKeys ?? viewModel.state.sortedKeys
        var annotations: [String: HtmlEpubAnnotation] = viewModel.state.annotations
        var texts = viewModel.state.texts
        var comments = viewModel.state.comments
        var selectionDeleted = false
        var popoverWasInserted = false
        // Update database keys based on realm notification
        var updatedKeys: [String] = []
        // Collect modified, deleted and inserted annotations to update the `Document`
        var updatedPdfAnnotations: [[String: Any]] = []
        var deletedPdfAnnotations: [String] = []
        var insertedPdfAnnotations: [[String: Any]] = []

        // Check which annotations changed and update Html/Epub
        for index in modifications {
            if index >= keys.count {
                DDLogWarn(
                    "HtmlEpubReaderActionHandler: tried modifying index out of bounds! keys.count=\(keys.count); index=\(index); deletions=\(deletions); insertions=\(insertions); modifications=\(modifications)"
                )
                continue
            }

            let key = keys[index]
            guard let item = objects.filter(.key(key)).first, let (annotation, json) = item.htmlEpubAnnotation else { continue }

            DDLogInfo("HtmlEpubReaderActionHandler: update Html/Epub annotation \(key)")
            annotations[key] = annotation
            updatedPdfAnnotations.append(json)

            if canUpdate(key: key, item: item, viewModel: viewModel) {
                DDLogInfo("HtmlEpubReaderActionHandler: update sidebar key \(key)")
                updatedKeys.append(key)

                if item.changeType == .sync {
                    // Update comment if it's remote sync change
                    DDLogInfo("HtmlEpubReaderActionHandler: update comment")
                    let textCacheTuple: (String, [UIFont: NSAttributedString])?
                    let comment: NSAttributedString?
                    // Annotation text
                    switch annotation.type {
                    case .highlight, .underline:
                        textCacheTuple = annotation.text.flatMap({
                            ($0, [viewModel.state.textFont: htmlAttributedStringConverter.convert(text: $0, baseAttributes: [.font: viewModel.state.textFont])])
                        })

                    case .note, .image, .ink, .freeText:
                        textCacheTuple = nil
                    }
                    texts[key] = textCacheTuple
                    // Annotation comment
                    switch annotation.type {
                    case .note, .highlight, .image, .underline:
                        comment = htmlAttributedStringConverter.convert(text: annotation.comment, baseAttributes: [.font: viewModel.state.commentFont])

                    case .ink, .freeText:
                        comment = nil
                    }
                    comments[key] = comment
                }
            }
        }

        var shouldCancelUpdate = false

        // Find Html/Epub annotations to be removed from document
        for index in deletions.reversed() {
            if index >= keys.count {
                DDLogWarn(
                    "HtmlEpubReaderActionHandler: tried removing index out of bounds! keys.count=\(keys.count); index=\(index); deletions=\(deletions); insertions=\(insertions); modifications=\(modifications)"
                )
                shouldCancelUpdate = true
                break
            }

            let key = keys.remove(at: index)
            annotations[key] = nil
            deletedPdfAnnotations.append(key)
            DDLogInfo("HtmlEpubReaderActionHandler: delete key \(key)")

            if viewModel.state.selectedAnnotationKey == key {
                DDLogInfo("HtmlEpubReaderActionHandler: deleted selected annotation")
                selectionDeleted = true
            }
        }

        if shouldCancelUpdate {
            return
        }

        // Create annotations which need to be added to Html/Epub
        for index in insertions {
            if index > keys.count {
                DDLogWarn("HtmlEpubReaderActionHandler: tried inserting index out of bounds! keys.count=\(keys.count); index=\(index); deletions=\(deletions); insertions=\(insertions); modifications=\(modifications)")
                shouldCancelUpdate = true
                break
            }

            let item = objects[index]

            guard let (annotation, json) = item.htmlEpubAnnotation else {
                DDLogWarn("HtmlEpubReaderActionHandler: tried adding invalid annotation")
                shouldCancelUpdate = true
                break
            }

            keys.insert(item.key, at: index)
            annotations[item.key] = annotation
            if viewModel.state.annotationPopoverKey == item.key {
                popoverWasInserted = true
            }
            DDLogInfo("HtmlEpubReaderActionHandler: insert key \(item.key)")

            switch item.changeType {
            case .user:
                break

            case .sync, .syncResponse:
                insertedPdfAnnotations.append(json)
                DDLogInfo("HtmlEpubReaderActionHandler: insert Html/Epub annotation")
            }
        }

        if shouldCancelUpdate {
            return
        }

        // Update state
        update(viewModel: viewModel) { state in
            if state.snapshotKeys == nil {
                state.sortedKeys = keys
            } else {
                state.snapshotKeys = keys
                state.sortedKeys = filteredKeys(from: keys, term: state.annotationSearchTerm, filter: state.annotationFilter, state: state)
            }
            state.annotations = annotations
            state.documentUpdate = HtmlEpubReaderState.DocumentUpdate(deletions: deletedPdfAnnotations, insertions: insertedPdfAnnotations, modifications: updatedPdfAnnotations)
            state.comments = comments
            state.texts = texts
            // Filter updated keys to include only keys that are actually available in `sortedKeys`. If filter/search is turned on and an item is edited so that it disappears from the filter/search,
            // `updatedKeys` will try to update it while the key will be deleted from data source at the same time.
            state.updatedAnnotationKeys = updatedKeys.filter({ state.sortedKeys.contains($0) })
            state.changes = .annotations
            if popoverWasInserted {
                // When note annotation is inserted it also wants to show a popover, but the annotation was not stored in local state yet. So we add a `popover` change here so that the popover is shown.
                state.changes.insert(.popover)
            }

            // Update selection
            if selectionDeleted {
                _select(key: nil, didSelectInDocument: true, state: &state)
            }

            // Disable sidebar editing if there are no results
            if (state.snapshotKeys ?? state.sortedKeys).isEmpty {
                state.sidebarEditingEnabled = false
                state.changes.insert(.sidebarEditing)
            }
        }

        func canUpdate(key: String, item: RItem, viewModel: ViewModel<HtmlEpubReaderActionHandler>) -> Bool {
            // If there was a sync type change, always update item
            switch item.changeType {
            case .sync:
                // If sync happened and this item changed, always update item
                return true

            case .syncResponse:
                // This is a response to local changes being synced to backend, can be ignored
                return false

            case .user: break
            }

            // Check whether selected annotation's comment is being edited.
            guard viewModel.state.selectedAnnotationCommentActive && viewModel.state.selectedAnnotationKey == key else { return true }

            // Check whether the comment actually changed.
            let newComment = item.fields.filter(.key(FieldKeys.Item.Annotation.comment)).first?.value
            let oldComment = viewModel.state.annotations[key]?.comment
            return oldComment == newComment
        }
    }
}

extension RItem {
    fileprivate var htmlEpubAnnotation: (HtmlEpubAnnotation, [String: Any])? {
        var type: AnnotationType?
        var position: [String: Any] = [:]
        var text: String?
        var sortIndex: String?
        var pageLabel: String?
        var comment: String?
        var color: String?
        var unknown: [String: String] = [:]

        for field in fields {
            switch (field.key, field.baseKey) {
            case (_, FieldKeys.Item.Annotation.position):
                position[field.key] = field.value

            case (FieldKeys.Item.Annotation.type, nil):
                type = AnnotationType(rawValue: field.value)
                if type == nil {
                    DDLogError("HtmlEpubReaderActionHandler: invalid annotation type when creating annotation, type=\(field.value)")
                }

            case (FieldKeys.Item.Annotation.text, nil):
                text = field.value

            case (FieldKeys.Item.Annotation.sortIndex, nil):
                sortIndex = field.value

            case (FieldKeys.Item.Annotation.pageLabel, nil):
                pageLabel = field.value

            case (FieldKeys.Item.Annotation.comment, nil):
                comment = field.value

            case (FieldKeys.Item.Annotation.color, nil):
                color = field.value

            default:
                unknown[field.key] = field.value
            }
        }

        guard let type, let sortIndex, !position.isEmpty else {
            DDLogError("HtmlEpubReaderActionHandler: can't create html/epub annotation, type=\(String(describing: type));sortIndex=\(String(describing: sortIndex));position=\(position)")
            return nil
        }

        let tags = Array(tags.map({ typedTag in
            let color: String? = (typedTag.tag?.color ?? "").isEmpty ? nil : typedTag.tag?.color
            return Tag(name: typedTag.tag?.name ?? "", color: color ?? "")
        }))

        var json: [String: Any] = [
            "id": key,
            "dateCreated": DateFormatter.iso8601WithFractionalSeconds.string(from: dateAdded),
            "dateModified": DateFormatter.iso8601WithFractionalSeconds.string(from: dateModified),
            "authorName": createdBy?.username ?? "",
            "type": type.rawValue,
            "text": text ?? "",
            "sortIndex": sortIndex,
            "pageLabel": pageLabel ?? "",
            "comment": comment ?? "",
            "color": color ?? "",
            "position": position,
            "tags": tags.map({ ["name": $0.name, "color": $0.color] })
        ]
        for (key, value) in unknown {
            json[key] = value
        }

        let annotation = HtmlEpubAnnotation(
            key: key,
            type: type,
            pageLabel: pageLabel ?? "",
            position: position,
            author: createdBy?.username ?? "",
            isAuthor: true,
            color: color ?? "",
            comment: comment ?? "",
            text: text,
            sortIndex: sortIndex,
            dateModified: dateModified,
            dateCreated: dateAdded,
            tags: tags
        )

        return (annotation, json)
    }
}
