//
//  ItemAction.swift
//  Zotero
//
//  Created by Michal Rentka on 03.03.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct ItemAction {
    enum Kind {
        case addToCollection, delete, duplicate, removeFromCollection, restore, trash, sort, filter, createParent, copyCitation, copyBibliography, share, download, removeDownload
    }

    private enum Image {
        case system(String)
        case asset(String)
    }

    let type: Kind
    let title: String
    private let _image: Image
    var image: UIImage? {
        switch self._image {
        case .asset(let name):
            return UIImage(named: name)?.withRenderingMode(.alwaysTemplate)

        case .system(let name):
            return UIImage(systemName: name)?.withRenderingMode(.alwaysTemplate)
        }
    }
    var isDestructive: Bool {
        switch self.type {
        case .delete, .trash: return true
        case .addToCollection, .duplicate, .removeFromCollection, .restore, .sort, .filter, .createParent, .copyCitation, .copyBibliography, .share, .download, .removeDownload: return false
        }
    }

    init(type: Kind) {
        self.type = type

        switch type {
        case .addToCollection:
            self.title = L10n.Items.Action.addToCollection
            self._image = .system("folder.badge.plus")

        case .delete:
            self.title = L10n.delete
            self._image = .asset(Asset.Images.emptyTrash.name)

        case .duplicate:
            self.title = L10n.Items.Action.duplicate
            self._image = .system("square.on.square")

        case .removeFromCollection:
            self.title = L10n.Items.Action.removeFromCollection
            self._image = .system("folder.badge.minus")

        case .restore:
            self.title = L10n.restore
            self._image = .asset(Asset.Images.restoreTrash.name)

        case .trash:
            self.title = L10n.moveToTrash
            self._image = .system("trash")

        case .createParent:
            self.title = L10n.Items.Action.createParent
            self._image = .system("plus")

        case .sort:
            self.title = ""
            self._image = .system("arrow.up.arrow.down")

        case .filter:
            self.title = ""
            self._image = .system("")

        case .copyCitation:
            self.title = L10n.Citation.copyCitation
            self._image = .system("doc.on.doc")

        case .copyBibliography:
            self.title = L10n.Citation.copyBibliography
            self._image = .system("doc.on.doc")

        case .share:
            self.title = L10n.share
            self._image = .system("square.and.arrow.up")

        case .download:
            self.title = L10n.Items.Action.download
            self._image = .system("arrow.down.circle")

        case .removeDownload:
            self.title = L10n.Items.Action.removeDownload
            self._image = .system("arrow.down.circle.dotted")
        }
    }
}
