//
//  TypesettingMenuViewController.swift
//  Zotero
//
//  Created by Basil on 18.01.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

protocol TypesettingMenuDelegate: AnyObject {
    func typesettingMenuDidUpdateSettings(_ settings: TypesettingSettings)
}

final class TypesettingMenuViewController: UITableViewController {
    weak var delegate: TypesettingMenuDelegate?
    private var settings: TypesettingSettings
    private let documentKey: String?
    
    enum Section: Int, CaseIterable {
        case font
        case textFormatting
        case margins
        case advanced
        case actions
        
        var title: String {
            switch self {
            case .font: return "Font"
            case .textFormatting: return "Text Formatting"
            case .margins: return "Margins & Layout"
            case .advanced: return "Advanced Typography"
            case .actions: return "Actions"
            }
        }
    }
    
    init(settings: TypesettingSettings, documentKey: String? = nil) {
        self.settings = settings
        self.documentKey = documentKey
        super.init(style: .insetGrouped)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Typesetting"
        
        tableView.register(SliderCell.self, forCellReuseIdentifier: "SliderCell")
        tableView.register(SegmentedControlCell.self, forCellReuseIdentifier: "SegmentedCell")
        tableView.register(TypesettingSwitchCell.self, forCellReuseIdentifier: "SwitchCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
    }
    
    private func updateSetting<T>(_ keyPath: WritableKeyPath<TypesettingSettings, T>, value: T) {
        settings[keyPath: keyPath] = value
        // Apply settings immediately for live preview
        FontManager.shared.setTypesettingSettings(settings, forDocument: documentKey ?? "default")
        delegate?.typesettingMenuDidUpdateSettings(settings)
    }
    
    // MARK: - Table View Data Source
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        
        switch section {
        case .font: return 5 // Added contrast
        case .textFormatting: return 8 // Added word expansion and monospace scale
        case .margins: return 6
        case .advanced: return 6
        case .actions: return 2
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return Section(rawValue: section)?.title
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        
        switch section {
        case .font:
            return "Font settings control the typeface, size, weight, contrast, and rendering quality"

        case .textFormatting:
            return "Text formatting options control spacing, alignment, text flow, and monospace font scaling"

        case .margins:
            return "Adjust margins and page layout including multi-column support"

        case .advanced:
            return "Advanced typographic features for fine-tuned text rendering"

        case .actions:
            return nil
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }
        
        switch section {
        case .font:
            return configureFontCell(for: indexPath)

        case .textFormatting:
            return configureTextFormattingCell(for: indexPath)

        case .margins:
            return configureMarginsCell(for: indexPath)

        case .advanced:
            return configureAdvancedCell(for: indexPath)

        case .actions:
            return configureActionsCell(for: indexPath)
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard let section = Section(rawValue: indexPath.section) else { return }
        
        switch section {
        case .font:
            if indexPath.row == 0 {
                showFontPicker()
            }

        case .textFormatting:
            if indexPath.row == 4 {
                showTextAlignmentPicker()
            }

        case .advanced:
            break

        case .actions:
            if indexPath.row == 0 {
                resetToDefaults()
            } else {
                saveAsDefault()
            }

        case .margins:
            break
        }
    }
    
    // MARK: - Cell Configuration
    
    private func configureFontCell(for indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.row {
        case 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            cell.textLabel?.text = "Font Family"
            cell.detailTextLabel?.text = settings.fontFamily ?? "System Default"
            cell.accessoryType = .disclosureIndicator
            return cell
            
        case 1:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "SliderCell", for: indexPath) as? SliderCell else {
                return UITableViewCell()
            }
            cell.configure(
                title: "Font Size",
                value: Float(settings.fontSize),
                range: 10...32,
                formatter: { String(format: "%.0f pt", $0) },
                onChange: { [weak self] value in
                    self?.settings.fontSize = CGFloat(value)
                    self?.notifyChange()
                }
            )
            return cell
            
        case 2:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "SegmentedCell", for: indexPath) as? SegmentedControlCell else {
                return UITableViewCell()
            }
            cell.setup(
                selected: TypesettingSettings.FontWeight.allCases.firstIndex(of: settings.fontWeight) ?? 1,
                segments: TypesettingSettings.FontWeight.allCases.map { $0.rawValue }
            ) { [weak self] (index: Int) in
                self?.settings.fontWeight = TypesettingSettings.FontWeight.allCases[index]
                self?.notifyChange()
            }
            return cell
            
        case 3:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "SegmentedCell", for: indexPath) as? SegmentedControlCell else {
                return UITableViewCell()
            }
            cell.setup(
                selected: TypesettingSettings.FontHinting.allCases.firstIndex(of: settings.fontHinting) ?? 2,
                segments: TypesettingSettings.FontHinting.allCases.map { $0.rawValue }
            ) { [weak self] (index: Int) in
                self?.settings.fontHinting = TypesettingSettings.FontHinting.allCases[index]
                self?.notifyChange()
            }
            return cell
            
        case 4:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "SliderCell", for: indexPath) as? SliderCell else {
                return UITableViewCell()
            }
            cell.configure(
                title: "Contrast",
                value: Float(settings.contrast),
                range: 0.5...2.0,
                formatter: { String(format: "%.2fx", $0) },
                onChange: { [weak self] value in
                    self?.settings.contrast = CGFloat(value)
                    self?.notifyChange()
                }
            )
            return cell
            
