//
//  FileAttachmentView.swift
//  Zotero
//
//  Created by Michal Rentka on 10/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import RxSwift

final class FileAttachmentView: UIView {
    enum Style {
        case list
        case detail
        case shareExtension
        case lookup
    }

    enum State {
        case ready(Attachment.Kind)
        case progress(CGFloat)
        case failed(Attachment.Kind, Error)

        static func stateFrom(type: Attachment.Kind, progress: CGFloat?, error: Error?) -> State {
            if let progress = progress {
                return .progress(progress)
            }
            if let error = error {
                return .failed(type, error)
            }
            return .ready(type)
        }
    }

    private enum ContentType {
        case progress(CGFloat)
        case image(asset: ImageAsset)
        case imageWithBadge(main: ImageAsset, badge: ImageAsset)
    }

    private enum BadgeType {
        case failed, missing, download
    }
    
    private static let size: CGFloat = 28
    private static let badgeDetailBorderWidth: CGFloat = 1.5
    private static let badgeListBorderWidth: CGFloat = 1
    private static let progressCircleWidth: CGFloat = 1.5
    private static let sfSymbolSize: CGFloat = 16
    private let disposeBag: DisposeBag

    private var circleLayer: CAShapeLayer!
    private var progressLayer: CAShapeLayer!
    private var stopLayer: CALayer!
    private var imageLayer: CALayer!
    private var badgeLayer: CALayer!
    private var badgeBorder: CALayer!
//    private weak var button: UIButton!
    private var contentType: ContentType?
    private var style: Style = .detail
    private var parentBackgroundColor: UIColor?

