//
//  PDFAnnotationsActionHandler.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 10/03/2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RealmSwift

final class PDFAnnotationsActionHandler: ViewModelActionHandler {
    typealias State = PDFAnnotationsState
    typealias Action = PDFAnnotationsAction

    func process(action: PDFAnnotationsAction, in viewModel: ViewModel<PDFAnnotationsActionHandler>) {
        switch action {
        case .initializeSortedKeys:
            update(viewModel: viewModel) { state in
                updateSortedKeys(in: &state)
                applyFilter(to: &state)
                state.changes = .annotations
            }

        case .setAnnotations(let annotationPages, let changedAnnotationKeys, let selectedAnnotationKey, let selectionFromDocument, let databaseAnnotations):
            update(viewModel: viewModel) { state in
                state.annotationPages = annotationPages
                state.databaseAnnotations = databaseAnnotations
                updateSortedKeys(in: &state)
                applyFilter(to: &state)
                state.updatedAnnotationKeys = changedAnnotationKeys?.filter({ state.sortedKeys.contains($0) })
                state.changes = .annotations
                let selectionChanged: Bool
                let newSelectedAnnotationKey: PDFReaderAnnotationKey?
                if selectionFromDocument, state.selectedAnnotationKey != selectedAnnotationKey {
                    selectionChanged = true
                    newSelectedAnnotationKey = selectedAnnotationKey
                } else if let selectedAnnotationKey = state.selectedAnnotationKey, !state.sortedKeys.contains(selectedAnnotationKey) {
                    selectionChanged = true
                    newSelectedAnnotationKey = nil
                } else {
                    selectionChanged = false
                    newSelectedAnnotationKey = nil
                }
                if selectionChanged {
                    updateSelection(
                        to: newSelectedAnnotationKey,
                        selectionFromDocument: selectionFromDocument,
                        selectionFromSidebar: false,
                        state: &state
                    )
                }

                // If sidebar editing is enabled and there are no results, disable it.
                if state.sidebarEditingEnabled, (state.snapshotKeys ?? state.sortedKeys).isEmpty {
                    state.sidebarEditingEnabled = false
                    state.selectedAnnotationsDuringEditing = []
                    state.deletionEnabled = false
                    state.mergingEnabled = false
                    state.changes.insert(.sidebarEditing)
                }
            }

        case .setSelection(let selectedAnnotationKey, let selectionFromDocument):
            update(viewModel: viewModel) { state in
                updateSelection(
                    to: selectedAnnotationKey,
                    selectionFromDocument: selectionFromDocument,
                    selectionFromSidebar: !selectionFromDocument,
                    state: &state
                )
            }

        case .setCommentActive(let isActive):
            update(viewModel: viewModel) { state in
                state.selectedAnnotationCommentActive = isActive
                state.changes = .activeComment
            }

        case .setSidebarEditingEnabled(let enabled):
            update(viewModel: viewModel) { state in
                state.sidebarEditingEnabled = enabled
                if !enabled {
                    state.selectedAnnotationsDuringEditing = []
                    state.deletionEnabled = false
                    state.mergingEnabled = false
                } else if let selectedAnnotationKey = state.selectedAnnotationKey {
                    state.selectedAnnotationKey = nil
                    state.updatedAnnotationKeys = [selectedAnnotationKey]
                    state.changes.insert(.selection)
                    if state.selectedAnnotationCommentActive {
                        state.selectedAnnotationCommentActive = false
                        state.changes.insert(.activeComment)
                    }
                }
                state.changes.insert(.sidebarEditing)
            }

        case .setSidebarEditingSelection(let deletionEnabled, let mergingEnabled):
            update(viewModel: viewModel) { state in
                state.deletionEnabled = deletionEnabled
                state.mergingEnabled = mergingEnabled
                state.changes = .sidebarEditingSelection
            }

        case .selectAnnotationDuringEditing(let key):
            selectDuringEditing(key: key, in: viewModel)

        case .deselectAnnotationDuringEditing(let key):
            deselectDuringEditing(key: key, in: viewModel)

        case .mergeSelectedAnnotations:
            guard viewModel.state.mergingEnabled else { return }
            update(viewModel: viewModel) { state in
                state.outgoingAction = .mergeAnnotations(state.selectedAnnotationsDuringEditing)
                state.mergingEnabled = false
                state.deletionEnabled = false
                state.selectedAnnotationsDuringEditing = []
                state.changes = .sidebarEditingSelection
            }

        case .removeSelectedAnnotations:
            guard viewModel.state.deletionEnabled else { return }
            update(viewModel: viewModel) { state in
                state.outgoingAction = .removeAnnotations(state.selectedAnnotationsDuringEditing)
                state.mergingEnabled = false
                state.deletionEnabled = false
                state.selectedAnnotationsDuringEditing = []
                state.changes = .sidebarEditingSelection
            }

        case .setSearchTerm(let term):
            let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedTerm = trimmedTerm.isEmpty ? nil : trimmedTerm
            guard normalizedTerm != viewModel.state.searchTerm else { return }
            update(viewModel: viewModel) { state in
                state.searchTerm = normalizedTerm
                applyFilter(to: &state)
                state.changes = [.annotations, .filter]
            }

        case .setFilter(let filter):
            guard filter != viewModel.state.filter else { return }
            update(viewModel: viewModel) { state in
                state.filter = filter
                applyFilter(to: &state)
                state.changes = [.annotations, .filter]
            }

        case .setLibrary(let library):
            update(viewModel: viewModel) { state in
                state.library = library
                state.changes = .library
            }

        case .setAppearance(let settings, let interfaceStyle):
            update(viewModel: viewModel) { state in
                state.settings = settings
                state.interfaceStyle = interfaceStyle
                state.changes = .appearance
            }

        case .setSettings(let settings):
            update(viewModel: viewModel) { state in
                state.settings = settings
            }

        case .send(let outgoingAction):
            update(viewModel: viewModel) { state in
                state.outgoingAction = outgoingAction
            }
        }
    }

