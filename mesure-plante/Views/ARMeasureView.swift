import SwiftUI
import ARKit

/// Vue principale AR pour la mesure des distances
struct ARMeasureView: View {
    let qrData: QRCodeData
    @StateObject private var arManager = ARManager()
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var showPointsList = false

    var body: some View {
        ZStack {
            // Vue AR
            ARSceneViewRepresentable(arManager: arManager)
                .ignoresSafeArea()

            // Overlay de recherche QR Code (automatique)
            if arManager.isSearchingQRCode && !arManager.qrCodeDetected {
                searchingOverlay
            }

            // HUD Overlay (seulement si calibré)
            if arManager.qrCodeDetected {
                VStack {
                    HUDOverlay(
                        referenceName: currentReferenceName,
                        distance: arManager.distance,
                        surfaceCount: arManager.surfaceCount,
                        pointCount: arManager.placedPoints.count,
                        statusMessage: arManager.statusMessage
                    )
                    Spacer()
                }
            }

            // Boutons en bas (seulement si calibré)
            if arManager.qrCodeDetected {
                bottomButtons
            }

            // Toast de confirmation
            if showToast {
                toastView
            }
        }
        .onAppear {
            arManager.configure(with: qrData)
            arManager.startSession()
        }
        .onDisappear {
            arManager.pauseSession()
        }
        .sheet(isPresented: $showPointsList) {
            PointsListView(points: arManager.placedPoints, qrData: qrData)
        }
    }

    // MARK: - Searching Overlay (Automatic QR Detection)

    private var searchingOverlay: some View {
        ZStack {
            // Fond semi-transparent
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 20) {
                    // Animation de recherche
                    ZStack {
                        // Cercle extérieur animé
                        Circle()
                            .stroke(Color.green.opacity(0.3), lineWidth: 4)
                            .frame(width: 100, height: 100)

                        // Cercle rotatif
                        Circle()
                            .trim(from: 0, to: 0.3)
                            .stroke(Color.green, lineWidth: 4)
                            .frame(width: 100, height: 100)
                            .rotationEffect(.degrees(arManager.isSearchingQRCode ? 360 : 0))
                            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: arManager.isSearchingQRCode)

                        // Icône QR
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 40))
                            .foregroundStyle(.green)
                    }

                    // Titre
                    VStack(spacing: 8) {
                        Text("Recherche automatique")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Pointez la caméra vers le QR Code\n« \(qrData.nom) »")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }

                    // Info données existantes
                    if arManager.hasExistingData {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                            Text("\(arManager.savedPointsCount) points seront restaurés")
                                .font(.caption)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // Bouton calibration manuelle (fallback)
                    Button(action: {
                        arManager.forceCalibration()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "scope")
                            Text("Calibrer manuellement")
                                .fontWeight(.medium)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Capsule())
                    }
                    .padding(.top, 8)

                    Text("Le QR code sera détecté automatiquement")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(32)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .padding()

                Spacer()
            }
        }
    }

    // MARK: - Bottom Buttons

    private var bottomButtons: some View {
        VStack {
            Spacer()

            HStack(spacing: 16) {
                // Bouton recalibrer
                Button(action: {
                    arManager.resetCalibration()
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.orange)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                }

                // Bouton liste des points
                if !arManager.placedPoints.isEmpty {
                    Button(action: { showPointsList = true }) {
                        Image(systemName: "list.bullet")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                    }
                }

                // Bouton placer point
                Button(action: placePoint) {
                    HStack(spacing: 12) {
                        Image(systemName: "leaf.fill")
                            .font(.title2)
                        Text("Placer Point")
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(arManager.isReady ? Color.green : Color.gray)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                }
                .disabled(!arManager.isReady)
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: - Toast View

    private var toastView: some View {
        VStack {
            Spacer()

            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white)
                Text(toastMessage)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color.green)
            .clipShape(Capsule())
            .shadow(radius: 10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .padding(.bottom, 120)
        }
        .animation(.spring(), value: showToast)
    }

    // MARK: - Helpers

    private var currentReferenceName: String {
        if let lastPoint = arManager.placedPoints.last {
            return lastPoint.nom
        }
        return qrData.nom
    }

    private func placePoint() {
        let previousCount = arManager.placedPoints.count
        arManager.placePoint()

        if arManager.placedPoints.count > previousCount {
            if let lastPoint = arManager.placedPoints.last {
                toastMessage = "\(lastPoint.nom) placé et sauvegardé"
                showToast = true

                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showToast = false
                }
            }
        }
    }
}

/// UIViewRepresentable pour intégrer ARSCNView dans SwiftUI
struct ARSceneViewRepresentable: UIViewRepresentable {
    let arManager: ARManager

    func makeUIView(context: Context) -> ARSCNView {
        return arManager.sceneView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

/// Vue liste des points placés
struct PointsListView: View {
    let points: [PlantPoint]
    let qrData: QRCodeData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                // Section info plantation
                Section {
                    HStack {
                        Image(systemName: "qrcode")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading) {
                            Text(qrData.nom)
                                .font(.headline)
                            Text("ID: \(qrData.id)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Plantation")
                }

                // Légende couleurs
                Section {
                    HStack(spacing: 16) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 12, height: 12)
                            Text("Nouveau")
                                .font(.caption)
                        }
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 12, height: 12)
                            Text("Restauré")
                                .font(.caption)
                        }
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.yellow)
                                .frame(width: 12, height: 12)
                            Text("QR Code")
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("Légende")
                }

                // Section points placés
                Section {
                    if points.isEmpty {
                        Text("Aucun point placé")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(points) { point in
                            HStack {
                                Image(systemName: "leaf.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.title2)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(point.nom)
                                        .font(.headline)

                                    Text("Position: (\(String(format: "%.2f", point.position.x)), \(String(format: "%.2f", point.position.y)), \(String(format: "%.2f", point.position.z)))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text("#\(point.id)")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Points placés (\(points.count))")
                }

                // Info sauvegarde
                Section {
                    HStack {
                        Image(systemName: "checkmark.icloud.fill")
                            .foregroundStyle(.green)
                        Text("Données sauvegardées automatiquement")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Résumé")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
        }
    }
}
