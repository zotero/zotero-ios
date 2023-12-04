//
//  PdfThumbnailsCell.swift
//  Zotero
//
//  Created by Michal Rentka on 04.12.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

final class PdfThumbnailsCell: UICollectionViewListCell {
    private(set) var disposeBag: DisposeBag = DisposeBag()

    override func prepareForReuse() {
        super.prepareForReuse()
        self.disposeBag = DisposeBag()
    }

    struct ContentConfiguration: UIContentConfiguration {
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
                self.apply(configuration: configuration)
            }
        }

        private weak var imageView: UIImageView!
        private weak var activityIndicator: UIActivityIndicatorView!

        init(configuration: ContentConfiguration) {
            self.configuration = configuration

            super.init(frame: .zero)

            self.backgroundColor = .systemGray6
            self.setupView()
            self.apply(configuration: configuration)
        }

        required init?(coder: NSCoder) {
            fatalError()
        }

        private func apply(configuration: ContentConfiguration) {
            if let image = configuration.image {
                imageView.image = configuration.image
                imageView.isHidden = false
                activityIndicator.stopAnimating()
            } else {
                imageView.isHidden = true
                activityIndicator.isHidden = false
                activityIndicator.startAnimating()
            }
        }

        private func setupView() {
            let activityIndicator = UIActivityIndicatorView(style: .medium)
            activityIndicator.tintColor = .gray
            activityIndicator.hidesWhenStopped = true
            activityIndicator.isHidden = true
            addSubview(activityIndicator)

            let imageView = UIImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFit
            addSubview(imageView)

            NSLayoutConstraint.activate([
                activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
                activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
                imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
                imageView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 15),
                trailingAnchor.constraint(greaterThanOrEqualTo: imageView.trailingAnchor, constant: 15),
                imageView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 20),
                imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
                heightAnchor.constraint(equalToConstant: 100)
            ])
        }
    }
}
