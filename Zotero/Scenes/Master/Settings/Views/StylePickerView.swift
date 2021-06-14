//
//  StylePickerView.swift
//  Zotero
//
//  Created by Michal Rentka on 14.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct StylePickerView: View {
    @EnvironmentObject var viewModel: ViewModel<StylePickerActionHandler>
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

    let picked: (String) -> Void

    var body: some View {
        Form {
            if let results = self.viewModel.state.results {
                ForEach(results) { style in
                    Button {
                        self.viewModel.process(action: .setStyle(style.identifier))
                        self.picked(style.title)
                        self.presentationMode.wrappedValue.dismiss()
                    } label: {
                        SinglePickerRow(text: style.title, isSelected: (self.viewModel.state.selected == style.identifier))
                            .foregroundColor(Color(self.textColor))
                    }
                }
            }
        }
        .onAppear {
            self.viewModel.process(action: .load)
        }
    }

    private var textColor: UIColor {
        return UIColor(dynamicProvider: { traitCollection -> UIColor in
            return traitCollection.userInterfaceStyle == .dark ? .white : .black
        })
    }
}

struct StylePickerView_Previews: PreviewProvider {
    static var previews: some View {
        StylePickerView(picked: { _ in })
    }
}
