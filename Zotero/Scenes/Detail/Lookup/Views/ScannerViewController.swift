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

final class ScannerViewController: UIViewController {
    private let viewModel: ViewModel<ScannerActionHandler>
    private let sessionQueue: DispatchQueue

    @IBOutlet private weak var barcodeContainer: UIView!
    @IBOutlet private weak var barcodeStackContainer: UIStackView!
    @IBOutlet private weak var barcodeTitleLabel: UILabel!

    private weak var lookupController: LookupViewController?
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    weak var coordinatorDelegate: LookupCoordinatorDelegate?

    init(viewModel: ViewModel<ScannerActionHandler>) {
        self.viewModel = viewModel
        self.sessionQueue = DispatchQueue(label: "org.zotero.ScannerViewController.sessionQueue", qos: .userInitiated)
        super.init(nibName: "ScannerViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.preferredContentSize = CGSize(width: 500, height: 500)
        self.navigationController?.preferredContentSize = self.preferredContentSize
        self.view.backgroundColor = UIColor.black

        self.setupLookupController()
        self.setupSession()
        self.barcodeContainer.layer.zPosition = 2
        self.setupNavigationItems()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        self.previewLayer?.frame = self.view.layer.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.sessionQueue.async { [weak self] in
            if self?.captureSession?.isRunning == false {
                self?.captureSession?.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        self.sessionQueue.async { [weak self] in
            if self?.captureSession?.isRunning == true {
                self?.captureSession?.stopRunning()
            }
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        self.updatePreviewOrientation()
    }

    deinit {
        DDLogInfo("ScannerViewController: deinitialized")
    }

    // MARK: - Actions

    private func updatePreviewOrientation() {
        guard let scene = UIApplication.shared.connectedScenes.first, let windowScene = scene as? UIWindowScene else { return }
        self.setPreview(orientation: windowScene.interfaceOrientation)
    }

    private func setPreview(orientation: UIInterfaceOrientation) {
        switch orientation {
        case .portrait:
            self.previewLayer?.connection?.videoOrientation = .portrait

        case .portraitUpsideDown:
            self.previewLayer?.connection?.videoOrientation = .portraitUpsideDown

        case .landscapeLeft:
            self.previewLayer?.connection?.videoOrientation = .landscapeLeft

        case .landscapeRight:
            self.previewLayer?.connection?.videoOrientation = .landscapeRight
        case .unknown: break
        @unknown default: break
        }
    }

    // MARK: - Setups

    private func setupLookupController() {
        guard let controller = self.coordinatorDelegate?.lookupController(restoreLookupState: true, hasDarkBackground: true) else { return }
        controller.view.backgroundColor = .clear
        controller.view.isHidden = true
        self.lookupController = controller

        controller.willMove(toParent: self)
        self.addChild(controller)
        self.barcodeStackContainer.addArrangedSubview(controller.view)
        controller.didMove(toParent: self)
    }

    private func setupNavigationItems() {
        let primaryAction = UIAction(title: L10n.close) { [weak self] _ in
            self?.navigationController?.presentingViewController?.dismiss(animated: true)
        }
        let cancelItem: UIBarButtonItem
        if #available(iOS 26.0.0, *) {
            cancelItem = UIBarButtonItem(systemItem: .close, primaryAction: primaryAction)
        } else {
            cancelItem = UIBarButtonItem(primaryAction: primaryAction)
        }
        navigationItem.leftBarButtonItem = cancelItem
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
        previewLayer.zPosition = 1
        self.view.layer.addSublayer(previewLayer)

        self.captureSession = captureSession
        self.previewLayer = previewLayer

        self.updatePreviewOrientation()
    }
}

extension ScannerViewController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        let scanned = metadataObjects.compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }
        let filtered = scanned.filter({ !self.viewModel.state.barcodes.contains($0) })

        guard !filtered.isEmpty else { return }

        self.viewModel.process(action: .setBarcodes(filtered))

        let isbns = filtered.flatMap({ ISBNParser.isbns(from: $0) })
        guard !isbns.isEmpty else { return }

        self.lookupController?.viewModel.process(action: .lookUp(isbns.joined(separator: ", ")))
        self.lookupController?.view.isHidden = false
    }
}

extension ScannerViewController: IdentifierLookupPresenter {
    func isPresenting() -> Bool {
        lookupController?.view.isHidden == false
    }
}
