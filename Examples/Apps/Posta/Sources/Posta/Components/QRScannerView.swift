import SwiftUI
import AVFoundation

struct QRScannerView: UIViewControllerRepresentable {
    let onScanned: (String) -> Void
    
    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onScanned = onScanned
        return controller
    }
    
    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var onScanned: ((String) -> Void)?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor.black
        captureSession = AVCaptureSession()
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }
        
        if (captureSession.canAddInput(videoInput)) {
            captureSession.addInput(videoInput)
        } else {
            failed()
            return
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if (captureSession.canAddOutput(metadataOutput)) {
            captureSession.addOutput(metadataOutput)
            
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            failed()
            return
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        // Add scanning overlay
        addScanningOverlay()
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }
    
    func failed() {
        let ac = UIAlertController(title: "Scanning not supported", message: "Your device does not support scanning a code from an item. Please use a device with a camera.", preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default))
        present(ac, animated: true)
        captureSession = nil
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if (captureSession?.isRunning == false) {
            DispatchQueue.global(qos: .background).async { [weak self] in
                self?.captureSession.startRunning()
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if (captureSession?.isRunning == true) {
            captureSession.stopRunning()
        }
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        captureSession.stopRunning()
        
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            onScanned?(stringValue)
            dismiss(animated: true)
        }
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    private func addScanningOverlay() {
        // Add semi-transparent overlay
        let overlayView = UIView(frame: view.bounds)
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        view.addSubview(overlayView)
        
        // Create scanning area
        let scanSize: CGFloat = min(view.bounds.width, view.bounds.height) * 0.7
        let scanRect = CGRect(
            x: (view.bounds.width - scanSize) / 2,
            y: (view.bounds.height - scanSize) / 2,
            width: scanSize,
            height: scanSize
        )
        
        // Create path for overlay with hole
        let path = UIBezierPath(rect: view.bounds)
        let scanPath = UIBezierPath(roundedRect: scanRect, cornerRadius: 20)
        path.append(scanPath.reversing())
        
        let maskLayer = CAShapeLayer()
        maskLayer.path = path.cgPath
        overlayView.layer.mask = maskLayer
        
        // Add corner brackets
        let cornerLength: CGFloat = 30
        let cornerWidth: CGFloat = 4
        let cornerRadius: CGFloat = 2
        
        // Top-left corner
        addCornerBracket(
            to: view,
            at: CGPoint(x: scanRect.minX, y: scanRect.minY),
            orientation: .topLeft,
            length: cornerLength,
            width: cornerWidth,
            radius: cornerRadius
        )
        
        // Top-right corner
        addCornerBracket(
            to: view,
            at: CGPoint(x: scanRect.maxX, y: scanRect.minY),
            orientation: .topRight,
            length: cornerLength,
            width: cornerWidth,
            radius: cornerRadius
        )
        
        // Bottom-left corner
        addCornerBracket(
            to: view,
            at: CGPoint(x: scanRect.minX, y: scanRect.maxY),
            orientation: .bottomLeft,
            length: cornerLength,
            width: cornerWidth,
            radius: cornerRadius
        )
        
        // Bottom-right corner
        addCornerBracket(
            to: view,
            at: CGPoint(x: scanRect.maxX, y: scanRect.maxY),
            orientation: .bottomRight,
            length: cornerLength,
            width: cornerWidth,
            radius: cornerRadius
        )
        
        // Add instruction label
        let label = UILabel()
        label.text = "Align QR code within frame"
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.topAnchor.constraint(equalTo: view.topAnchor, constant: scanRect.minY - 60)
        ])
        
        // Add close button
        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)
        
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
    
    @objc private func closeTapped() {
        dismiss(animated: true)
    }
    
    enum CornerOrientation {
        case topLeft, topRight, bottomLeft, bottomRight
    }
    
    private func addCornerBracket(to view: UIView, at point: CGPoint, orientation: CornerOrientation, length: CGFloat, width: CGFloat, radius: CGFloat) {
        let path = UIBezierPath()
        
        switch orientation {
        case .topLeft:
            path.move(to: CGPoint(x: point.x + length, y: point.y))
            path.addLine(to: CGPoint(x: point.x + radius, y: point.y))
            path.addArc(withCenter: CGPoint(x: point.x + radius, y: point.y + radius),
                       radius: radius,
                       startAngle: .pi * 1.5,
                       endAngle: .pi,
                       clockwise: false)
            path.addLine(to: CGPoint(x: point.x, y: point.y + length))
            
        case .topRight:
            path.move(to: CGPoint(x: point.x - length, y: point.y))
            path.addLine(to: CGPoint(x: point.x - radius, y: point.y))
            path.addArc(withCenter: CGPoint(x: point.x - radius, y: point.y + radius),
                       radius: radius,
                       startAngle: .pi * 1.5,
                       endAngle: 0,
                       clockwise: true)
            path.addLine(to: CGPoint(x: point.x, y: point.y + length))
            
        case .bottomLeft:
            path.move(to: CGPoint(x: point.x + length, y: point.y))
            path.addLine(to: CGPoint(x: point.x + radius, y: point.y))
            path.addArc(withCenter: CGPoint(x: point.x + radius, y: point.y - radius),
                       radius: radius,
                       startAngle: .pi * 0.5,
                       endAngle: .pi,
                       clockwise: true)
            path.addLine(to: CGPoint(x: point.x, y: point.y - length))
            
        case .bottomRight:
            path.move(to: CGPoint(x: point.x - length, y: point.y))
            path.addLine(to: CGPoint(x: point.x - radius, y: point.y))
            path.addArc(withCenter: CGPoint(x: point.x - radius, y: point.y - radius),
                       radius: radius,
                       startAngle: .pi * 0.5,
                       endAngle: 0,
                       clockwise: false)
            path.addLine(to: CGPoint(x: point.x, y: point.y - length))
        }
        
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = path.cgPath
        shapeLayer.strokeColor = UIColor.white.cgColor
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.lineWidth = width
        shapeLayer.lineCap = .round
        view.layer.addSublayer(shapeLayer)
    }
}