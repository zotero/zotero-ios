//
//  ProgressView.swift
//  Zotero
//
//  Created by Michal Rentka on 11/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ProgressView: View {
    let value: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .opacity(0.1)
                    .background(Color.gray.opacity(0.1))
                Rectangle()
                    .frame(width: (geometry.size.width * self.value))
                    .opacity(0.5)
                    .background(Color.blue)
                    .animation(.default)
            }
        }
    }
}

struct ProgressView_Previews: PreviewProvider {
    static var previews: some View {
        ProgressView(value: 0.75).frame(height: 8).padding()
    }
}
