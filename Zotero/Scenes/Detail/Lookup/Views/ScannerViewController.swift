//
//  ScannerViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 16.06.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import AVFoundation
import UIKit

import CocoaLumberjackSwift
import RxSwift

final class ScannerViewController: UIViewController {
    private let viewModel: ViewModel<ScannerActionHandler>
    private let disposeBag: DisposeBag

    @IBOutlet private weak var codeLabel: UILabel!

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    weak var coordinatorDelegate: ScannerToLookupCoordinatorDelegate?

    init(viewModel: ViewModel<ScannerActionHandler>) {
        self.viewModel = viewModel
        self.disposeBag = DisposeBag()
        super.init(nibName: "ScannerViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.preferredContentSize = CGSize(width: 500, height: 300)
        self.navigationController?.preferredContentSize = self.preferredContentSize
        self.view.backgroundColor = UIColor.black
        self.setupSession()
        self.setupNavigationItems()

        self.viewModel.stateObservable
                      .subscribe(with: self, onNext: { `self`, state in
                          self.update(state: state)
                      })
                      .disposed(by: self.disposeBag)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        self.previewLayer?.frame = self.view.layer.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if (self.captureSession?.isRunning == false) {
            self.captureSession?.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if (self.captureSession?.isRunning == true) {
            self.captureSession?.stopRunning()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        self.setPreview(orientation: UIDevice.current.orientation)
    }

    // MARK: - Actions

    private func update(state: ScannerState) {
        let codes = state.codes.joined(separator: ", ")
        self.codeLabel.text = codes
        self.navigationItem.rightBarButtonItem?.isEnabled = !codes.isEmpty
    }

    private func setPreview(orientation: UIDeviceOrientation) {
        switch orientation {
        case .portrait:
            self.previewLayer?.connection?.videoOrientation = .portrait
        case .portraitUpsideDown:
            self.previewLayer?.connection?.videoOrientation = .portraitUpsideDown
        case .landscapeLeft:
            self.previewLayer?.connection?.videoOrientation = .landscapeRight
        case .landscapeRight:
            self.previewLayer?.connection?.videoOrientation = .landscapeLeft
        case .faceUp, .faceDown, .unknown: break
        @unknown default: break
        }
    }

    // MARK: - Setups

    private func setupNavigationItems() {
        let doneItem = UIBarButtonItem(title: L10n.lookUp, style: .done, target: nil, action: nil)
        doneItem.rx.tap.subscribe(with: self, onNext: { `self`, _ in
            self.coordinatorDelegate?.showLookup(with: self.viewModel.state.codes)
        }).disposed(by: self.disposeBag)
        self.navigationItem.rightBarButtonItem = doneItem

        let cancelItem = UIBarButtonItem(title: L10n.cancel, style: .plain, target: nil, action: nil)
        cancelItem.rx.tap.subscribe(onNext: { [weak self] in
            self?.navigationController?.presentingViewController?.dismiss(animated: true)
        }).disposed(by: self.disposeBag)
        self.navigationItem.leftBarButtonItem = cancelItem
    }

    private func setupSession() {
        let captureSession = AVCaptureSession()

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }

        let videoInput: AVCaptureDeviceInput

        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch let error {
            DDLogError("ScannerViewController: can't create device input - \(error)")
            return
        }

        guard captureSession.canAddInput(videoInput) else {
            DDLogError("ScannerViewController: capture session can't add video input")
            return
        }

        captureSession.addInput(videoInput)

        let metadataOutput = AVCaptureMetadataOutput()

        guard captureSession.canAddOutput(metadataOutput) else {
            DDLogError("ScannerViewController: capture session can't output metadata")
            return
        }

        captureSession.addOutput(metadataOutput)

        metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
        metadataOutput.metadataObjectTypes = [.ean8, .ean13]

        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = self.view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.connection?.videoOrientation = .landscapeLeft
        self.view.layer.addSublayer(previewLayer)

        self.captureSession = captureSession
        self.previewLayer = previewLayer

        self.setPreview(orientation: UIDevice.current.orientation)
    }
}

extension ScannerViewController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        let scanned = metadataObjects.compactMap { object -> String? in
            guard let readableObject = object as? AVMetadataMachineReadableCodeObject, let string = readableObject.stringValue else { return nil }
            return string
        }
        self.viewModel.process(action: .save(scanned))
    }
}
