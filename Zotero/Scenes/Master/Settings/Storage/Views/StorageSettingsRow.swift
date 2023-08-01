//
//  StorageSettingsRow.swift
//  Zotero
//
//  Created by Michal Rentka on 04/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct StorageSettingsRow: View {
    let title: String
    let data: DirectoryData?
    let deleteAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Text(self.title)

            Spacer()

            Text(self.storageDataString(for: self.data))

            if (self.data?.fileCount ?? 0) > 0 {
                self.deleteAction.flatMap {
                    Button(action: $0) {
                        Image(systemName: "trash")
                    }
                }
            }
        }
    }

    private func storageDataString(for data: DirectoryData?) -> String {
        guard let data = data, data.fileCount > 0 else { return "-" }
        let mbString = String(format: "%.2f", data.mbSize)
        return (L10n.Settings.Storage.files(data.fileCount)) + " (\(mbString) MB)"
    }
}

struct StorageSettingsRow_Previews: PreviewProvider {
    static var previews: some View {
        StorageSettingsRow(title: "TOTAL", data: DirectoryData(fileCount: 2, mbSize: 1)) {}
    }
}
