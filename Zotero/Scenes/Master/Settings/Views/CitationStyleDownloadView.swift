//
//  CitationStyleDownloadView.swift
//  Zotero
//
//  Created by Michal Rentka on 18.05.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct CitationStyleDownloadView: View {
    @EnvironmentObject var viewModel: ViewModel<CitationsActionHandler>

    let pickAction: (CitationStyle) -> Void

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)

            if self.viewModel.state.loadingRemoteStyles {
                ActivityIndicatorView(style: .medium, isAnimating: .constant(true))
            } else if self.viewModel.state.loadingError != nil {
                CitationStyleErrorView()
            } else {
                CitationStyleContentView(pickAction: self.pickAction)
            }
        }
        .onAppear {
            self.viewModel.process(action: .loadRemoteStyles)
        }
    }
}

fileprivate struct CitationStyleErrorView: View {
    @EnvironmentObject var viewModel: ViewModel<CitationsActionHandler>

    var body: some View {
        VStack(spacing: 16) {
            Text("Could not load styles.")

            Button {
                self.viewModel.process(action: .loadRemoteStyles)
            } label: {
                Text("Try again")
                    .foregroundColor(Color.white)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 8).foregroundColor(Asset.Colors.zoteroBlue.swiftUiColor))
            }
        }
    }
}

fileprivate struct CitationStyleContentView: View {
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
    @EnvironmentObject var viewModel: ViewModel<CitationsActionHandler>

    let pickAction: (CitationStyle) -> Void

    var body: some View {
        Form {
            ForEach(self.viewModel.state.remoteStyles) { style in
                Button(action: {
                    self.pickAction(style)
                    self.presentationMode.wrappedValue.dismiss()
                }, label: {
                    CitationStyleRow(style: style)
                })
            }
        }
    }
}

fileprivate struct CitationStyleRow: View {
    let style: CitationStyle

    var body: some View {
        HStack {
            Text(self.style.title)

            Spacer()

            Text(Formatter.sqlFormat.string(from: self.style.updated))
                .foregroundColor(Color(UIColor.systemGray))
        }
    }
}

struct CitationStyleDownloadView_Previews: PreviewProvider {
    static var previews: some View {
        CitationStyleDownloadView(pickAction: { _ in })
    }
}
