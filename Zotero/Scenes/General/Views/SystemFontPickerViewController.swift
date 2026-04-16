//
//  SystemFontPickerViewController.swift
//  Zotero
//
//  Created by Basil on 18.01.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

protocol SystemFontPickerDelegate: AnyObject {
    func systemFontPicker(_ picker: SystemFontPickerViewController, didSelectFont fontName: String)
}

final class SystemFontPickerViewController: UITableViewController {
    weak var delegate: SystemFontPickerDelegate?
    private var selectedFont: String?
    private var fontFamilies: [String] = []
    private var filteredFontFamilies: [String] = []
    private var searchController: UISearchController!
    
    init(selectedFont: String?) {
        self.selectedFont = selectedFont
        super.init(style: .insetGrouped)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "System Fonts"
        
        setupSearchController()
        
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        
        loadFontFamilies()
    }
    
    private func setupSearchController() {
        searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search fonts"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }
    
    private func loadFontFamilies() {
        fontFamilies = UIFont.familyNames.sorted()
        filteredFontFamilies = fontFamilies
        tableView.reloadData()
    }
    
    private func filterFonts(for searchText: String) {
        if searchText.isEmpty {
            filteredFontFamilies = fontFamilies
        } else {
            filteredFontFamilies = fontFamilies.filter { $0.localizedCaseInsensitiveContains(searchText) }
        }
        tableView.reloadData()
    }
    
    // MARK: - Table View
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredFontFamilies.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let familyName = filteredFontFamilies[indexPath.row]
        
        cell.textLabel?.text = familyName
        if let font = UIFont(name: familyName, size: 17) ?? UIFont.fontNames(forFamilyName: familyName).first.flatMap({ UIFont(name: $0, size: 17) }) {
            cell.textLabel?.font = font
        }
        
        cell.accessoryType = familyName == selectedFont ? .checkmark : .none
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let familyName = filteredFontFamilies[indexPath.row]
        
        // Show font variants if multiple exist
        let fontNames = UIFont.fontNames(forFamilyName: familyName)
        if fontNames.count > 1 {
            showFontVariants(familyName: familyName, fontNames: fontNames)
        } else if let fontName = fontNames.first {
            delegate?.systemFontPicker(self, didSelectFont: fontName)
            navigationController?.popViewController(animated: true)
        }
    }
    
    private func showFontVariants(familyName: String, fontNames: [String]) {
        let alert = UIAlertController(
            title: familyName,
            message: "Select a font variant",
            preferredStyle: .actionSheet
        )
        
        for fontName in fontNames.sorted() {
            alert.addAction(UIAlertAction(title: fontName, style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.delegate?.systemFontPicker(self, didSelectFont: fontName)
                self.navigationController?.popViewController(animated: true)
            })
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = tableView
            let indexPath = filteredFontFamilies.firstIndex(of: familyName).map { IndexPath(row: $0, section: 0) }
            if let indexPath = indexPath, let cell = tableView.cellForRow(at: indexPath) {
                popover.sourceRect = cell.bounds
            }
        }
        
        present(alert, animated: true)
    }
}

// MARK: - UISearchResultsUpdating

extension SystemFontPickerViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        filterFonts(for: searchController.searchBar.text ?? "")
    }
}