    private func updateSortedKeys(in state: inout PDFAnnotationsState) {
        let sortedKeys = createSortedKeys(fromDatabaseAnnotations: state.databaseAnnotations, documentAnnotationKeys: state.documentAnnotationKeys)
        if sortedKeys != state.sortedKeys {
            state.sortedKeys = sortedKeys
            state.snapshotKeys = nil
        }

        func createSortedKeys(fromDatabaseAnnotations databaseAnnotations: Results<RItem>?, documentAnnotationKeys: [PDFReaderAnnotationKey]) -> [PDFReaderAnnotationKey] {
            var keys: [PDFReaderAnnotationKey] = []
            if let databaseAnnotations {
                for item in databaseAnnotations {
                    guard let annotation = PDFDatabaseAnnotation(item: item), isValid(databaseAnnotation: annotation) else { continue }
                    keys.append(PDFReaderAnnotationKey(key: item.key, sortIndex: item.annotationSortIndex, type: .database))
                }
            }
            keys.append(contentsOf: documentAnnotationKeys)
            keys.sort(by: { lhs, rhs in
                if lhs.sortIndex != rhs.sortIndex {
                    return lhs.sortIndex < rhs.sortIndex
                }
                if lhs.key != rhs.key {
                    return lhs.key < rhs.key
                }
                return lhs.type == .database && rhs.type == .document
            })
            return keys

            func isValid(databaseAnnotation: PDFDatabaseAnnotation) -> Bool {
                guard databaseAnnotation._page != nil else { return false }

                switch databaseAnnotation.type {
                case .ink:
                    if databaseAnnotation.item.paths.isEmpty {
                        DDLogInfo("PDFAnnotationsActionHandler: \(databaseAnnotation.type) annotation \(databaseAnnotation.key) missing paths")
                        return false
                    }

                case .highlight, .image, .note, .underline:
                    if databaseAnnotation.item.rects.isEmpty {
                        DDLogInfo("PDFAnnotationsActionHandler: \(databaseAnnotation.type) annotation \(databaseAnnotation.key) missing rects")
                        return false
                    }

                case .freeText:
                    if databaseAnnotation.item.rects.isEmpty {
                        DDLogInfo("PDFAnnotationsActionHandler: \(databaseAnnotation.type) annotation \(databaseAnnotation.key) missing rects")
                        return false
                    }
                    if databaseAnnotation.fontSize == nil {
                        // Since free text annotations are created in AnnotationConverter using `setBoundingBox(annotation.boundingBox(boundingBoxConverter: boundingBoxConverter), transformSize: true)`
                        // it's ok even if they are missing `fontSize`, so we just log it and continue validation.
                        DDLogInfo("PDFAnnotationsActionHandler: \(databaseAnnotation.type) annotation \(databaseAnnotation.key) missing fontSize")
                    }
                    if databaseAnnotation.rotation == nil {
                        DDLogInfo("PDFAnnotationsActionHandler: \(databaseAnnotation.type) annotation \(databaseAnnotation.key) missing rotation")
                        return false
                    }
                }

                // Sort index consists of 3 parts separated by "|":
                // - 1. page index (5 characters)
                // - 2. character offset (6 characters)
                // - 3. y position from top (5 characters)
                let sortIndex = databaseAnnotation.sortIndex
                let parts = sortIndex.split(separator: "|")
                if parts.count != 3 || parts[0].count != 5 || parts[1].count != 6 || parts[2].count != 5 {
                    DDLogInfo("PDFAnnotationsActionHandler: invalid sort index (\(sortIndex)) for \(databaseAnnotation.key)")
                    return false
                }

                return true
            }
        }
    }

