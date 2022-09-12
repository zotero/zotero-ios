//
//  PDFExportSettingsView.swift
//  Zotero
//
//  Created by Michal Rentka on 12.09.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import SwiftUI

struct PDFExportSettingsView: View {
    @State var settings: PDFExportSettings
    let exportHandler: ((PDFExportSettings) -> Void)

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 20) {
                Toggle(isOn: self.$settings.includeAnnotations) {
                    Text(L10n.Pdf.Export.includeAnnotations)
                }

                Button {
                    self.exportHandler(self.settings)
                } label: {
                    Text(L10n.Pdf.Export.export)
                        .padding()
                        .frame(width: proxy.size.width)
                }
                .foregroundColor(.white)
                .background(Asset.Colors.zoteroBlueWithDarkMode.swiftUiColor)
            }
        }
        .padding()
    }
}

struct PDFExportSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        PDFExportSettingsView(settings: PDFExportSettings(includeAnnotations: false), exportHandler: { _ in })
    }
}

#endif
