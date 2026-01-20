import SwiftUI
import AVFoundation

/// Vue pour scanner le QR Code au démarrage
struct QRScannerView: View {
    @Binding var scannedData: QRCodeData?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isScanning = true
    @State private var showSuccess = false
    @State private var scannedName = ""

    var body: some View {
        ZStack {
            // Vue caméra
            QRScannerUIView(
                onCodeScanned: handleScannedCode,
                onError: handleError
            )
            .ignoresSafeArea()

            // Overlay normal
            if !showSuccess {
                VStack {
                    // Titre
                    Text("Scanner le QR Code")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.top, 60)

                    Spacer()

                    // Cadre de scan
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.green, lineWidth: 4)
                        .frame(width: 250, height: 250)
                        .overlay {
                            ScannerCorners()
                        }

                    Spacer()

                    // Instructions
                    VStack(spacing: 8) {
                        Text("Placez le QR Code dans le cadre")
                            .font(.subheadline)
                        Text("Le scan est automatique")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.white)
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 60)
                }
            }

            // Overlay succès
            if showSuccess {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    // Icône de succès animée
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.green)
                        .scaleEffect(showSuccess ? 1.0 : 0.5)
                        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: showSuccess)

                    VStack(spacing: 8) {
                        Text("QR Code détecté !")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text(scannedName)
                            .font(.headline)
                            .foregroundStyle(.green)
                    }

                    Text("Passage à la vue AR...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ProgressView()
                        .tint(.green)
                }
                .foregroundStyle(.white)
                .padding(40)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 24))
            }
        }
        .alert("Erreur de scan", isPresented: $showError) {
            Button("Réessayer") {
                isScanning = true
            }
        } message: {
            Text(errorMessage)
        }
    }

    private func handleScannedCode(_ code: String) {
        guard isScanning else { return }

        if let data = QRCodeData.from(jsonString: code) {
            isScanning = false
            HapticManager.shared.success()

            // Afficher le succès
            scannedName = data.nom
            withAnimation {
                showSuccess = true
            }

            // Passer à l'écran AR après un court délai
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                scannedData = data
            }
        } else {
            isScanning = false
            HapticManager.shared.error()
            errorMessage = "Format JSON invalide.\n\nLe QR Code doit contenir:\n• id\n• nom\n• lat\n• lon"
            showError = true
        }
    }

    private func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}

/// Coins décoratifs pour le scanner
struct ScannerCorners: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let cornerLength: CGFloat = 30
            let lineWidth: CGFloat = 4

            Path { path in
                // Coin supérieur gauche
                path.move(to: CGPoint(x: 0, y: cornerLength))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: cornerLength, y: 0))

                // Coin supérieur droit
                path.move(to: CGPoint(x: size.width - cornerLength, y: 0))
                path.addLine(to: CGPoint(x: size.width, y: 0))
                path.addLine(to: CGPoint(x: size.width, y: cornerLength))

                // Coin inférieur droit
                path.move(to: CGPoint(x: size.width, y: size.height - cornerLength))
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.addLine(to: CGPoint(x: size.width - cornerLength, y: size.height))

                // Coin inférieur gauche
                path.move(to: CGPoint(x: cornerLength, y: size.height))
                path.addLine(to: CGPoint(x: 0, y: size.height))
                path.addLine(to: CGPoint(x: 0, y: size.height - cornerLength))
            }
            .stroke(Color.green, lineWidth: lineWidth)
        }
    }
}

/// UIViewRepresentable pour la caméra QR
struct QRScannerUIView: UIViewRepresentable {
    let onCodeScanned: (String) -> Void
    let onError: (Error) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black

        let manager = QRCodeManager()
        manager.delegate = context.coordinator
        context.coordinator.manager = manager

        DispatchQueue.main.async {
            manager.startScanning(in: view)
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.manager?.updatePreviewFrame(uiView.bounds)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned, onError: onError)
    }

    class Coordinator: NSObject, QRCodeManagerDelegate {
        var manager: QRCodeManager?
        let onCodeScanned: (String) -> Void
        let onError: (Error) -> Void

        init(onCodeScanned: @escaping (String) -> Void, onError: @escaping (Error) -> Void) {
            self.onCodeScanned = onCodeScanned
            self.onError = onError
        }

        func qrCodeManager(_ manager: QRCodeManager, didScanCode code: String) {
            onCodeScanned(code)
        }

        func qrCodeManager(_ manager: QRCodeManager, didFailWithError error: Error) {
            onError(error)
        }
    }
}
