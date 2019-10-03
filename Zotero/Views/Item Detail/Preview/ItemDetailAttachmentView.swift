//
//  ItemDetailAttachmentView.swift
//  Zotero
//
//  Created by Michal Rentka on 29/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemDetailAttachmentView: View {
    let iconName: String
    let title: String
    let rightAccessory: AccessoryView.Accessory?
    let progress: Double?

    var body: some View {
        HStack {
            Image(self.iconName)
                .renderingMode(.original)
                .resizable()
                .frame(width: 18, height: 18)

            Text(self.title)

            if self.rightAccessory != nil {
                Spacer()
            }

            self.rightAccessory.flatMap({
                AccessoryView(accessory: $0, progress: self.progress)
            })
        }
    }
}

struct AccessoryView: View {
    enum Accessory {
        case downloadIcon, progress, disclosureIndicator, error
    }

    // SWIFTUI BUG: - Closure containing control flow statement cannot be used with function builder 'ViewBuilder', add progress and error values to enum when possible

    let accessory: Accessory
    let progress: Double?

    var body: some View {
        Group {
            if self.accessory == .downloadIcon {
                Image(systemName: "square.and.arrow.down").foregroundColor(.blue)
            }
            if self.accessory == .progress {
                self.progress.flatMap({
                    ProgressView(value: CGFloat($0))
                        .frame(maxWidth: 150, maxHeight: 8)
                })
            }
            if self.accessory == .error {
                Image(systemName: "xmark.octagon").foregroundColor(.red)
            }
            if self.accessory == .disclosureIndicator {
                Image(systemName: "chevron.right").foregroundColor(.gray)
            }
        }
    }
}

struct ItemDetailAttachmentView_Previews: PreviewProvider {
    static var previews: some View {
        List {
            ItemDetailAttachmentView(iconName: "pdf",
                                     title: "Some pdf name.pdf",
                                     rightAccessory: .progress,
                                     progress: 0.4)
            ItemDetailAttachmentView(iconName: "web-page",
                                     title: "Website link",
                                     rightAccessory: .disclosureIndicator,
                                     progress: 0.4)
        }
    }
}
