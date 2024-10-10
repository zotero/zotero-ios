//
//  SettingsListButtonRow.swift
//  Zotero
//
//  Created by Michal Rentka on 14.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct SettingsListButtonRow: View {
    let text: String
    let detailText: String?
    let enabled: Bool

    var body: some View {
        HStack {
            Text(self.text)
                .foregroundColor(Color(self.textColor))

            Spacer()

            if let text = self.detailText {
                Text(text)
                    .foregroundColor(Color(UIColor.systemGray))
            }

            Image(systemName: "chevron.right")
                .foregroundColor(Color(UIColor.systemGray))
                .font(.body.weight(.semibold))
                .imageScale(.small)
                .opacity(0.7)
        }
    }

    private var textColor: UIColor {
        if !self.enabled {
            return .systemGray
        }
        return UIColor(dynamicProvider: { traitCollection -> UIColor in
            return traitCollection.userInterfaceStyle == .dark ? .white : .black
        })
    }
}

struct SettingsListButtonRow_Previews: PreviewProvider {
    static var previews: some View {
        SettingsListButtonRow(text: "Test", detailText: nil, enabled: true)
    }
}
