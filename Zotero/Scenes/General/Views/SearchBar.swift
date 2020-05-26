//
//  SearchBar.swift
//  Zotero
//
//  Created by Michal Rentka on 20/05/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import SwiftUI

import RxSwift

struct SearchBar: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String

    private let disposeBag = DisposeBag()

    func makeUIView(context: UIViewRepresentableContext<SearchBar>) -> UISearchBar {
        let searchBar = UISearchBar(frame: .zero)
        searchBar.placeholder = placeholder
        searchBar.searchBarStyle = .minimal
        searchBar.autocapitalizationType = .none

        searchBar.rx.text.observeOn(MainScheduler.instance)
                         .debounce(.milliseconds(150), scheduler: MainScheduler.instance)
                         .subscribe(onNext: { text in
                             self.text = (text ?? "")
                         })
                         .disposed(by: self.disposeBag)

        return searchBar
    }

    func updateUIView(_ uiView: UISearchBar, context: UIViewRepresentableContext<SearchBar>) {
        uiView.text = self.text
    }
}
