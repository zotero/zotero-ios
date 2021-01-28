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

            self.data.flatMap({ Text(self.storageDataString(for: $0)) }) ?? Text("-")

            if (self.data?.fileCount ?? 0) > 0 {
                self.deleteAction.flatMap {
                    Button(action: $0) {
                        Image(systemName: "trash")
                    }
                }
            }
        }
    }

    private func storageDataString(for data: DirectoryData) -> String {
        let mbString = String(format: "%.2f", data.mbSize)
        return (data.fileCount == 1 ? L10n.Settings.Storage.oneFile : L10n.Settings.Storage.multipleFiles(data.fileCount)) + " (\(mbString) MB)"
    }
}

struct StorageSettingsRow_Previews: PreviewProvider {
    static var previews: some View {
        StorageSettingsRow(title: "TOTAL", data: DirectoryData(fileCount: 2, mbSize: 1)) {}
    }
}