        default:
            return UITableViewCell()
        }
    }
    
    private func configureTextFormattingCell(for indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.row {
        case 0:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "SliderCell", for: indexPath) as? SliderCell else {
                return UITableViewCell()
            }
            cell.configure(
                title: "Line Spacing",
                value: Float(settings.lineSpacing),
                range: 0.8...2.5,
                formatter: { String(format: "%.1fx", $0) },
                onChange: { [weak self] value in
                    self?.settings.lineSpacing = CGFloat(value)
                    self?.notifyChange()
                }
            )
            return cell
            
        case 1:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "SliderCell", for: indexPath) as? SliderCell else {
                return UITableViewCell()
            }
            cell.configure(
                title: "Paragraph Spacing",
                value: Float(settings.paragraphSpacing),
                range: 0.0...2.0,
                formatter: { String(format: "%.1fem", $0) },
                onChange: { [weak self] value in
                    self?.settings.paragraphSpacing = CGFloat(value)
                    self?.notifyChange()
                }
            )
            return cell
            
        case 2:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "SegmentedCell", for: indexPath) as? SegmentedControlCell else {
                return UITableViewCell()
            }
            cell.setup(
                selected: TypesettingSettings.WordSpacing.allCases.firstIndex(of: settings.wordSpacing) ?? 2,
                segments: TypesettingSettings.WordSpacing.allCases.map { $0.rawValue }
            ) { [weak self] (index: Int) in
                self?.settings.wordSpacing = TypesettingSettings.WordSpacing.allCases[index]
                self?.notifyChange()
            }
            return cell
            
        case 3:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "SliderCell", for: indexPath) as? SliderCell else {
                return UITableViewCell()
            }
            cell.configure(
                title: "Letter Spacing",
                value: Float(settings.letterSpacing),
                range: -0.5...2.0,
                formatter: { String(format: "%.2fem", $0) },
                onChange: { [weak self] value in
                    self?.settings.letterSpacing = CGFloat(value)
                    self?.notifyChange()
                }
            )
            return cell
            
        case 4:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            cell.textLabel?.text = "Text Alignment"
            cell.detailTextLabel?.text = settings.textAlignment.rawValue
            cell.accessoryType = .disclosureIndicator
            return cell
            
        case 5:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "SliderCell", for: indexPath) as? SliderCell else {
                return UITableViewCell()
            }
            cell.configure(
                title: "First Line Indent",
                value: Float(settings.firstLineIndent),
                range: 0.0...5.0,
                formatter: { String(format: "%.1fem", $0) },
                onChange: { [weak self] value in
                    self?.settings.firstLineIndent = CGFloat(value)
                    self?.notifyChange()
                }
            )
            return cell
            
        case 6:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "SegmentedCell", for: indexPath) as? SegmentedControlCell else {
                return UITableViewCell()
            }
            cell.setup(
                selected: TypesettingSettings.WordExpansion.allCases.firstIndex(of: settings.wordExpansion) ?? 2,
                segments: TypesettingSettings.WordExpansion.allCases.map { $0.rawValue }
            ) { [weak self] (index: Int) in
                self?.settings.wordExpansion = TypesettingSettings.WordExpansion.allCases[index]
                self?.notifyChange()
            }
            return cell
            
        case 7:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "SliderCell", for: indexPath) as? SliderCell else {
                return UITableViewCell()
            }
            cell.configure(
                title: "Monospace Font Scale",
                value: Float(settings.monospaceScale * 100),
                range: 50...150,
                formatter: { String(format: "%.0f%%", $0) },
                onChange: { [weak self] value in
                    self?.settings.monospaceScale = CGFloat(value) / 100.0
                    self?.notifyChange()
                }
            )
            return cell
            
        default:
            return UITableViewCell()
        }
    }
    
    private func configureMarginsCell(for indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "SliderCell", for: indexPath) as? SliderCell else {
            return UITableViewCell()
        }
        
        switch indexPath.row {
        case 0:
            cell.configure(
                title: "Top Margin",
                value: Float(settings.topMargin),
                range: 0...100,
                formatter: { String(format: "%.0f pt", $0) },
                onChange: { [weak self] value in
                    self?.settings.topMargin = CGFloat(value)
                    self?.notifyChange()
                }
            )

        case 1:
            cell.configure(
                title: "Bottom Margin",
                value: Float(settings.bottomMargin),
                range: 0...100,
                formatter: { String(format: "%.0f pt", $0) },
                onChange: { [weak self] value in
                    self?.settings.bottomMargin = CGFloat(value)
                    self?.notifyChange()
                }
            )

        case 2:
            cell.configure(
                title: "Left Margin",
                value: Float(settings.leftMargin),
                range: 0...100,
                formatter: { String(format: "%.0f pt", $0) },
                onChange: { [weak self] value in
                    self?.settings.leftMargin = CGFloat(value)
                    self?.notifyChange()
                }
            )

        case 3:
            cell.configure(
                title: "Right Margin",
                value: Float(settings.rightMargin),
                range: 0...100,
                formatter: { String(format: "%.0f pt", $0) },
                onChange: { [weak self] value in
                    self?.settings.rightMargin = CGFloat(value)
                    self?.notifyChange()
                }
            )

        case 4:
            cell.configure(
                title: "Column Count",
                value: Float(settings.columnCount),
                range: 1...3,
                formatter: { String(format: "%.0f", $0) },
                onChange: { [weak self] value in
                    self?.settings.columnCount = Int(value)
                    self?.notifyChange()
                }
            )

        case 5:
            cell.configure(
                title: "Column Gap",
                value: Float(settings.columnGap),
                range: 10...50,
                formatter: { String(format: "%.0f pt", $0) },
                onChange: { [weak self] value in
                    self?.settings.columnGap = CGFloat(value)
                    self?.notifyChange()
                }
            )

        default:
            break
        }
        
        return cell
    }
    
    private func configureAdvancedCell(for indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "SwitchCell", for: indexPath) as? TypesettingSwitchCell else {
            return UITableViewCell()
        }
        
        switch indexPath.row {
        case 0:
            cell.configure(title: "Hyphenation", isOn: settings.hyphenation) { [weak self] (isOn: Bool) in
                self?.settings.hyphenation = isOn
                self?.notifyChange()
            }

        case 1:
            cell.configure(title: "Ligatures", isOn: settings.ligatures) { [weak self] (isOn: Bool) in
                self?.settings.ligatures = isOn
                self?.notifyChange()
            }

        case 2:
            cell.configure(title: "Widow/Orphan Control", isOn: settings.widowOrphanControl) { [weak self] (isOn: Bool) in
                self?.settings.widowOrphanControl = isOn
                self?.notifyChange()
            }

        case 3:
            cell.configure(title: "Ignore Publisher Styles", isOn: settings.ignorePublisherStyles) { [weak self] (isOn: Bool) in
                self?.settings.ignorePublisherStyles = isOn
                self?.notifyChange()
            }

        case 4:
            cell.configure(title: "Ignore Publisher Fonts", isOn: settings.ignorePublisherFonts) { [weak self] (isOn: Bool) in
                self?.settings.ignorePublisherFonts = isOn
                self?.notifyChange()
            }

        case 5:
            guard let segmentedCell = tableView.dequeueReusableCell(withIdentifier: "SegmentedCell", for: indexPath) as? SegmentedControlCell else {
                return UITableViewCell()
            }
            segmentedCell.setup(
                selected: TypesettingSettings.Justification.allCases.firstIndex(of: settings.justification) ?? 1,
                segments: TypesettingSettings.Justification.allCases.map { $0.rawValue }
            ) { [weak self] (index: Int) in
                self?.settings.justification = TypesettingSettings.Justification.allCases[index]
                self?.notifyChange()
            }
            return segmentedCell

        default:
            break
        }
        
        return cell
    }
    
    private func configureActionsCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        
        switch indexPath.row {
        case 0:
            cell.textLabel?.text = "Reset to Defaults"
            cell.textLabel?.textColor = .systemRed

        case 1:
            cell.textLabel?.text = documentKey != nil ? "Save for All Documents" : "Save as Default"
            cell.textLabel?.textColor = .systemBlue

        default:
            break
        }
        
        return cell
    }
    
    // MARK: - Actions
    
    private func showFontPicker() {
        let fontPicker = FontManagementViewController(documentKey: documentKey)
        fontPicker.delegate = self
        let nav = UINavigationController(rootViewController: fontPicker)
        present(nav, animated: true)
    }
    
    private func showTextAlignmentPicker() {
        let alert = UIAlertController(title: "Text Alignment", message: nil, preferredStyle: .actionSheet)
        
        for alignment in TypesettingSettings.TextAlignment.allCases {
            alert.addAction(UIAlertAction(title: alignment.rawValue, style: .default) { [weak self] _ in
                self?.settings.textAlignment = alignment
                self?.notifyChange()
                self?.tableView.reloadRows(at: [IndexPath(row: 4, section: Section.textFormatting.rawValue)], with: .automatic)
            })
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func resetToDefaults() {
        let alert = UIAlertController(
            title: "Reset to Defaults",
            message: "This will reset all typesetting settings to their default values.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Reset", style: .destructive) { [weak self] _ in
            self?.settings = .default
            self?.tableView.reloadData()
            self?.notifyChange()
        })
        
        present(alert, animated: true)
    }
    
    private func saveAsDefault() {
        FontManager.shared.setDefaultTypesettingSettings(settings)
        
        let alert = UIAlertController(
            title: "Saved",
            message: "These settings will be used as default for all documents.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func notifyChange() {
        // Save settings immediately for live preview
        FontManager.shared.setTypesettingSettings(settings, forDocument: documentKey ?? "default")
        delegate?.typesettingMenuDidUpdateSettings(settings)
    }
}

// MARK: - FontManagementDelegate

extension TypesettingMenuViewController: FontManagementDelegate {
    func fontManagementDidSelectFont(_ font: FontMetadata?, forDocument documentKey: String?) {
        settings.fontFamily = font?.postScriptName
        tableView.reloadRows(at: [IndexPath(row: 0, section: Section.font.rawValue)], with: .automatic)
        notifyChange()
    }
    
    func fontManagementDidUpdateSettings() {
        // No additional action needed
    }
}

// MARK: - Custom Cells

private class SliderCell: UITableViewCell {
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let slider = UISlider()
    private var valueFormatter: ((Float) -> String)?
    private var onChange: ((Float) -> Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        selectionStyle = .none
        
        titleLabel.font = .preferredFont(forTextStyle: .body)
        valueLabel.font = .preferredFont(forTextStyle: .callout)
        valueLabel.textColor = .secondaryLabel
        
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        
        let labelStack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        labelStack.axis = .horizontal
        labelStack.distribution = .equalSpacing
        
        let mainStack = UIStackView(arrangedSubviews: [labelStack, slider])
        mainStack.axis = .vertical
        mainStack.spacing = 8
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(mainStack)
        
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }
    
    func configure(title: String, value: Float, range: ClosedRange<Float>, formatter: @escaping (Float) -> String, onChange: @escaping (Float) -> Void) {
        titleLabel.text = title
        slider.minimumValue = range.lowerBound
        slider.maximumValue = range.upperBound
        slider.value = value
        self.valueFormatter = formatter
        self.onChange = onChange
        valueLabel.text = formatter(value)
    }
    
    @objc private func sliderChanged() {
        valueLabel.text = valueFormatter?(slider.value)
        onChange?(slider.value)
    }
}

// MARK: - Custom Cells

private class TypesettingSwitchCell: UITableViewCell {
    private let titleLabel = UILabel()
    private let switchControl = UISwitch()
    private var onChange: ((Bool) -> Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        selectionStyle = .none
        
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        switchControl.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
        switchControl.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(titleLabel)
        contentView.addSubview(switchControl)
        
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: switchControl.leadingAnchor, constant: -8),
            
            switchControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            switchControl.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }
    
    func configure(title: String, isOn: Bool, onChange: @escaping (Bool) -> Void) {
        titleLabel.text = title
        switchControl.isOn = isOn
        self.onChange = onChange
    }
    
    @objc private func switchChanged() {
        onChange?(switchControl.isOn)
    }
}
