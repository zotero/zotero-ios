//
//  FontManagementViewController.swift
//  Zotero
//
//  Created by Basil on 18.01.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import UniformTypeIdentifiers

protocol FontManagementDelegate: AnyObject {
    func fontManagementDidSelectFont(_ font: FontMetadata?, forDocument documentKey: String?)
    func fontManagementDidUpdateSettings()
}

final class FontManagementViewController: UITableViewController {
    weak var delegate: FontManagementDelegate?
    private let documentKey: String?
    private let fontManager = FontManager.shared
    private var fonts: [FontMetadata] = []
    private var selectedFont: String?
    
    enum Section: Int, CaseIterable {
        case actions
        case currentSelection
        case installedFonts
        
        var title: String {
            switch self {
            case .actions: return "Actions"
            case .currentSelection: return "Current Selection"
            case .installedFonts: return "Installed Fonts"
            }
        }
    }
    
    init(documentKey: String? = nil) {
        self.documentKey = documentKey
        super.init(style: .insetGrouped)
        
        // Get current font selection
        if let documentKey = documentKey {
            selectedFont = fontManager.font(forDocument: documentKey)
        } else {
            selectedFont = fontManager.preferences.defaultFont
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = documentKey != nil ? "Document Font" : "Default Font"
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneButtonTapped)
        )
        
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.register(FontCell.self, forCellReuseIdentifier: "FontCell")
        
        loadFonts()
        
        fontManager.delegate = self
    }
    
    private func loadFonts() {
        fonts = fontManager.getAllFonts()
        tableView.reloadData()
    }
    
    @objc private func doneButtonTapped() {
        dismiss(animated: true)
    }
    
    @objc private func importFontTapped() {
        let documentPicker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.truetypefont, .otfFont, .ttcFont],
            asCopy: true
        )
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = true
        present(documentPicker, animated: true)
    }
    
    @objc private func clearSelectionTapped() {
        selectedFont = nil
        if let documentKey = documentKey {
            fontManager.setFont(nil, forDocument: documentKey)
        } else {
            fontManager.setDefaultFont(nil)
        }
        delegate?.fontManagementDidSelectFont(nil, forDocument: documentKey)
        tableView.reloadSections([Section.currentSelection.rawValue, Section.installedFonts.rawValue], with: .automatic)
    }
    
    // MARK: - Table View Data Source
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        
        switch section {
        case .actions:
            return 2

        case .currentSelection:
            return 1

        case .installedFonts:
            return fonts.count
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return Section(rawValue: section)?.title
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        
        switch section {
        case .actions:
            return "Import custom TTF, OTF, or TTC font files to use in your ebooks"

        case .currentSelection:
            if documentKey != nil {
                return "Font for this document only. Clear to use default font."
            } else {
                return "Default font used for all ebooks unless overridden per-document"
            }

        case .installedFonts:
            return fonts.isEmpty ? "No custom fonts installed. Tap 'Import Font' to add fonts." : nil
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }
        
        switch section {
        case .actions:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            cell.textLabel?.textAlignment = .left
            if indexPath.row == 0 {
                cell.textLabel?.text = "Import Font..."
                cell.textLabel?.textColor = .systemBlue
                cell.accessoryType = .none
            } else {
                cell.textLabel?.text = "System Fonts"
                cell.accessoryType = .disclosureIndicator
            }
            return cell
            
        case .currentSelection:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            if let selectedFont = selectedFont,
               let metadata = fontManager.getFontMetadata(for: selectedFont) {
                cell.textLabel?.text = metadata.displayName
                cell.detailTextLabel?.text = "Tap to change"
            } else {
                cell.textLabel?.text = documentKey != nil ? "Use Default Font" : "System Default"
                cell.detailTextLabel?.text = nil
            }
            cell.textLabel?.textAlignment = .left
            cell.accessoryType = .disclosureIndicator
            return cell
            
        case .installedFonts:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "FontCell", for: indexPath) as? FontCell else {
                return UITableViewCell()
            }
            
            let font = fonts[indexPath.row]
            cell.configure(with: font, isSelected: font.postScriptName == selectedFont)
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard let section = Section(rawValue: indexPath.section) else { return }
        
        switch section {
        case .actions:
            if indexPath.row == 0 {
                importFontTapped()
            } else {
                showSystemFontPicker()
            }
            
        case .currentSelection:
            if selectedFont != nil {
                showClearConfirmation()
            }
            
        case .installedFonts:
            let font = fonts[indexPath.row]
            selectedFont = font.postScriptName
            
            if let documentKey = documentKey {
                fontManager.setFont(font.postScriptName, forDocument: documentKey)
            } else {
                fontManager.setDefaultFont(font.postScriptName)
            }
            
            delegate?.fontManagementDidSelectFont(font, forDocument: documentKey)
            
            tableView.reloadSections([Section.currentSelection.rawValue, Section.installedFonts.rawValue], with: .automatic)
        }
    }
    
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard Section(rawValue: indexPath.section) == .installedFonts else { return nil }
        
        let font = fonts[indexPath.row]
        
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            self?.deleteFont(font)
            completion(true)
        }
        
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if Section(rawValue: indexPath.section) == .installedFonts {
            return 70
        }
        return UITableView.automaticDimension
    }
    
    // MARK: - Font Management
    
    private func deleteFont(_ font: FontMetadata) {
        let alert = UIAlertController(
            title: "Delete Font",
            message: "Are you sure you want to delete '\(font.displayName)'? This cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            do {
                try self?.fontManager.removeFont(font)
                self?.loadFonts()
            } catch {
                self?.showError(error)
            }
        })
        
        present(alert, animated: true)
    }
    
    private func showSystemFontPicker() {
        let picker = SystemFontPickerViewController(selectedFont: selectedFont)
        picker.delegate = self
        navigationController?.pushViewController(picker, animated: true)
    }
    
    private func showClearConfirmation() {
        let alert = UIAlertController(
            title: "Clear Selection",
            message: documentKey != nil ? "Use the default font for this document?" : "Remove default font selection?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear", style: .default) { [weak self] _ in
            self?.clearSelectionTapped()
        })
        
        present(alert, animated: true)
    }
    
    private func showError(_ error: Error) {
        let alert = UIAlertController(
            title: "Error",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UIDocumentPickerDelegate

extension FontManagementViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        var successCount = 0
        var errors: [Error] = []
        
        for url in urls {
            do {
                _ = try fontManager.importFont(from: url)
                successCount += 1
            } catch {
                errors.append(error)
            }
        }
        
        if successCount > 0 {
            loadFonts()
        }
        
        if !errors.isEmpty {
            let message = errors.map { $0.localizedDescription }.joined(separator: "\n")
            showError(NSError(domain: "FontImport", code: 0, userInfo: [NSLocalizedDescriptionKey: message]))
        }
    }
}

