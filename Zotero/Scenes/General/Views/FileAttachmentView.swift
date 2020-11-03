//
//  FileAttachmentView.swift
//  Zotero
//
//  Created by Michal Rentka on 10/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

fileprivate struct LayerData {
    enum Border {
        case borderLine
        case progressLine(CGFloat)
    }

    enum Content {
        case stopSign
        case image(String)
    }

    let border: Border?
    let content: Content
    let badgeName: String?
}

class FileAttachmentView: UIView {
    enum Style {
        case list
        case detail
    }
    
    private static let size: CGFloat = 28
    private static let badgeBorderWidth: CGFloat = 1.5
    private static let badgeSize: CGFloat = 11
    private static let progressCircleWidth: CGFloat = 1.5
    private let disposeBag: DisposeBag

    private var circleLayer: CAShapeLayer!
    private var progressLayer: CAShapeLayer!
    private var stopLayer: CALayer!
    private var imageLayer: CALayer!
    private var badgeLayer: CALayer!
    private var badgeBorder: CALayer!
    private weak var button: UIButton!
    private var mainImageName: String?
    private var badgeImageName: String?
    private var parentBackgroundColor: UIColor?

    var contentInsets: UIEdgeInsets = UIEdgeInsets() {
        didSet {
            self.invalidateIntrinsicContentSize()
        }
    }
    var tapEnabled: Bool {
        get {
            return self.button.isEnabled
        }

        set {
            self.button.isEnabled = newValue
        }
    }
    var tapAction: (() -> Void)?

    // MARK: - Lifecycle

    override init(frame: CGRect) {
        self.disposeBag = DisposeBag()

        super.init(frame: frame)

        self.setup()
    }

    required init?(coder: NSCoder) {
        self.disposeBag = DisposeBag()

        super.init(coder: coder)

        self.setup()
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: (FileAttachmentView.size + self.contentInsets.left + self.contentInsets.right),
                      height: (FileAttachmentView.size + self.contentInsets.top + self.contentInsets.bottom))
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let x = self.contentInsets.left + ((self.bounds.width - self.contentInsets.left - self.contentInsets.right) / 2)
        let y = self.contentInsets.top + ((self.bounds.height - self.contentInsets.top - self.contentInsets.bottom) / 2)
        let center = CGPoint(x: x, y: y)
        // CAShapeLayer draws from center of path, so radius needs to be smaller to achieve outer size of `FileAttachmentView.size`
        let path = UIBezierPath(arcCenter: center,
                                radius: ((FileAttachmentView.size - FileAttachmentView.progressCircleWidth) / 2),
                                startAngle: -.pi / 2,
                                endAngle: 3 * .pi / 2,
                                clockwise: true).cgPath

