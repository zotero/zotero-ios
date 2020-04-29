//
//  AnnotationCell.swift
//  Zotero
//
//  Created by Michal Rentka on 29/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class AnnotationCell: UITableViewCell {
    func setup(with annotation: Annotation) {
        self.set(view: AnnotationRow(annotation: annotation))
    }
}
