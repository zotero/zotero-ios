//
//  PdfReaderView.swift
//  Zotero
//
//  Created by Michal Rentka on 13/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

#if PDFENABLED
import PSPDFKit
import PSPDFKitUI
#endif

struct PdfReaderView: UIViewControllerRepresentable {
    let url: URL

    #if PDFENABLED

    func makeUIViewController(context: Context) -> PSPDFViewController {
        return PSPDFViewController(document: PSPDFDocument(url: self.url))
    }

    func updateUIViewController(_ uiViewController: PSPDFViewController, context: Context) {}

    #else

    func makeUIViewController(context: Context) -> UIViewController {
        return UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    #endif
}

#if DEBUG

struct PdfReaderView_Previews: PreviewProvider {
    static var previews: some View {
        PdfReaderView(url: URL(fileURLWithPath: ""))
    }
}

#endif
