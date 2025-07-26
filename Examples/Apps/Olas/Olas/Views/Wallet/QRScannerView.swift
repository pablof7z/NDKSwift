import SwiftUI
import AVFoundation

struct QRScannerView: UIViewControllerRepresentable {
    let completion: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.completion = { result in
            completion(result)
            dismiss()
        }
        return controller
    }
    
    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var completion: ((String) -> Void)?
    
    private let scannerOverlay = UIView()
    private let cornerLength: CGFloat = 30
    private let cornerWidth: CGFloat = 4
    private let scanAreaSize: CGFloat = 280
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor.black
        
        // Setup camera
        setupCamera()
        
        // Add overlay
        setupOverlay()
        
        // Add close button
        setupCloseButton()
        
        // Add instructions
        setupInstructions()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if captureSession?.isRunning == false {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.startRunning()
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if captureSession?.isRunning == true {
            captureSession.stopRunning()
        }
    }
    
    private func setupCamera() {
        captureSession = AVCaptureSession()
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            showError("No camera available")
            return
        }
        
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            showError("Camera input error")
            return
        }
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            showError("Could not add video input")
            return
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            showError("Could not add metadata output")
            return
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }
    
    private func setupOverlay() {
        // Semi-transparent overlay
        let overlayPath = UIBezierPath(rect: view.bounds)
        let scanPath = UIBezierPath(roundedRect: CGRect(
            x: (view.bounds.width - scanAreaSize) / 2,
            y: (view.bounds.height - scanAreaSize) / 2,
            width: scanAreaSize,
            height: scanAreaSize
        ), cornerRadius: 20)
        overlayPath.append(scanPath)
        overlayPath.usesEvenOddFillRule = true
        
        let fillLayer = CAShapeLayer()
        fillLayer.path = overlayPath.cgPath
        fillLayer.fillRule = .evenOdd
        fillLayer.fillColor = UIColor.black.withAlphaComponent(0.6).cgColor
        view.layer.addSublayer(fillLayer)
        
        // Corner guides
        let scanRect = CGRect(
            x: (view.bounds.width - scanAreaSize) / 2,
            y: (view.bounds.height - scanAreaSize) / 2,
            width: scanAreaSize,
            height: scanAreaSize
        )
        
        // Top-left corner
        addCorner(at: CGPoint(x: scanRect.minX, y: scanRect.minY), start: .right, end: .down)
        // Top-right corner
        addCorner(at: CGPoint(x: scanRect.maxX, y: scanRect.minY), start: .down, end: .left)
        // Bottom-left corner
        addCorner(at: CGPoint(x: scanRect.minX, y: scanRect.maxY), start: .up, end: .right)
        // Bottom-right corner
        addCorner(at: CGPoint(x: scanRect.maxX, y: scanRect.maxY), start: .left, end: .up)
        
        // Scanning animation
        addScanningAnimation(in: scanRect)
    }
    
    private func addCorner(at point: CGPoint, start: Direction, end: Direction) {
        let path = UIBezierPath()
        
        switch start {
        case .right:
            path.move(to: CGPoint(x: point.x, y: point.y))
            path.addLine(to: CGPoint(x: point.x + cornerLength, y: point.y))
        case .down:
            path.move(to: CGPoint(x: point.x, y: point.y))
            path.addLine(to: CGPoint(x: point.x, y: point.y + cornerLength))
        case .left:
            path.move(to: CGPoint(x: point.x, y: point.y))
            path.addLine(to: CGPoint(x: point.x - cornerLength, y: point.y))
        case .up:
            path.move(to: CGPoint(x: point.x, y: point.y))
            path.addLine(to: CGPoint(x: point.x, y: point.y - cornerLength))
        }
        
        path.move(to: point)
        
        switch end {
        case .right:
            path.addLine(to: CGPoint(x: point.x + cornerLength, y: point.y))
        case .down:
            path.addLine(to: CGPoint(x: point.x, y: point.y + cornerLength))
        case .left:
            path.addLine(to: CGPoint(x: point.x - cornerLength, y: point.y))
        case .up:
            path.addLine(to: CGPoint(x: point.x, y: point.y - cornerLength))
        }
        
        let cornerLayer = CAShapeLayer()
        cornerLayer.path = path.cgPath
        cornerLayer.strokeColor = UIColor.white.cgColor
        cornerLayer.fillColor = UIColor.clear.cgColor
        cornerLayer.lineWidth = cornerWidth
        cornerLayer.lineCap = .round
        view.layer.addSublayer(cornerLayer)
    }
    
    private func addScanningAnimation(in rect: CGRect) {
        let scanLine = UIView()
        scanLine.backgroundColor = UIColor.white.withAlphaComponent(0.8)
        scanLine.frame = CGRect(
            x: rect.minX + 10,
            y: rect.minY,
            width: rect.width - 20,
            height: 2
        )
        view.addSubview(scanLine)
        
        // Add gradient effect
        let gradient = CAGradientLayer()
        gradient.frame = scanLine.bounds
        gradient.colors = [
            UIColor.clear.cgColor,
            UIColor.white.cgColor,
            UIColor.clear.cgColor
        ]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        scanLine.layer.addSublayer(gradient)
        
        // Animate
        UIView.animate(withDuration: 2, delay: 0, options: [.repeat, .autoreverse], animations: {
            scanLine.frame.origin.y = rect.maxY - 2
        })
    }
    
    private func setupCloseButton() {
        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .white
        closeButton.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)
        
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }
    
    private func setupInstructions() {
        let instructionLabel = UILabel()
        instructionLabel.text = "Point camera at QR code"
        instructionLabel.textColor = .white
        instructionLabel.font = .systemFont(ofSize: 18, weight: .medium)
        instructionLabel.textAlignment = .center
        
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(instructionLabel)
        
        NSLayoutConstraint.activate([
            instructionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            instructionLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -50)
        ])
    }
    
    @objc private func closeTapped() {
        dismiss(animated: true)
    }
    
    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Scanner Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            self.dismiss(animated: true)
        })
        present(alert, animated: true)
    }
    
    // MARK: - AVCaptureMetadataOutputObjectsDelegate
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        captureSession.stopRunning()
        
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            
            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            completion?(stringValue)
        }
    }
    
    enum Direction {
        case up, down, left, right
    }
}