    private func applyFilter(to state: inout PDFAnnotationsState) {
        guard state.searchTerm != nil || state.filter != nil else {
            if let snapshotKeys = state.snapshotKeys {
                state.sortedKeys = snapshotKeys
                state.snapshotKeys = nil
            }
            return
        }

        let snapshotKeys = state.snapshotKeys ?? state.sortedKeys
        if state.snapshotKeys == nil {
            state.snapshotKeys = snapshotKeys
        }
        state.sortedKeys = filteredKeys(from: snapshotKeys, state: state)

        func filteredKeys(from snapshotKeys: [PDFReaderAnnotationKey], state: PDFAnnotationsState) -> [PDFReaderAnnotationKey] {
            return snapshotKeys.filter({ key in
                guard let annotation = state.annotation(for: key) else { return false }
                return annotation.matches(term: state.searchTerm, filter: state.filter, displayName: state.displayName, username: state.username)
            })
        }
    }

    private func updateSelection(to selectedAnnotationKey: PDFReaderAnnotationKey?, selectionFromDocument: Bool, selectionFromSidebar: Bool, state: inout PDFAnnotationsState) {
        let selectionChanged = state.selectedAnnotationKey != selectedAnnotationKey
        if selectionChanged {
            state.updatedAnnotationKeys = state.updatedAnnotationKeys ?? []
            state.updatedAnnotationKeys?.append(contentsOf: [state.selectedAnnotationKey, selectedAnnotationKey].compactMap({ $0 }))
        }
        state.selectedAnnotationKey = selectedAnnotationKey
        state.focusOnSelectionIfNeeded = selectionFromDocument && (selectedAnnotationKey != nil)
        state.selectionFromSidebar = selectionFromSidebar
        state.changes.insert(.selection)
        if selectionChanged && state.selectedAnnotationCommentActive {
            state.selectedAnnotationCommentActive = false
            state.changes.insert(.activeComment)
        }
    }

    private func selectDuringEditing(key: PDFReaderAnnotationKey, in viewModel: ViewModel<PDFAnnotationsActionHandler>) {
        guard let annotation = viewModel.state.annotation(for: key) else { return }
        let annotationDeletable = annotation.isSyncable && annotation.editability(currentUserId: viewModel.state.userId, library: viewModel.state.library) != .notEditable
        update(viewModel: viewModel) { state in
            if state.selectedAnnotationsDuringEditing.isEmpty {
                state.deletionEnabled = annotationDeletable
            } else {
                state.deletionEnabled = state.deletionEnabled && annotationDeletable
            }

            state.selectedAnnotationsDuringEditing.insert(key)

            if state.selectedAnnotationsDuringEditing.count == 1 {
                state.mergingEnabled = false
            } else {
                state.mergingEnabled = selectedAnnotationsMergeable(selected: state.selectedAnnotationsDuringEditing, in: viewModel)
            }

            state.changes = .sidebarEditingSelection
        }
    }