// MARK: - FontManagerDelegate

extension FontManagementViewController: FontManagerDelegate {
    func fontManager(_ manager: FontManager, didUpdateFonts fonts: [FontMetadata]) {
        loadFonts()
    }
    
    func fontManager(_ manager: FontManager, didFailWithError error: Error) {
        showError(error)
    }
}

// MARK: - SystemFontPickerDelegate

extension FontManagementViewController: SystemFontPickerDelegate {
    func systemFontPicker(_ picker: SystemFontPickerViewController, didSelectFont fontName: String) {
        selectedFont = fontName
        
        if let documentKey = documentKey {
            fontManager.setFont(fontName, forDocument: documentKey)
        } else {
            fontManager.setDefaultFont(fontName)
        }
        
        // Create temporary metadata for system font
        let metadata = FontMetadata(
            fileName: fontName,
            displayName: fontName,
            familyName: fontName,
            postScriptName: fontName,
            weight: .regular,
            isItalic: false,
            dateAdded: Date(),
            fileSize: 0
        )
        
        delegate?.fontManagementDidSelectFont(metadata, forDocument: documentKey)
        
        tableView.reloadSections([Section.currentSelection.rawValue], with: .automatic)
    }
}

// MARK: - FontCell

private class FontCell: UITableViewCell {
    private let fontNameLabel = UILabel()
    private let fontDetailsLabel = UILabel()
    private let previewLabel = UILabel()
    private let checkmarkImageView = UIImageView(image: UIImage(systemName: "checkmark"))
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        fontNameLabel.font = .preferredFont(forTextStyle: .headline)
        fontDetailsLabel.font = .preferredFont(forTextStyle: .caption1)
        fontDetailsLabel.textColor = .secondaryLabel
        previewLabel.text = "The quick brown fox jumps over the lazy dog"
        previewLabel.font = .systemFont(ofSize: 14)
        previewLabel.numberOfLines = 1
        
        checkmarkImageView.tintColor = .systemBlue
        checkmarkImageView.contentMode = .scaleAspectFit
        
        let stackView = UIStackView(arrangedSubviews: [fontNameLabel, fontDetailsLabel, previewLabel])
        stackView.axis = .vertical
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        checkmarkImageView.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(stackView)
        contentView.addSubview(checkmarkImageView)
        
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            stackView.trailingAnchor.constraint(equalTo: checkmarkImageView.leadingAnchor, constant: -8),
            
            checkmarkImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            checkmarkImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkmarkImageView.widthAnchor.constraint(equalToConstant: 20),
            checkmarkImageView.heightAnchor.constraint(equalToConstant: 20)
        ])
    }
    
    func configure(with metadata: FontMetadata, isSelected: Bool) {
        fontNameLabel.text = metadata.displayName
        fontDetailsLabel.text = "\(metadata.familyName) • \(metadata.weight.displayName)\(metadata.isItalic ? " Italic" : "")"
        
        // Try to display preview in the actual font
        if let font = UIFont(name: metadata.postScriptName, size: 14) {
            previewLabel.font = font
        }
        
        checkmarkImageView.isHidden = !isSelected
    }
}

// MARK: - UTType Extension for Fonts

extension UTType {
    static var truetypefont: UTType {
        UTType(filenameExtension: "ttf") ?? .data
    }
    
    static var otfFont: UTType {
        UTType(filenameExtension: "otf") ?? .data
    }
    
    static var ttcFont: UTType {
        UTType(filenameExtension: "ttc") ?? .data
    }
}