        self.circleLayer.path = path
        self.progressLayer.path = path
        self.stopLayer.position = center
        self.imageLayer.position = center
        // Badge is supposed to be at bottom right with outer border, so badgeLayer needs to be moved outside of bounds a bit
        self.badgeLayer.position = CGPoint(x: (self.bounds.width - self.contentInsets.right) - 0.5,
                                           y: (self.bounds.height - self.contentInsets.bottom) - 0.5)
        self.badgeBorder.position = self.badgeLayer.position
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        guard self.traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }

        self.circleLayer.strokeColor = UIColor.systemGray5.cgColor
        self.badgeBorder.borderColor = self.parentBackgroundColor?.cgColor

        if let name = self.badgeImageName {
            self.badgeLayer.contents = UIImage(named: name)?.cgImage
        }
        if let name = self.mainImageName {
            self.imageLayer.contents = UIImage(named: name)?.cgImage
        }
    }

    // MARK: - Actions

    func set(backgroundColor: UIColor?) {
        self.badgeBorder?.borderColor = backgroundColor?.cgColor
        self.parentBackgroundColor = backgroundColor
    }

    private func set(selected: Bool) {
        let opacity: Float = selected ? 0.5 : 1
        self.imageLayer.opacity = opacity
        self.badgeLayer.opacity = opacity
        self.stopLayer.opacity = opacity
    }

    func set(contentType: Attachment.ContentType, progress: CGFloat?, error: Error?, style: Style) {
        guard let data = self.layerData(contentType: contentType, progress: progress, error: error, style: style) else { return }

        if let border = data.border {
            switch border {
            case .borderLine:
                self.progressLayer.isHidden = true
                self.circleLayer.isHidden = false
            case .progressLine(let progress):
                self.progressLayer.strokeEnd = progress
                self.progressLayer.isHidden = false
                self.circleLayer.isHidden = false
            }
        } else {
            self.progressLayer.isHidden = true
            self.circleLayer.isHidden = true
        }

        switch data.content {
        case .stopSign:
            self.stopLayer.isHidden = false
            self.imageLayer.isHidden = true
            self.mainImageName = nil

        case .image(let name):
            let image = UIImage(named: name)
            let size = image?.size ?? CGSize()

            self.stopLayer.isHidden = true
            self.imageLayer.isHidden = false
            self.imageLayer.contents = image?.cgImage
            self.mainImageName = name

            if size.width != self.imageLayer.frame.width || size.height != self.imageLayer.frame.height {
                self.imageLayer.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
                self.setNeedsLayout()
            }
        }

        self.badgeLayer.isHidden = data.badgeName == nil
        self.badgeBorder.isHidden = data.badgeName == nil
        self.badgeImageName = data.badgeName
        if let name = data.badgeName {
            self.badgeLayer.contents = UIImage(named: name)?.cgImage
        }
    }

    private func layerData(contentType: Attachment.ContentType, progress: CGFloat?, error: Error?, style: Style) -> LayerData? {
        if let progress = progress {
            return LayerData(border: .progressLine(progress), content: .stopSign, badgeName: nil)
        }
        switch style {
        case .list:
            let image = self.listImage(for: contentType, error: error)
            return LayerData(border: .borderLine, content: .image(image), badgeName: nil)
        case .detail:
            let (image, badge) = self.detailImageData(for: contentType, error: error)
            return LayerData(border: nil, content: .image(image), badgeName: badge)
        }
    }

    private func listImage(for contentType: Attachment.ContentType, error: Error?) -> String {
        switch contentType {
        case .file(let file, _, let location, _):
            let documentType = file.mimeType == "application/pdf" ? "pdf" : "document"
            var state = self.attachmentState(from: location, error: error)
            if !state.isEmpty {
                state = "-" + state
            }
            return "attachment-list-" + documentType + state

        case .snapshot, .url:
            // These two are not shown in item list, but just in case return missing document
            return "attachment-list-document-missing"
        }
    }

    private func detailImageData(for contentType: Attachment.ContentType, error: Error?) -> (image: String, badge: String?) {
        switch contentType {
        case .file(let file, _, let location, let linkType):
            let documentType = file.mimeType == "application/pdf" ? "pdf" : "document"
            let link = linkType == .linked ? "-linked" : ""
            let badge = self.detailBadge(from: location, error: error)
            return (("attachment-detail" + link + "-" + documentType), badge)
        case .snapshot(_, _, _, let location):
            let badge = self.detailBadge(from: location, error: error)
            return ("attachment-detail-webpage-snapshot", badge)
        case .url:
            return ("attachment-detail-linked-url", nil)
        }
    }

    private func attachmentState(from location: Attachment.FileLocation?, error: Error?) -> String {
        guard error == nil else {
            return "download-failed"
        }
        guard let location = location else {
            return "missing"
        }
        switch location {
        case .local:
            return ""
        case .remote:
            return "download"
        }
    }

    private func detailBadge(from location: Attachment.FileLocation?, error: Error?) -> String? {
        let state = self.attachmentState(from: location, error: error)
        if state.isEmpty {
            return nil
        }
        return "attachment-detail-" + state
    }

    // MARK: - Setup

    private func setup() {
        self.backgroundColor = .clear
        self.translatesAutoresizingMaskIntoConstraints = false

        let circleLayer = self.createCircleLayer()
        self.layer.addSublayer(circleLayer)
        self.circleLayer = circleLayer

        let progressLayer = self.createProgressLayer()
        self.layer.addSublayer(progressLayer)
        self.progressLayer = progressLayer

        let stopLayer = self.createStopLayer()
        self.layer.addSublayer(stopLayer)
        self.stopLayer = stopLayer

        let imageLayer = self.createImageLayer()
        self.layer.addSublayer(imageLayer)
        self.imageLayer = imageLayer
        
        let badgeLayer = self.createBadgeLayer()
        self.layer.addSublayer(badgeLayer)
        self.badgeLayer = badgeLayer
        
        let badgeBorder = self.createBadgeBorderLayer()
        self.layer.addSublayer(badgeBorder)
        self.badgeBorder = badgeBorder

        let button = UIButton()
        button.frame = self.bounds
        button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.addSubview(button)
        self.button = button

        button.rx
              .controlEvent(.touchDown)
              .subscribe(onNext: { [weak self] _ in
                  self?.set(selected: true)
              })
              .disposed(by: self.disposeBag)

        button.rx
              .controlEvent([.touchUpOutside, .touchUpInside, .touchCancel])
              .subscribe(onNext: { [weak self] _ in
                  self?.set(selected: false)
              })
              .disposed(by: self.disposeBag)

        button.rx
              .controlEvent(.touchUpInside)
              .subscribe(onNext: { [weak self] _ in
                  self?.tapAction?()
              })
              .disposed(by: self.disposeBag)
    }

    private func createImageLayer() -> CALayer {
        let layer = CALayer()
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.contentsGravity = .resizeAspect
        layer.actions = ["contents": NSNull()]
        layer.shouldRasterize = true
        layer.rasterizationScale = UIScreen.main.scale
        return layer
    }
    
    private func createBadgeLayer()  -> CALayer {
        let layer = CALayer()
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.frame = CGRect(x: 0, y: 0, width: FileAttachmentView.badgeSize, height: FileAttachmentView.badgeSize)
        layer.contentsGravity = .resizeAspect
        layer.shouldRasterize = true
        layer.rasterizationScale = UIScreen.main.scale
        return layer
    }
    
    private func createBadgeBorderLayer() -> CALayer {
        let size = FileAttachmentView.badgeSize + (FileAttachmentView.badgeBorderWidth * 2)
        
        let layer = CALayer()
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        layer.borderWidth = FileAttachmentView.badgeBorderWidth
        layer.cornerRadius = size / 2
        layer.masksToBounds = true
        // Disable color animation
        layer.actions = ["borderColor": NSNull()]
        layer.shouldRasterize = true
        layer.rasterizationScale = UIScreen.main.scale
        return layer
    }

    private func createCircleLayer() -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.lineWidth = 1.5
        layer.strokeColor = UIColor.systemGray5.cgColor
        layer.shouldRasterize = true
        layer.rasterizationScale = UIScreen.main.scale
        return layer
    }

    private func createProgressLayer() -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.lineWidth = 1.5
        layer.strokeColor = Asset.Colors.zoteroBlue.color.cgColor
        layer.strokeStart = 0
        layer.strokeEnd = 0
        return layer
    }

    private func createStopLayer() -> CALayer {
        let layer = CALayer()
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.frame = CGRect(x: 0, y: 0, width: 8, height: 8)
        layer.cornerRadius = 2
        layer.masksToBounds = true
        layer.backgroundColor = Asset.Colors.zoteroBlue.color.cgColor
        layer.shouldRasterize = true
        layer.rasterizationScale = UIScreen.main.scale
        return layer
    }
}
