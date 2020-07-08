//
//  UISearchBar+Extensions.swift
//  Zotero
//
//  Created by Michal Rentka on 08/07/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

extension UISearchBar {
    private var activityIndicator: UIActivityIndicatorView? {
        return self.searchTextField.leftView?.subviews.first(where: { $0 is UIActivityIndicatorView }) as? UIActivityIndicatorView
    }

    var isLoading: Bool {
        get {
            return self.activityIndicator != nil
        }

        set {
            if !newValue {
                self.activityIndicator?.removeFromSuperview()
                self.setImage(UIImage(systemName: "magnifyingglass"), for: .search, state: .normal)
                return
            }

            guard self.activityIndicator == nil else { return }

            // Even though the `leftViewMode` is set to `.always`, if the image is empty or nil, the `leftView` is hidden.
            // So we create a clear image and set it to `leftView`, so that activity indicator can be visible.
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.tintColor = .gray
            indicator.startAnimating()
            self.setImage(UIColor.clear.createImage(size: indicator.frame.size), for: .search, state: .normal)
            self.searchTextField.leftViewMode = .always
            self.searchTextField.leftView?.addSubview(indicator)
        }
    }
}
