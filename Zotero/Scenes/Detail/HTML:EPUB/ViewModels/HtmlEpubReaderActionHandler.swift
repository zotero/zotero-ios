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
    let backgroundQueue: DispatchQueue
    weak var delegate: HtmlEpubReaderContainerDelegate?

    init(dbStorage: DbStorage, schemaController: SchemaController, htmlAttributedStringConverter: HtmlAttributedStringConverter, dateParser: DateParser) {
        self.dbStorage = dbStorage
        self.schemaController = schemaController
        self.htmlAttributedStringConverter = htmlAttributedStringConverter
        self.dateParser = dateParser
        self.backgroundQueue = DispatchQueue(label: "org.zotero.Zotero.HtmlEpubReaderActionHandler.queue", qos: .userInteractive)
    }

    func process(action: HtmlEpubReaderAction, in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        switch action {
        case .toggleTool(let tool):
            toggle(tool: tool, in: viewModel)

        case .loadDocument:
            load(in: viewModel)

        case .removeAnnotation(let key):
            remove(keys: [key], in: viewModel)

        case .saveAnnotations(let params):
            saveAnnotations(params: params, in: viewModel)

        case .searchAnnotations(let term):
            searchAnnotations(for: term, in: viewModel)

        case .searchDocument(let term):
            update(viewModel: viewModel) { state in
                state.documentSearchTerm = term
            }

        case .selectAnnotationFromSidebar(let key):
            self.update(viewModel: viewModel) { state in
                _select(data: (key, CGRect()), didSelectInDocument: false, state: &state)
            }

        case .selectAnnotationFromDocument(let key, let rect):
            update(viewModel: viewModel) { state in
                _select(data: (key, rect), didSelectInDocument: true, state: &state)
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
            self.update(viewModel: viewModel) { state in
                _select(data: nil, didSelectInDocument: false, state: &state)
            }

        case .parseAndCacheComment(key: let key, comment: let comment):
            update(viewModel: viewModel, notifyListeners: false) { state in
                state.comments[key] = self.htmlAttributedStringConverter.convert(text: comment, baseAttributes: [.font: viewModel.state.commentFont])
            }

        case .updateAnnotationProperties(let key, let color, let lineWidth, let pageLabel, let updateSubsequentLabels, let highlightText):
            set(color: color, lineWidth: lineWidth, pageLabel: pageLabel, updateSubsequentLabels: updateSubsequentLabels, highlightText: highlightText, key: key, viewModel: viewModel)

        case .setColor(key: let key, color: let color):
            set(color: color, key: key, viewModel: viewModel)

        case .setViewState(let params):
            setViewState(params: params, in: viewModel)

        case .setToolOptions(let color, let size, let tool):
            setTool(color: color, size: size, tool: tool, in: viewModel)
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
        self.perform(request: request) { error in
            guard let error = error else { return }
            // TODO: - handle error
            DDLogError("HtmlEpubReaderActionHandler: can't store page - \(error)")
        }
    }

    private func remove(keys: [String], in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        DDLogInfo("HtmlEpubReaderActionHandler: annotations deleted - keys=\(keys)")

        guard !keys.isEmpty else { return }

        let request = MarkObjectsAsDeletedDbRequest<RItem>(keys: keys, libraryId: viewModel.state.library.identifier)
        self.perform(request: request) { [weak self, weak viewModel] error in
            guard let self = self, let viewModel = viewModel else { return }

            if let error = error {
                DDLogError("HtmlEpubReaderActionHandler: can't remove annotations \(keys) - \(error)")

                self.update(viewModel: viewModel) { state in
                    state.error = .cantDeleteAnnotation
                }
            }
        }
    }

    private func set(color: String, lineWidth: CGFloat, pageLabel: String, updateSubsequentLabels: Bool, highlightText: String, key: String, viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        let values = [
            KeyBaseKeyPair(key: FieldKeys.Item.Annotation.pageLabel, baseKey: nil): pageLabel,
            KeyBaseKeyPair(key: FieldKeys.Item.Annotation.text, baseKey: nil): highlightText,
            KeyBaseKeyPair(key: FieldKeys.Item.Annotation.color, baseKey: nil): color,
            KeyBaseKeyPair(key: FieldKeys.Item.Annotation.Position.lineWidth, baseKey: FieldKeys.Item.Annotation.position): "\(Decimal(lineWidth).rounded(to: 3))"
        ]
        let request = EditItemFieldsDbRequest(key: key, libraryId: viewModel.state.library.identifier, fieldValues: values, dateParser: dateParser)
        self.perform(request: request) { [weak self, weak viewModel] error in
            guard let error = error, let self = self, let viewModel = viewModel else { return }

            DDLogError("HtmlEpubReaderActionHandler: can't update annotation \(key) - \(error)")

            self.update(viewModel: viewModel) { state in
                state.error = .cantUpdateAnnotation
            }
        }
    }

    private func set(color: String, key: String, viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        let values = [KeyBaseKeyPair(key: FieldKeys.Item.Annotation.color, baseKey: nil): color]
        let request = EditItemFieldsDbRequest(key: key, libraryId: viewModel.state.library.identifier, fieldValues: values, dateParser: dateParser)
        self.perform(request: request) { [weak self, weak viewModel] error in
            guard let error = error, let self = self, let viewModel = viewModel else { return }

            DDLogError("HtmlEpubReaderActionHandler: can't set color \(key) - \(error)")

            self.update(viewModel: viewModel) { state in
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
        perform(request: request) { error in
            guard let error else { return }

            DDLogError("HtmlEpubReaderActionHandler: can't set comment \(key) - \(error)")

            self.update(viewModel: viewModel) { state in
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

            self.update(viewModel: viewModel) { state in
                state.error = .cantUpdateAnnotation
            }
        }
    }

    private func _select(data: (String, CGRect)?, didSelectInDocument: Bool, state: inout HtmlEpubReaderState) {
        guard data?.0 != state.selectedAnnotationKey else { return }

        if let existing = state.selectedAnnotationKey {
            add(updatedAnnotationKey: existing, state: &state)

            if state.selectedAnnotationCommentActive {
                state.selectedAnnotationCommentActive = false
                state.changes.insert(.activeComment)
            }
        }

        state.changes.insert(.selection)

        guard let (key, rect) = data else {
            state.selectedAnnotationKey = nil
            state.selectedAnnotationRect = nil
            return
        }

        state.selectedAnnotationKey = key
        state.selectedAnnotationRect = rect

        if !didSelectInDocument {
            state.focusDocumentLocation = key
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
        self.filterAnnotations(with: viewModel.state.annotationSearchTerm, filter: filter, in: viewModel)
    }

    private func searchAnnotations(for term: String, in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTerm = trimmedTerm.isEmpty ? nil : trimmedTerm
        guard newTerm != viewModel.state.annotationSearchTerm else { return }
        self.filterAnnotations(with: newTerm, filter: viewModel.state.annotationFilter, in: viewModel)
    }

    /// Filters annotations based on given term and filer parameters.
    /// - parameter term: Term to filter annotations.
    /// - parameter viewModel: ViewModel.
    private func filterAnnotations(with term: String?, filter: AnnotationsFilter?, in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        if term == nil && filter == nil {
            guard let snapshot = viewModel.state.snapshotKeys else { return }

            // TODO: - Unhide document annotations

            self.update(viewModel: viewModel) { state in
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
        let filteredKeys = self.filteredKeys(from: snapshot, term: term, filter: filter, state: viewModel.state)

        // TODO: - Hide document annotations

        self.update(viewModel: viewModel) { state in
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

        let request = CreateHtmlEpubAnnotationsDbRequest(
            attachmentKey: viewModel.state.key,
            libraryId: viewModel.state.library.identifier,
            annotations: annotations,
            userId: viewModel.state.userId,
            schemaController: schemaController
        )
        self.perform(request: request) { [weak viewModel] error in
            guard let error, let viewModel else { return }

            DDLogError("HtmlEpubReaderActionHandler: could not store annotations - \(error)")

            self.update(viewModel: viewModel) { state in
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

    private func load(in viewModel: ViewModel<HtmlEpubReaderActionHandler>) {
        do {
            let data = try Data(contentsOf: viewModel.state.url)
            let jsArrayData = try JSONSerialization.data(withJSONObject: [UInt8](data))
            guard let jsArrayString = String(data: jsArrayData, encoding: .utf8) else {
                DDLogError("HtmlEpubReaderActionHandler: can't convert data to string")
                return
            }
            let (sortedKeys, annotations, json, token, rawPage) = loadAnnotationsAndJson(in: viewModel)
            let page: HtmlEpubReaderState.DocumentData.Page?

            switch viewModel.state.url.pathExtension.lowercased() {
            case "epub":
                page = .epub(cfi: rawPage)

            case "html", "htm":
                if let scrollYPercent = Double(rawPage) {
                    page = .html(scrollYPercent: scrollYPercent)
                } else {
                    DDLogError("HtmlEPubReaderActionHandler: incompatible lastIndexPage stored for \(viewModel.state.key) - \(rawPage)")
                    page = nil
                }

            default:
                page = nil
            }

            let documentData = HtmlEpubReaderState.DocumentData(buffer: jsArrayString, annotationsJson: json, page: page)
            self.update(viewModel: viewModel) { state in
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
            let pageIndex = try self.dbStorage.perform(request: pageIndexRequest, on: .main)
            let annotationsRequest = ReadAnnotationsDbRequest(attachmentKey: viewModel.state.key, libraryId: viewModel.state.library.identifier)
            let items = try self.dbStorage.perform(request: annotationsRequest, on: .main)
            var sortedKeys: [String] = []
            var annotations: [String: HtmlEpubAnnotation] = [:]
            var jsons: [[String: Any]] = []

            for item in items {
                guard let (annotation, json) = item.htmlEpubAnnotation else { continue }
                jsons.append(json)
                sortedKeys.append(annotation.key)
                annotations[item.key] = annotation
            }

            let jsonData = try JSONSerialization.data(withJSONObject: jsons)

            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                DDLogError("HtmlEpubReaderActionHandler: can't convert json data to string")
                return ([], [:], "[]", nil, "")
            }

            let token = items.observe { [weak self, weak viewModel] change in
                guard let self = self, let viewModel = viewModel else { return }
                switch change {
                case .update(let objects, let deletions, let insertions, let modifications):
                    self.update(objects: objects, deletions: deletions, insertions: insertions, modifications: modifications, viewModel: viewModel)
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
        var comments = viewModel.state.comments
        var selectKey: String?
        var selectionDeleted = false
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
                    comments[key] = htmlAttributedStringConverter.convert(text: annotation.comment, baseAttributes: [.font: viewModel.state.commentFont])
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
            DDLogInfo("HtmlEpubReaderActionHandler: insert key \(item.key)")

            switch item.changeType {
            case .user:
                // Select newly created annotation if needed
                let sidebarVisible = self.delegate?.isSidebarVisible ?? false
                let isNote = annotation.type == .note
                if !viewModel.state.sidebarEditingEnabled && (sidebarVisible || isNote) {
                    selectKey = item.key
                    DDLogInfo("HtmlEpubReaderActionHandler: select new annotation")
                }

            case .sync, .syncResponse:
                insertedPdfAnnotations.append(json)
                DDLogInfo("HtmlEpubReaderActionHandler: insert Html/Epub annotation")
            }
        }

        if shouldCancelUpdate {
            return
        }

        // Update state
        self.update(viewModel: viewModel) { state in
            if state.snapshotKeys == nil {
                state.sortedKeys = keys
            } else {
                state.snapshotKeys = keys
                state.sortedKeys = self.filteredKeys(from: keys, term: state.annotationSearchTerm, filter: state.annotationFilter, state: state)
            }
            state.annotations = annotations
            state.documentUpdate = HtmlEpubReaderState.DocumentUpdate(deletions: deletedPdfAnnotations, insertions: insertedPdfAnnotations, modifications: updatedPdfAnnotations)
            state.comments = comments
            // Filter updated keys to include only keys that are actually available in `sortedKeys`. If filter/search is turned on and an item is edited so that it disappears from the filter/search,
            // `updatedKeys` will try to update it while the key will be deleted from data source at the same time.
            state.updatedAnnotationKeys = updatedKeys.filter({ state.sortedKeys.contains($0) })
            state.changes = .annotations

            // Update selection
            if let key = selectKey {
                self._select(data: (key, CGRect()), didSelectInDocument: true, state: &state)
            } else if selectionDeleted {
                self._select(data: nil, didSelectInDocument: true, state: &state)
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
        let tags = Array(self.tags.map({ typedTag in
            let color: String? = (typedTag.tag?.color ?? "").isEmpty ? nil : typedTag.tag?.color
            return Tag(name: typedTag.tag?.name ?? "", color: color ?? "")
        }))

        var type: AnnotationType?
        var position: [String: Any] = [:]
        var text: String?
        var sortIndex: String?
        var pageLabel: String?
        var comment: String?
        var color: String?
        var unknown: [String: String] = [:]

        for field in self.fields {
            switch (field.key, field.baseKey) {
            case (FieldKeys.Item.Annotation.Position.htmlEpubType, FieldKeys.Item.Annotation.position):
                position[FieldKeys.Item.Annotation.Position.htmlEpubType] = field.value

            case (FieldKeys.Item.Annotation.Position.htmlEpubValue, FieldKeys.Item.Annotation.position):
                position[FieldKeys.Item.Annotation.Position.htmlEpubValue] = field.value

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

        let json: [String: Any] = [
            "id": self.key,
            "dateCreated": DateFormatter.iso8601WithFractionalSeconds.string(from: self.dateAdded),
            "dateModified": DateFormatter.iso8601WithFractionalSeconds.string(from: self.dateModified),
            "authorName": self.createdBy?.username ?? "",
            "type": type.rawValue,
            "text": text ?? "",
            "sortIndex": sortIndex,
            "pageLabel": pageLabel ?? "",
            "comment": comment ?? "",
            "color": color ?? "",
            "position": position,
            "tags": tags.map({ ["name": $0.name, "color": $0.color] })
        ]
        let annotation = HtmlEpubAnnotation(
            key: self.key,
            type: type,
            pageLabel: pageLabel ?? "",
            position: position,
            author: self.createdBy?.username ?? "",
            isAuthor: true,
            color: color ?? "",
            comment: comment ?? "",
            text: text,
            sortIndex: sortIndex,
            dateModified: self.dateModified,
            dateCreated: self.dateAdded,
            tags: tags
        )

        return (annotation, json)
    }
}
