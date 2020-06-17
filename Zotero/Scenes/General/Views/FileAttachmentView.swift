//
//  FileAttachmentView.swift
//  Zotero
//
//  Created by Michal Rentka on 10/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

class FileAttachmentView: UIView {
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
        self.badgeLayer.position = CGPoint(x: (self.bounds.width - self.contentInsets.right),
                                           y: (self.bounds.height - self.contentInsets.bottom))
        self.badgeBorder.position = CGPoint(x: self.badgeLayer.position.x + FileAttachmentView.badgeBorderWidth,
                                            y: self.badgeLayer.position.y + FileAttachmentView.badgeBorderWidth)
    }

    // MARK: - Actions
    
    func set(backgroundColor: UIColor?) {
        self.backgroundColor = backgroundColor
        self.badgeBorder?.borderColor = backgroundColor?.cgColor
    }

    private func set(selected: Bool) {
        let opacity: Float = selected ? 0.5 : 1
        self.imageLayer.opacity = opacity
        self.badgeLayer.opacity = opacity
        self.stopLayer.opacity = opacity
    }

    func set(contentType: Attachment.ContentType, progress: CGFloat?, error: Error?) {
        guard let (file, _, location) = contentType.fileData else { return }

        var imageName: String?
        var badgeName: String?
        var inProgress = false
        var borderVisible = true
        var strokeEnd: CGFloat = 0
        
        if let progress = progress {
            inProgress = true
            strokeEnd = progress
        } else if error != nil {
            badgeName = "attachment-failed"
        } else if let location = location {
            switch location {
            case .local:
                strokeEnd = 1
            case .remote:
                badgeName = "attachment-download"
            }
        } else {
            badgeName = "attachment-missing"
            borderVisible = false
        }

        if !inProgress {
            switch file.ext {
            case "pdf":
                imageName = "attachment-pdf"
            default:
                imageName = "attachment-document"
            }
        }

        self.stopLayer.isHidden = !inProgress
        self.imageLayer.isHidden = inProgress
        self.badgeLayer.isHidden = inProgress
        self.circleLayer.isHidden = !borderVisible
        self.progressLayer.isHidden = !borderVisible
        self.progressLayer.strokeEnd = strokeEnd
        self.imageLayer.contents = imageName.flatMap({ UIImage(named: $0) })?.cgImage
        self.badgeLayer.contents = badgeName.flatMap({ UIImage(named: $0) })?.cgImage
    }

    // MARK: - Setup

    private func setup() {
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
        layer.frame = CGRect(x: 0, y: 0, width: 24, height: 24)
        layer.contentsGravity = .resizeAspect
        return layer
    }
    
    private func createBadgeLayer()  -> CALayer {
        let layer = CALayer()
        layer.anchorPoint = CGPoint(x: 1, y: 1)
        layer.frame = CGRect(x: 0, y: 0, width: FileAttachmentView.badgeSize, height: FileAttachmentView.badgeSize)
        layer.contentsGravity = .resizeAspect
        return layer
    }
    
    private func createBadgeBorderLayer() -> CALayer {
        let size = FileAttachmentView.badgeSize + (FileAttachmentView.badgeBorderWidth * 2)
        
        let layer = CALayer()
        layer.anchorPoint = CGPoint(x: 1, y: 1)
        layer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        layer.borderWidth = FileAttachmentView.badgeBorderWidth
        layer.cornerRadius = size / 2
        layer.masksToBounds = true
        layer.borderColor = self.backgroundColor?.cgColor
        // Disable color animation
        layer.actions = ["borderColor": NSNull()]
        return layer
    }

    private func createCircleLayer() -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.lineWidth = 1.5
        layer.strokeColor = UIColor.systemGray5.cgColor
        return layer
    }

    private func createProgressLayer() -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.lineWidth = 1.5
        layer.strokeColor = UIColor.systemBlue.cgColor
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
        layer.backgroundColor = UIColor.systemBlue.cgColor
        return layer
    }
}
