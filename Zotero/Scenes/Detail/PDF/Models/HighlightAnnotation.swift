//
//  HighlightAnnotation.swift
//  Zotero
//
//  Created by Michal Rentka on 10.12.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import PSPDFKit

final class HighlightAnnotation: PSPDFKit.HighlightAnnotation {

    override init() {
        super.init()
        self.blendMode = .normal
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.blendMode = .normal
    }

    override init(dictionary dictionaryValue: [String : Any]?) throws {
        try super.init(dictionary: dictionaryValue)
        self.blendMode = .normal
    }

    override var shouldDrawNoteIconIfNeeded: Bool {
        return false
    }

    override func draw(context: CGContext, options: RenderOptions?) {
        super.draw(context: context, options: options)

        guard let comment = self.contents, !comment.isEmpty else { return }

        CommentIconDrawingController.draw(context: context, boundingBox: (self.rects?.first ?? self.boundingBox), color: (self.color ?? .black))
    }

    override class var supportsSecureCoding: Bool {
        true
    }
}
