//
//  ItemPickerView.swift
//  ZShare
//
//  Created by Michal Rentka on 02/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ItemPickerView: View {
    let data: [(key: String, value: String)]
    let picked: ((String, String)) -> Void

    var body: some View {
        List {
            ForEach(self.data, id: \.key) { data in
                Text(data.value)
                    .onTapGesture {
                        self.picked(data)
                    }
            }
        }
    }
}

struct ItemPickerView_Previews: PreviewProvider {
    static var previews: some View {
        ItemPickerView(data: []) { _ in }
    }
}