    var contentInsets: UIEdgeInsets = UIEdgeInsets() {
        didSet {
            self.invalidateIntrinsicContentSize()
        }
    }
//    var tapEnabled: Bool {
//        get {
//            return self.button.isEnabled
//        }
//
//        set {
//            self.button.isEnabled = newValue
//        }
//    }
//    var tapAction: (() -> Void)?

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
        self.badgeLayer.position = CGPoint(x: (x + (self.imageLayer.frame.width / 2.0)) - 0.5,
                                           y: (y + (self.imageLayer.frame.height / 2.0)) - 0.5)
        self.badgeBorder.position = self.badgeLayer.position
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        guard self.traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }

        self.circleLayer.strokeColor = UIColor.systemGray5.cgColor
        self.badgeBorder.borderColor = self.parentBackgroundColor?.cgColor

        if let type = self.contentType {
            self.set(contentType: type, style: self.style)
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

    func set(state: State, style: Style) {
        guard let type = self.contentType(state: state, style: style) else { return }
        self.set(contentType: type, style: style)
    }

    private func set(contentType: ContentType, style: Style) {
        self.contentType = contentType
        self.style = style

        switch contentType {
        case .progress(let progress):
            self.set(progress: progress, showsStop: (style != .lookup))
            self.setMainImage(asset: nil)
            self.setBadge(asset: nil, style: style)

        case .image(let asset):
            self.set(progress: nil, showsStop: false)
            self.setMainImage(asset: asset)
            self.setBadge(asset: nil, style: style)

        case .imageWithBadge(let mainAsset, let badgeAsset):
            self.set(progress: nil, showsStop: false)
            self.setMainImage(asset: mainAsset)
            self.setBadge(asset: badgeAsset, style: style)
        }
    }

    private func set(progress: CGFloat?, showsStop: Bool) {
        if showsStop {
            self.stopLayer.isHidden = progress == nil
        } else {
            self.stopLayer.isHidden = true
        }
        self.progressLayer.isHidden = progress == nil
        self.circleLayer.isHidden = progress == nil
        if let progress = progress {
            self.progressLayer.strokeEnd = progress
        }
    }

    private func setMainImage(asset: ImageAsset?) {
        let image = asset?.image
        self.imageLayer.isHidden = asset == nil
        self.imageLayer.contents = image?.cgImage
        self.imageLayer.mask = nil
        self.imageLayer.backgroundColor = UIColor.clear.cgColor

        if let image = image, self.imageLayer.frame.width != image.size.width || self.imageLayer.frame.height != image.size.height {
            self.imageLayer.frame = CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
            self.setNeedsLayout()
        }
    }

    private func setBadge(asset: ImageAsset?, style: Style) {
        let image = asset?.image
        self.badgeLayer.isHidden = asset == nil
        self.badgeBorder.isHidden = asset == nil
        self.badgeLayer.contents = image?.cgImage

        if let image = image {
            let borderWidth = self.badgeBorderWidth(for: style)
            let badgeBorderSize = image.size.width + (borderWidth * 2)

            self.badgeBorder.frame = CGRect(x: 0, y: 0, width: badgeBorderSize, height: badgeBorderSize)
            self.badgeBorder.borderWidth = borderWidth
            self.badgeBorder.cornerRadius = badgeBorderSize / 2
            self.badgeLayer.frame = CGRect(origin: CGPoint(), size: image.size)

            self.setNeedsLayout()
        }
    }

    private func badgeBorderWidth(for style: Style) -> CGFloat {
        switch style {
        case .detail, .shareExtension, .lookup: return FileAttachmentView.badgeDetailBorderWidth
        case .list: return FileAttachmentView.badgeListBorderWidth
        }
    }

    private func contentType(state: State, style: Style) -> ContentType? {
        switch state {
        case .progress(let progress):
            return .progress(progress)

        case .ready(let type):
            switch type {
            case .file(_, _, let location, _):
                switch location {
                case .local: return .image(asset: self.mainAsset(for: type, style: style))
                case .remoteMissing: return .imageWithBadge(main: self.mainAsset(for: type, style: style), badge: self.badge(for: .missing, style: style))
                case .remote, .localAndChangedRemotely: return .imageWithBadge(main: self.mainAsset(for: type, style: style), badge: self.badge(for: .download, style: style))
                }

            case .url: return .image(asset: self.mainAsset(for: type, style: style))
            }

        case .failed(let type, _): return .imageWithBadge(main: self.mainAsset(for: type, style: style), badge: self.badge(for: .failed, style: style))
        }
    }

    private func badge(for type: BadgeType, style: Style) -> ImageAsset {
        switch type {
        case .download:
            switch style {
            case .detail, .shareExtension, .lookup: return Asset.Images.Attachments.badgeDetailDownload
            case .list: return Asset.Images.Attachments.badgeListDownload
            }

        case .failed:
            switch style {
            case .detail, .lookup: return Asset.Images.Attachments.badgeDetailFailed
            case .shareExtension: return Asset.Images.Attachments.badgeShareextFailed
            case .list: return Asset.Images.Attachments.badgeListFailed
            }

        case .missing:
            switch style {
            case .detail, .shareExtension, .lookup: return Asset.Images.Attachments.badgeDetailMissing
            case .list: return Asset.Images.Attachments.badgeListMissing
            }
        }
    }

    private func mainAsset(for attachmentType: Attachment.Kind, style: Style) -> ImageAsset {
        switch attachmentType {
        case .url:
            switch style {
            case .detail, .shareExtension, .lookup: return Asset.Images.Attachments.detailLinkedUrl
            case .list: return Asset.Images.Attachments.listLink
            }

        case .file(_, let contentType, _, let linkType):
            switch linkType {
            case .embeddedImage:
                switch style {
                case .detail, .shareExtension, .lookup: return Asset.Images.Attachments.detailImage
                case .list: return Asset.Images.Attachments.listImage
                }

            case .linkedFile:
                switch style {
                case .detail, .shareExtension, .lookup:
                    switch contentType {
                    case "application/pdf": return Asset.Images.Attachments.detailLinkedPdf
                    default: return Asset.Images.Attachments.detailLinkedDocument
                    }

                case .list:
                    return Asset.Images.Attachments.listLink
                }
            case .importedUrl where contentType == "text/html":
                switch style {
                case .list: return Asset.Images.Attachments.listWebPageSnapshot
                case .detail, .shareExtension, .lookup: return Asset.Images.Attachments.detailWebpageSnapshot
                }

            case .importedFile, .importedUrl:
                switch contentType {
                case "image/png", "image/jpeg", "image/gif":
                    switch style {
                    case .detail, .shareExtension, .lookup: return Asset.Images.Attachments.detailImage
                    case .list: return Asset.Images.Attachments.listImage
                    }
                case "application/pdf":
                    switch style {
                    case .detail, .shareExtension, .lookup: return Asset.Images.Attachments.detailPdf
                    case .list: return Asset.Images.Attachments.listPdf
                    }

                default:
                    switch style {
                    case .detail, .shareExtension, .lookup: return Asset.Images.Attachments.detailDocument
                    case .list: return Asset.Images.Attachments.listDocument
                    }
                }
            }
        }
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

//        let button = UIButton()
//        button.frame = self.bounds
//        button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
//        self.addSubview(button)
//        self.button = button
//
//        button.rx
//              .controlEvent(.touchDown)
//              .subscribe(onNext: { [weak self] _ in
//                  self?.set(selected: true)
//              })
//              .disposed(by: self.disposeBag)
//
//        button.rx
//              .controlEvent([.touchUpOutside, .touchUpInside, .touchCancel])
//              .subscribe(onNext: { [weak self] _ in
//                  self?.set(selected: false)
//              })
//              .disposed(by: self.disposeBag)
//
//        button.rx
//              .controlEvent(.touchUpInside)
//              .subscribe(onNext: { [weak self] _ in
//                  self?.tapAction?()
//              })
//              .disposed(by: self.disposeBag)
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
    
    private func createBadgeLayer() -> CALayer {
        let layer = CALayer()
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.contentsGravity = .resizeAspect
        layer.shouldRasterize = true
        layer.rasterizationScale = UIScreen.main.scale
        return layer
    }
    
    private func createBadgeBorderLayer() -> CALayer {
        let layer = CALayer()
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
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
        layer.actions = ["strokeEnd": NSNull()]
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
