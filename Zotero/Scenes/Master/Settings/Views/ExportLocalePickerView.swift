//
//  ExportLocalePickerView.swift
//  Zotero
//
//  Created by Michal Rentka on 14.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct ExportLocalePickerView: View {
    @EnvironmentObject var viewModel: ViewModel<ExportLocalePickerActionHandler>
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

    let picked: (String) -> Void

    var body: some View {
        if self.viewModel.state.loading {
            ActivityIndicatorView(style: .medium, isAnimating: .constant(true))
                .onAppear {
                    self.viewModel.process(action: .load)
                }
        } else {
            Form {
                ForEach(self.viewModel.state.locales) { locale in
                    Button {
                        self.viewModel.process(action: .setLocale(locale.id))
                        self.picked(locale.name)
                        self.presentationMode.wrappedValue.dismiss()
                    } label: {
                        SinglePickerRow(text: locale.name, isSelected: (self.viewModel.state.selected == locale.id))
                            .foregroundColor(Color(self.textColor))
                    }
                }
            }
        }
    }

    private var textColor: UIColor {
        return UIColor(dynamicProvider: { traitCollection -> UIColor in
            return traitCollection.userInterfaceStyle == .dark ? .white : .black
        })
    }
}

struct ExportLocalePickerView_Previews: PreviewProvider {
    static var previews: some View {
        ExportLocalePickerView(picked: { _ in })
    }
}
