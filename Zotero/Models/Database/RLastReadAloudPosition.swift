//
//  RLastReadAloudPosition.swift
//  Zotero
//
//  Created by Michal Rentka on 24.09.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct RLastReadAloudPositionChanges: OptionSet {
    typealias RawValue = Int16

    let rawValue: Int16

    init(rawValue: Int16) {
        self.rawValue = rawValue
    }
}

extension RLastReadAloudPositionChanges {
    static let position = RLastReadAloudPositionChanges(rawValue: 1 << 0)
}

/// Sentence where read-aloud playback of an attachment left off, synced as `lastReadAloudPosition_<library>_<key>`.
/// The two document kinds store different anchors: PDF stores the sentence's page and rects, HTML/EPUB the reader's own
/// source position, which is opaque to the app and therefore kept as JSON.
final class RLastReadAloudPosition: Object {
    @Persisted(indexed: true) var key: String
    /// PDF: 0-based index of the page the sentence lies on. Nil for reader positions.
    @Persisted var pageIndex: Int?
    /// PDF: rects of the sentence, in PDF coordinate space.
    @Persisted var rects: List<RRect>
    /// HTML/EPUB: the reader's source position for the sentence (an EPUB CFI `FragmentSelector`, a snapshot
    /// `CssSelector`), as JSON. Nil for PDF positions.
    @Persisted var sourceJson: String?
    @Persisted var customLibraryKey: RCustomLibraryType?
    @Persisted var groupKey: Int?
    /// Indicates which local changes need to be synced to backend
    @Persisted var changes: List<RObjectChange>

    // MARK: - Sync data
    /// Indicates local version of object
    @Persisted(indexed: true) var version: Int
    /// State which indicates whether object is synced with backend data, see ObjectSyncState for more info
    @Persisted var syncState: ObjectSyncState
    /// Date when last sync attempt was performed on this object
    @Persisted var lastSyncDate: Date
    /// Number of retries for sync of this object
    @Persisted var syncRetries: Int
    /// Raw value for `UpdatableChangeType`, indicates whether current update of item has been made by user or sync process.
    @Persisted var changeType: UpdatableChangeType
    /// Indicates whether the object is deleted locally and needs to be synced with backend
    @Persisted var deleted: Bool

    // MARK: - Sync properties

    var changedFields: RLastReadAloudPositionChanges {
        var changes: RLastReadAloudPositionChanges = []
        for change in self.changes {
            changes.insert(RLastReadAloudPositionChanges(rawValue: change.rawChanges))
        }
        return changes
    }

    // MARK: - Position

    /// The stored anchor, or nil when neither shape is filled in (an object created by a failed parse).
    var position: ReadAloudResumePosition? {
        get {
            if let pageIndex {
                return .pdf(pageIndex: pageIndex, rects: rects.map({ CGRect(x: $0.minX, y: $0.minY, width: $0.maxX - $0.minX, height: $0.maxY - $0.minY) }))
            }
            guard let sourceJson,
                  let data = sourceJson.data(using: .utf8),
                  let source = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { return nil }
            return .reader(source: source)
        }

        set {
            switch newValue {
            case .pdf(let pageIndex, let rects):
                self.pageIndex = pageIndex
                sourceJson = nil
                self.rects.removeAll()
                for rect in rects {
                    let rRect = RRect()
                    rRect.minX = rect.minX
                    rRect.minY = rect.minY
                    rRect.maxX = rect.maxX
                    rRect.maxY = rect.maxY
                    self.rects.append(rRect)
                }

            case .reader(let source):
                pageIndex = nil
                rects.removeAll()
                sourceJson = (try? JSONSerialization.data(withJSONObject: source)).flatMap({ String(data: $0, encoding: .utf8) })

            case .none:
                pageIndex = nil
                rects.removeAll()
                sourceJson = nil
            }
        }
    }

    /// Whether the stored anchor is the same one, so that repeated reports of the same sentence don't mark the object
    /// as changed (and don't trigger a sync).
    func matches(position: ReadAloudResumePosition) -> Bool {
        switch (self.position, position) {
        case (.pdf(let storedPage, let storedRects), .pdf(let newPage, let newRects)):
            return storedPage == newPage && storedRects == newRects

        case (.reader(let storedSource), .reader(let newSource)):
            return NSDictionary(dictionary: storedSource).isEqual(to: newSource)

        default:
            return false
        }
    }
}
