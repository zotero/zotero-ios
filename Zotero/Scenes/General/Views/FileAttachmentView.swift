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
    private let disposeBag: DisposeBag

    private var circleLayer: CAShapeLayer!
    private var progressLayer: CAShapeLayer!
    private var stopLayer: CALayer!
    private var imageLayer: CALayer!
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
        return CGSize(width: (FileAttachmentView.size + self.contentInsets.left + self.contentInsets.right + (self.circleLayer.lineWidth * 2)),
                      height: (FileAttachmentView.size + self.contentInsets.top + self.contentInsets.bottom + (self.circleLayer.lineWidth * 2)))
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let x = self.contentInsets.left + ((self.bounds.width - self.contentInsets.left - self.contentInsets.right) / 2)
        let y = self.contentInsets.top + ((self.bounds.height - self.contentInsets.top - self.contentInsets.bottom) / 2)
        let center = CGPoint(x: x, y: y)
        let path = UIBezierPath(arcCenter: center, radius: (FileAttachmentView.size / 2), startAngle: -.pi / 2,
                                endAngle: 3 * .pi / 2, clockwise: true).cgPath

        self.circleLayer.path = path
        self.progressLayer.path = path
        self.stopLayer.position = center
        self.imageLayer.position = center
    }

    // MARK: - Actions

    private func set(selected: Bool) {
        self.layer.opacity = selected ? 0.5 : 1
    }

    func set(contentType: Attachment.ContentType, progress: CGFloat?, error: Error?) {
        guard let (file, _, location) = contentType.fileData else { return }

        var imageName: String
        var inProgress = false
        var borderVisible = true
        var strokeEnd: CGFloat = 0

        switch file.ext {
        case "pdf":
            imageName = "pdf-attachment"
        default:
            imageName = "document-attachment"
        }

        if let progress = progress {
            inProgress = true
            strokeEnd = progress
        } else if error != nil {
            imageName += "-download-failed"
        } else if let location = location {
            switch location {
            case .local:
                strokeEnd = 1
            case .remote:
                imageName += "-download"
            }
        } else {
            imageName += "-missing"
            borderVisible = false
        }

        self.stopLayer.isHidden = !inProgress
        self.imageLayer.isHidden = inProgress
        self.circleLayer.isHidden = !borderVisible
        self.progressLayer.isHidden = !borderVisible
        self.progressLayer.strokeEnd = strokeEnd

        if !inProgress, let image = UIImage(named: imageName) {
            self.imageLayer.contents = image.cgImage
        }
    }

    // MARK: - Setup

    private func setup() {
        self.translatesAutoresizingMaskIntoConstraints = false
        self.layer.masksToBounds = true
        self.layer.backgroundColor = UIColor.clear.cgColor
        self.backgroundColor = .clear

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
