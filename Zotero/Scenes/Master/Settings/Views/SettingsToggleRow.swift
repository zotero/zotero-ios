//
//  SettingsToggleRow.swift
//  Zotero
//
//  Created by Michal Rentka on 15/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct SettingsToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var value: Bool

    var body: some View {
        Toggle(isOn: self.$value) {
            VStack(alignment: .leading) {
                Text(self.title)
                    .font(.headline)
                self.subtitle.flatMap {
                    Text($0)
                        .font(.callout)
                        .foregroundColor(.gray)
                }
            }
        }
    }
}

struct SettingsToggleRow_Previews: PreviewProvider {
    static var previews: some View {
        List {
            SettingsToggleRow(title: "Some title", subtitle: "Some subtitle", value: .constant(false))
        }
    }
}
