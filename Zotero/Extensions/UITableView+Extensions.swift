//
//  UITableView+Extensions.swift
//  Zotero
//
//  Created by Michal Rentka on 22.09.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

extension UITableView {
    func setDefaultSizedHeader() {
        let header = UIView()
        header.frame = CGRect(origin: CGPoint(), size: CGSize(width: 36, height: 36))
        self.tableHeaderView = header
    }
}
