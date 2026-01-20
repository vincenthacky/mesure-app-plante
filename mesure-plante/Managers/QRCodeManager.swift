import AVFoundation
import UIKit

/// Délégué pour recevoir les résultats du scan QR Code
protocol QRCodeManagerDelegate: AnyObject {
    func qrCodeManager(_ manager: QRCodeManager, didScanCode code: String)
    func qrCodeManager(_ manager: QRCodeManager, didFailWithError error: Error)
}

/// Gestionnaire du scan de QR Code avec AVFoundation
final class QRCodeManager: NSObject {
    weak var delegate: QRCodeManagerDelegate?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isScanning = false

    /// Configure et démarre la session de capture
    func startScanning(in view: UIView) {
        guard !isScanning else { return }

        let session = AVCaptureSession()

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            delegate?.qrCodeManager(self, didFailWithError: QRScanError.cameraUnavailable)
            return
        }

        do {
            let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)

            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            } else {
                delegate?.qrCodeManager(self, didFailWithError: QRScanError.inputError)
                return
            }

            let metadataOutput = AVCaptureMetadataOutput()

            if session.canAddOutput(metadataOutput) {
                session.addOutput(metadataOutput)
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                metadataOutput.metadataObjectTypes = [.qr]
            } else {
                delegate?.qrCodeManager(self, didFailWithError: QRScanError.outputError)
                return
            }

            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.frame = view.layer.bounds
            previewLayer.videoGravity = .resizeAspectFill
            view.layer.insertSublayer(previewLayer, at: 0)

            self.previewLayer = previewLayer
            self.captureSession = session
            self.isScanning = true

            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        } catch {
            delegate?.qrCodeManager(self, didFailWithError: error)
        }
    }

    /// Arrête la session de capture
    func stopScanning() {
        guard isScanning else { return }

        captureSession?.stopRunning()
        previewLayer?.removeFromSuperlayer()
        captureSession = nil
        previewLayer = nil
        isScanning = false
    }

    /// Met à jour le frame du preview layer
    func updatePreviewFrame(_ frame: CGRect) {
        previewLayer?.frame = frame
    }
}

// MARK: - AVCaptureMetadataOutputObjectsDelegate
extension QRCodeManager: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              metadataObject.type == .qr,
              let stringValue = metadataObject.stringValue else {
            return
        }

        HapticManager.shared.impact()
        delegate?.qrCodeManager(self, didScanCode: stringValue)
    }
}

// MARK: - Erreurs
enum QRScanError: LocalizedError {
    case cameraUnavailable
    case inputError
    case outputError

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "La caméra n'est pas disponible"
        case .inputError:
            return "Impossible de configurer l'entrée vidéo"
        case .outputError:
            return "Impossible de configurer la sortie métadonnées"
        }
    }
}
