//
//  ClosureTextField.swift
//  Zotero
//
//  Created by Michal Rentka on 03/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ClosureTextField: View {
    let title: String
    @State var text: String
    let didChange: (String) -> Void

    var body: some View {
        TextField(self.title, text: self.$text, onEditingChanged: { _ in
            self.didChange(self.text)
        }, onCommit: {})
    }
}

struct ClosureTextField_Previews: PreviewProvider {
    static var previews: some View {
        ClosureTextField(title: "Test", text: "Some text") { _ in
        }
    }
}
