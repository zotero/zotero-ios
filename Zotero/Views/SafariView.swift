//
//  SafariView.swift
//  Zotero
//
//  Created by Michal Rentka on 13/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI
import SafariServices

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        return SFSafariViewController(url: self.url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {

    }
}

#if DEBUG

struct SafariView_Previews: PreviewProvider {
    static var previews: some View {
        SafariView(url: URL(string: "https://www.zotero.org/")!)
    }
}

#endif
