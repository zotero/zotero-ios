//
//  ImagePreviewViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 12/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

final class ImagePreviewViewController: UIViewController {
    @IBOutlet private weak var imageView: UIImageView!
    @IBOutlet private weak var scrollView: UIScrollView!

    private let image: UIImage
    private let disposeBag: DisposeBag

    // MARK: - Lifecycle

    init(image: UIImage, title: String) {
        self.image = image
        self.disposeBag = DisposeBag()

        super.init(nibName: "ImagePreviewViewController", bundle: nil)

        self.title = title
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.setup(image: self.image)
        self.setupGestureRecognizers()
        self.setupNavigationBar()
    }

    // MARK: - Actions

    private func toggleNavbarVisibility() {
        let willHide = !(self.navigationController?.isNavigationBarHidden ?? false)

        if !willHide {
            self.navigationController?.navigationBar.alpha = 0
            self.navigationController?.setNavigationBarHidden(false, animated: false)
        }

        UIView.animate(withDuration: 0.2, animations: {
            self.navigationController?.navigationBar.alpha = willHide ? 0 : 1
            if self.traitCollection.userInterfaceStyle == .light {
                self.view.backgroundColor = willHide ? .black : .white
            }
        }, completion: { finished in
            guard finished else { return }
            if willHide {
                self.navigationController?.setNavigationBarHidden(willHide, animated: false)
            }
        })
    }

    private func toggleZoom(sender: UITapGestureRecognizer) {
        if self.scrollView.zoomScale == self.scrollView.minimumZoomScale {
            let zoomRect = self.zoomRectangle(scale: 4, center: sender.location(in: sender.view))
            self.scrollView.zoom(to: zoomRect, animated: true)
        } else {
            self.scrollView.setZoomScale(self.scrollView.minimumZoomScale, animated: true)
        }
    }

    private func zoomRectangle(scale: CGFloat, center: CGPoint) -> CGRect {
        var rect = CGRect()
        rect.size.height = self.imageView.frame.height / scale
        rect.size.width  = self.imageView.frame.width / scale
        rect.origin.x = center.x - (rect.width / 2)
        rect.origin.y = center.y - (rect.height / 2)
        return rect
    }

    // MARK: - Setups

    private func setup(image: UIImage) {
        if image.imageData != nil {
            self.imageView.setGifImage(image)
        } else {
            self.imageView.image = image
        }
    }

    private func setupGestureRecognizers() {
        let tap = UITapGestureRecognizer()
        tap.numberOfTapsRequired = 1
        tap.rx
           .event
           .observe(on: MainScheduler.instance)
           .subscribe(onNext: { [weak self] _ in
               self?.toggleNavbarVisibility()
           })
           .disposed(by: self.disposeBag)
        self.view.addGestureRecognizer(tap)

        let doubleTap = UITapGestureRecognizer()
        doubleTap.numberOfTapsRequired = 2
        doubleTap.rx
                 .event
                 .observe(on: MainScheduler.instance)
                 .subscribe(onNext: { [weak self] sender in
                     self?.toggleZoom(sender: sender)
                 })
                 .disposed(by: self.disposeBag)
        self.view.addGestureRecognizer(doubleTap)

        tap.require(toFail: doubleTap)
    }

    private func setupNavigationBar() {
        let closeItem = UIBarButtonItem(title: L10n.close)
        closeItem.tintColor = Asset.Colors.zoteroBlue.color
        closeItem.rx
                 .tap
                 .observe(on: MainScheduler.instance)
                 .subscribe(onNext: { [weak self] in
                     self?.navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
                 })
                 .disposed(by: self.disposeBag)
        self.navigationItem.rightBarButtonItem = closeItem
    }
}

extension ImagePreviewViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return self.imageView
    }
}
