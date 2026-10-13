//
//  PDFLinkPreviewViewController.swift
//  Zotero
//
//  Created by Victor Puga on 09/10/2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import PSPDFKit

/// Popover showing a zoomable, scrollable preview of the page an internal link points to, scrolled to the link's destination.
final class PDFLinkPreviewViewController: UIViewController {
    private static let contentWidth: CGFloat = 640
    private static let maxContentHeight: CGFloat = 560
    /// Height of the visible page region, in PDF points.
    private static let visiblePageHeight: CGFloat = 260
    /// Part of the page above the destination that stays visible, in PDF points.
    private static let marginAboveDestination: CGFloat = 30
    /// Rendered image resolution relative to the display size, so the content stays sharp when zoomed in.
    private static let renderScale: CGFloat = 3

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let document: PSPDFKit.Document
    private let pageIndex: PageIndex
    private let offsetFromTop: CGFloat?
    private let appearance: Appearance
    private let pageSize: CGSize
    private let scale: CGFloat
    private var didSetInitialOffset = false

    /// - parameter offsetFromTop: Distance of the link destination from the top of the page in PDF points. If `nil`, the preview shows the whole page.
    init(document: PSPDFKit.Document, pageIndex: PageIndex, offsetFromTop: CGFloat?, appearance: Appearance) {
        self.document = document
        self.pageIndex = pageIndex
        self.offsetFromTop = offsetFromTop
        self.appearance = appearance
        pageSize = document.pageInfoForPage(at: pageIndex)?.size ?? CGSize(width: 612, height: 792)
        scale = Self.contentWidth / pageSize.width
        super.init(nibName: nil, bundle: nil)
        let height = offsetFromTop == nil ? pageSize.height : min(Self.visiblePageHeight, pageSize.height)
        preferredContentSize = CGSize(width: Self.contentWidth, height: min(height * scale, Self.maxContentHeight))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.delegate = self
        scrollView.minimumZoomScale = 0.5
        scrollView.maximumZoomScale = 4
        scrollView.showsHorizontalScrollIndicator = false
        view.addSubview(scrollView)

        imageView.contentMode = .scaleAspectFit
        imageView.frame = CGRect(x: 0, y: 0, width: Self.contentWidth, height: pageSize.height * scale)
        scrollView.addSubview(imageView)
        scrollView.contentSize = imageView.frame.size

        render()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !didSetInitialOffset, scrollView.bounds.height > 0 else { return }
        didSetInitialOffset = true
        guard let offsetFromTop else { return }
        let maxOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        let offset = (offsetFromTop - Self.marginAboveDestination) * scale
        scrollView.contentOffset = CGPoint(x: 0, y: min(max(0, offset), maxOffset))
    }

    private func render() {
        let options = RenderOptions()
        switch appearance {
        case .dark:
            options.invertRenderColor = true
            options.filters = [.colorCorrectInverted]

        case .sepia:
            options.filters = [.sepia]

        case .light:
            break
        }

        let request = MutableRenderRequest(document: document)
        request.pageIndex = pageIndex
        request.imageSize = CGSize(width: Self.contentWidth * Self.renderScale, height: pageSize.height * scale * Self.renderScale)
        request.options = options

        do {
            let task = try RenderTask(request: request)
            task.completionHandler = { [weak self] image, error in
                if let error {
                    DDLogError("PDFLinkPreviewViewController: can't render page \(self?.pageIndex ?? 0) - \(error)")
                }
                DispatchQueue.main.async {
                    self?.imageView.image = image
                }
            }
            PSPDFKit.SDK.shared.renderManager.renderQueue.schedule(task)
        } catch let error {
            DDLogError("PDFLinkPreviewViewController: can't create render task - \(error)")
        }
    }
}

extension PDFLinkPreviewViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
}

extension PDFLinkPreviewViewController: UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        return .none
    }
}
