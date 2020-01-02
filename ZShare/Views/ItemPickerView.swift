//
//  ItemPickerView.swift
//  ZShare
//
//  Created by Michal Rentka on 02/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemPickerView: View {
    let data: [(String, String)]

    private let picked: ((String, String)) -> Void

    init(data: [String: String], picked: @escaping ((String, String)) -> Void) {
        self.data = data.sorted(by: { $0.value > $1.value })
        self.picked = picked
    }

    var body: some View {
        List {
            ForEach(self.data, id: \.0) { data in
                Text(data.1)
                    .onTapGesture {
                        self.picked(data)
                    }
            }
        }
    }
}

struct ItemPickerView_Previews: PreviewProvider {
    static var previews: some View {
        ItemPickerView(data: [:]) { _ in }
    }
}