    private func deselectDuringEditing(key: PDFReaderAnnotationKey, in viewModel: ViewModel<PDFAnnotationsActionHandler>) {
        update(viewModel: viewModel) { state in
            state.selectedAnnotationsDuringEditing.remove(key)
            if state.selectedAnnotationsDuringEditing.isEmpty {
                if state.deletionEnabled {
                    state.deletionEnabled = false
                    state.changes = .sidebarEditingSelection
                }
                if state.mergingEnabled {
                    state.mergingEnabled = false
                    state.changes = .sidebarEditingSelection
                }
            } else {
                // Check whether deletion state changed after removing this annotation.
                let deletionEnabled = selectedAnnotationsDeletable(selected: state.selectedAnnotationsDuringEditing, in: viewModel)
                if state.deletionEnabled != deletionEnabled {
                    state.deletionEnabled = deletionEnabled
                    state.changes = .sidebarEditingSelection
                }
                if state.selectedAnnotationsDuringEditing.count == 1 {
                    if state.mergingEnabled {
                        state.mergingEnabled = false
                        state.changes = .sidebarEditingSelection
                    }
                } else {
                    state.mergingEnabled = selectedAnnotationsMergeable(selected: state.selectedAnnotationsDuringEditing, in: viewModel)
                    state.changes = .sidebarEditingSelection
                }
            }
        }

        func selectedAnnotationsDeletable(selected: Set<PDFReaderAnnotationKey>, in viewModel: ViewModel<PDFAnnotationsActionHandler>) -> Bool {
            return !selected.contains(where: { key in
                guard let annotation = viewModel.state.annotation(for: key) else { return false }
                return !annotation.isSyncable || annotation.editability(currentUserId: viewModel.state.userId, library: viewModel.state.library) == .notEditable
            })
        }
    }

    private func selectedAnnotationsMergeable(selected: Set<PDFReaderAnnotationKey>, in viewModel: ViewModel<PDFAnnotationsActionHandler>) -> Bool {
        var page: Int?
        var type: AnnotationType?
        var color: String?
//        var rects: [CGRect]?

        let hasSameProperties: (PDFAnnotation) -> Bool = { annotation in
            // Check whether annotations of one type are selected
            if let type = type {
                if type != annotation.type {
                    return false
                }
            } else {
                type = annotation.type
            }
            // Check whether annotations of one color are selected
            if let color = color {
                if color != annotation.color {
                    return false
                }
            } else {
                color = annotation.color
            }
            return true
        }

        for key in selected {
            guard let annotation = viewModel.state.annotation(for: key) else { continue }
            guard annotation.isSyncable else { return false }

            if let page = page {
                // Only 1 page can be selected
                if page != annotation.page {
                    return false
                }
            } else {
                page = annotation.page
            }

            switch annotation.type {
            case .ink:
                if !hasSameProperties(annotation) {
                    return false
                }

            case .highlight:
                return false
//                if !hasSameProperties(annotation) {
//                    return false
//                }
//                // Check whether rects are overlapping
//                if let rects = rects {
//                    if !rects(rects: rects, hasIntersectionWith: annotation.rects) {
//                        return false
//                    }
//                } else {
//                    rects = annotation.rects
//                }

            case .note, .image, .underline, .freeText:
                return false
            }
        }

        return true
    }

//    private func rects(rects lRects: [CGRect], hasIntersectionWith rRects: [CGRect]) -> Bool {
//        for rect in lRects {
//            if rRects.contains(where: { $0.intersects(rect) }) {
//                return true
//            }
//        }
//        return false
//    }
}
