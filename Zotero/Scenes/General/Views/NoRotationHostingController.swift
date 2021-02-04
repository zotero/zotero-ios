//
//  NoRotationHostingController.swift
//  Zotero
//
//  Created by Michal Rentka on 23/07/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import SwiftUI

final class NoRotationHostingController<Content>: UIHostingController<Content> where Content : View {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.userInterfaceIdiom == .pad ? .all : [.portrait, .portraitUpsideDown]
    }
}
