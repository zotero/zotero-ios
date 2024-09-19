//
//  KeyboardData.swift
//  Zotero
//
//  Created by Michal Rentka on 05/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct KeyboardData {
    let startFrame: CGRect
    let endFrame: CGRect
    let animationDuration: Double
    let animationOptions: UIView.AnimationOptions

    var visibleHeight: CGFloat {
        // endFrame.height might be 0 for a floating keyboard that is hiding, so return 0 for this case.
        // Additionally, floating keyboard will not reach the end of the screen, therefore we can ignore it.
        guard endFrame.height > 0, endFrame.maxY >= UIScreen.main.bounds.height else { return 0 }
        return UIScreen.main.bounds.height - endFrame.minY
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let startFrame = userInfo[UIResponder.keyboardFrameBeginUserInfoKey] as? NSValue,
              let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue,
              let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber,
              let options = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber else {
            return nil
        }

        self.startFrame = startFrame.cgRectValue
        self.endFrame = endFrame.cgRectValue
        self.animationDuration = duration.doubleValue
        self.animationOptions = UIView.AnimationOptions(rawValue: options.uintValue)
    }
}
