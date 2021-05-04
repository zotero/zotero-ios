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

fileprivate enum LayerData {
    case progress(CGFloat)
    case image(asset: ImageAsset, opacity: Float)
    case sfSymbol(name: String, color: UIColor)
    case imageWithBadge(main: ImageAsset, badge: ImageAsset)
}

final class FileAttachmentView: UIView {
    enum Style {
        case list
        case detail
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
    
    private static let size: CGFloat = 28
    private static let badgeBorderWidth: CGFloat = 1.5
    private static let badgeSize: CGFloat = 11
    private static let progressCircleWidth: CGFloat = 1.5
    private static let sfSymbolSize: CGFloat = 16
    private let disposeBag: DisposeBag

    private var circleLayer: CAShapeLayer!
    private var progressLayer: CAShapeLayer!
    private var stopLayer: CALayer!
    private var imageLayer: CALayer!
    private var badgeLayer: CALayer!
    private var badgeBorder: CALayer!
    private weak var button: UIButton!
    private var layerData: LayerData?
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

        if let data = self.layerData {
            self.set(layerData: data)
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

    func showFailure() {

    }

    func set(state: State, style: Style) {
        guard let data = self.layerData(state: state, style: style) else { return }
        self.set(layerData: data)
    }

    private func set(layerData: LayerData) {
        self.layerData = layerData

        switch layerData {
        case .progress(let progress):
            self.set(progress: progress)
            self.setMainImage(data: nil)
            self.setBadge(asset: nil)

        case .image(let asset, let opacity):
            self.set(progress: nil)
            self.setMainImage(data: (asset, opacity))
            self.imageLayer.opacity = opacity
            self.setBadge(asset: nil)

        case .sfSymbol(let name, let color):
            self.set(progress: nil)
            self.setMainSymbol(name: name, color: color)
            self.setBadge(asset: nil)

        case .imageWithBadge(let mainAsset, let badgeAsset):
            self.set(progress: nil)
            self.setMainImage(data: (mainAsset, 1))
            self.setBadge(asset: badgeAsset)
        }
    }

    private func set(progress: CGFloat?) {
        self.stopLayer.isHidden = progress == nil
        self.progressLayer.isHidden = progress == nil
        self.circleLayer.isHidden = progress == nil
        if let progress = progress {
            self.progressLayer.strokeEnd = progress
        }
    }

    private func setMainImage(data: (asset: ImageAsset, opacity: Float)?) {
        let image = data?.asset.image
        self.imageLayer.isHidden = data == nil
        self.imageLayer.contents = image?.cgImage
        self.imageLayer.mask = nil
        self.imageLayer.backgroundColor = UIColor.clear.cgColor
        if let opacity = data?.opacity {
            self.imageLayer.opacity = opacity
        }

        if let image = image, self.imageLayer.frame.width != image.size.width || self.imageLayer.frame.height != image.size.height {
            self.imageLayer.frame = CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
            self.setNeedsLayout()
        }
    }

    private func setMainSymbol(name: String, color: UIColor) {
        let mask = CALayer()
        mask.frame = CGRect(x: 0, y: 0, width: FileAttachmentView.sfSymbolSize, height: FileAttachmentView.sfSymbolSize)
        mask.contents = UIImage(systemName: name)?.cgImage
        self.imageLayer.isHidden = false
        self.imageLayer.mask = mask
        self.imageLayer.contents = nil
        self.imageLayer.backgroundColor = color.cgColor
        self.imageLayer.opacity = 1

        if self.imageLayer.frame.width != mask.frame.width || self.imageLayer.frame.height != mask.frame.height {
            self.imageLayer.frame = mask.frame
            self.setNeedsLayout()
        }
    }

    private func setBadge(asset: ImageAsset?) {
        self.badgeLayer.isHidden = asset == nil
        self.badgeBorder.isHidden = asset == nil
        self.badgeLayer.contents = asset?.image.cgImage
    }

    private func layerData(state: State, style: Style) -> LayerData? {
        switch state {
        case .progress(let progress):
            return .progress(progress)

        case .ready(let type):
            switch style {
            case .list:
                switch type {
                case .file(_, _, let location, _):
                    switch location {
                    case .remoteMissing: return .sfSymbol(name: "questionmark.circle.fill", color: Asset.Colors.attachmentMissing.color)
                    case .local: return .image(asset: self.mainAsset(for: type, style: style), opacity: 1)
                    case .remote: return .image(asset: self.mainAsset(for: type, style: style), opacity: 0.5)
                    }
                case .url: return .image(asset: self.mainAsset(for: type, style: style), opacity: 1)
                }
            case .detail:
                switch type {
                case .file(_, _, let location, _):
                    switch location {
                    case .remoteMissing: return .imageWithBadge(main: self.mainAsset(for: type, style: style), badge: Asset.Images.Attachments.badgeMissing)
                    case .local: return .image(asset: self.mainAsset(for: type, style: style), opacity: 1)
                    case .remote: return .imageWithBadge(main: self.mainAsset(for: type, style: style), badge: Asset.Images.Attachments.badgeDownload)
                    }
                case .url: return .image(asset: self.mainAsset(for: type, style: style), opacity: 1)
                }
            }
        case .failed(let type, _):
            switch style {
            case .list: return .sfSymbol(name: "exclamationmark.circle.fill", color: Asset.Colors.attachmentError.color)
            case .detail: return .imageWithBadge(main: self.mainAsset(for: type, style: style), badge: Asset.Images.Attachments.badgeFailed)
            }
        }
    }

    private func mainAsset(for attachmentType: Attachment.Kind, style: Style) -> ImageAsset {
        switch attachmentType {
        case .url:
            switch style {
            case .detail: return Asset.Images.Attachments.detailLinkedUrl
            case .list: return Asset.Images.Attachments.listLink
            }
        case .file(_, let contentType, _, let linkType):
            switch linkType {
            case .embeddedImage:
                switch style {
                case .detail: return Asset.Images.Attachments.detailImage
                case .list: return Asset.Images.Attachments.listImage
                }
            case .linkedFile:
                switch style {
                case .detail:
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
                case .detail: return Asset.Images.Attachments.detailWebpageSnapshot
                }
            case .importedFile, .importedUrl:
                switch contentType {
                case "image/png", "image/jpeg", "image/gif":
                    switch style {
                    case .detail: return Asset.Images.Attachments.detailImage
                    case .list: return Asset.Images.Attachments.listImage
                    }
                case "application/pdf":
                    switch style {
                    case .detail: return Asset.Images.Attachments.detailPdf
                    case .list: return Asset.Images.Attachments.listPdf
                    }
                default:
                    switch style {
                    case .detail: return Asset.Images.Attachments.detailDocument
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
