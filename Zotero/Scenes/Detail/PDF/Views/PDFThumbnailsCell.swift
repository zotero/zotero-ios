//
//  PDFThumbnailsCell.swift
//  Zotero
//
//  Created by Michal Rentka on 04.12.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

final class PDFThumbnailsCell: UICollectionViewListCell {
    private(set) var disposeBag: DisposeBag = DisposeBag()

    override var isSelected: Bool {
        didSet {
            (self.contentView as? ContentView)?.selectionBackground.isHidden = !isSelected
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        (self.contentView as? ContentView)?.selectionBackground.isHidden = !isSelected
        self.disposeBag = DisposeBag()
    }

    struct ContentConfiguration: UIContentConfiguration {
        let label: String
        let image: UIImage?

        func makeContentView() -> UIView & UIContentView {
            return ContentView(configuration: self)
        }

        func updated(for state: UIConfigurationState) -> ContentConfiguration {
            return self
        }
    }

    final class ContentView: UIView, UIContentView {
        var configuration: UIContentConfiguration {
            didSet {
                guard let configuration = self.configuration as? ContentConfiguration else { return }
                apply(configuration: configuration)
            }
        }

        fileprivate weak var selectionBackground: UIView!
        private weak var imageView: UIImageView!
        private weak var imageViewHeight: NSLayoutConstraint!
        private weak var imageViewWidth: NSLayoutConstraint!
        private weak var label: UILabel!
        private weak var activityIndicator: UIActivityIndicatorView!

        init(configuration: ContentConfiguration) {
            self.configuration = configuration

            super.init(frame: .zero)

            backgroundColor = .systemGray6
            setupView()
            apply(configuration: configuration)
        }

        required init?(coder: NSCoder) {
            fatalError()
        }

        private func apply(configuration: ContentConfiguration) {
            if let image = configuration.image {
                imageViewWidth.constant = (image.size.width / image.size.height) * imageViewHeight.constant
                imageView.image = image
                label.text = configuration.label
                imageView.isHidden = false
                label.isHidden = false
                activityIndicator.stopAnimating()
            } else {
                imageView.isHidden = true
                label.isHidden = true
                activityIndicator.isHidden = false
                activityIndicator.startAnimating()
            }
        }

        private func setupView() {
            let selectionBackground = UIView()
            selectionBackground.translatesAutoresizingMaskIntoConstraints = false
            selectionBackground.backgroundColor = .systemGray3
            selectionBackground.layer.cornerRadius = 8
            selectionBackground.layer.masksToBounds = true
            selectionBackground.isHidden = true
            addSubview(selectionBackground)
            self.selectionBackground = selectionBackground

            let activityIndicator = UIActivityIndicatorView(style: .medium)
            activityIndicator.translatesAutoresizingMaskIntoConstraints = false
            activityIndicator.tintColor = .gray
            activityIndicator.hidesWhenStopped = true
            activityIndicator.isHidden = true
            addSubview(activityIndicator)
            self.activityIndicator = activityIndicator

            let imageView = UIImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFit
            addSubview(imageView)
            self.imageView = imageView

            let label = UILabel()
            label.textAlignment = .center
            label.font = .preferredFont(forTextStyle: .body)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.setContentHuggingPriority(.required, for: .vertical)
            label.setContentCompressionResistancePriority(.required, for: .vertical)
            addSubview(label)
            self.label = label

            let imageViewHeight = imageView.heightAnchor.constraint(equalToConstant: PDFThumbnailsLayout.cellImageHeight)
            imageViewHeight.priority = .init(999)
            self.imageViewHeight = imageViewHeight
            let imageViewWidth = imageView.widthAnchor.constraint(equalToConstant: 0)
            imageViewWidth.priority = .defaultHigh
            self.imageViewWidth = imageViewWidth
            let imageViewLeading = imageView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: PDFThumbnailsLayout.cellImageHorizontalMinInset)
            imageViewLeading.priority = .required
            let imageViewTrailing = trailingAnchor.constraint(greaterThanOrEqualTo: imageView.trailingAnchor, constant: PDFThumbnailsLayout.cellImageHorizontalMinInset)
            imageViewTrailing.priority = .required

            NSLayoutConstraint.activate([
                activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
                activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
                imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
                imageViewLeading,
                imageViewTrailing,
                imageView.topAnchor.constraint(equalTo: topAnchor, constant: PDFThumbnailsLayout.cellImageTopInset),
                label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: PDFThumbnailsLayout.cellLabelTopInset),
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PDFThumbnailsLayout.cellImageHorizontalMinInset),
                trailingAnchor.constraint(equalTo: label.trailingAnchor, constant: PDFThumbnailsLayout.cellImageHorizontalMinInset),
                label.bottomAnchor.constraint(equalTo: bottomAnchor),
                imageView.topAnchor.constraint(equalTo: selectionBackground.topAnchor, constant: 10),
                selectionBackground.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 10),
                imageView.leadingAnchor.constraint(equalTo: selectionBackground.leadingAnchor, constant: 10),
                selectionBackground.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 10),
                imageViewHeight,
                imageViewWidth
            ])
        }
    }
}
