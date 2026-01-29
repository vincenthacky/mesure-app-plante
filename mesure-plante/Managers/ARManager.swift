import ARKit
import SceneKit
import Combine
import Vision

/// Gestionnaire principal de la session ARKit avec détection automatique de QR Code de asso
final class ARManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var distance: Float = 0.0
    @Published var surfaceCount: Int = 0
    @Published var placedPoints: [PlantPoint] = []
    @Published var isReady: Bool = false
    @Published var statusMessage: String = "Initialisation..."
    @Published var qrCodeDetected: Bool = false
    @Published var hasExistingData: Bool = false
    @Published var isSearchingQRCode: Bool = true

    // MARK: - AR Properties
    private(set) var sceneView: ARSCNView!
    private var qrCodeAnchor: ARAnchor?
    private var qrCodeWorldPosition: SIMD3<Float>?
    private var qrCodeWorldTransform: simd_float4x4?
    private var referencePosition: SIMD3<Float>?
    private var pointCounter: Int = 0

    // MARK: - Data Properties
    private var currentSession: PlantSession?
    private var qrData: QRCodeData?

    // MARK: - Vision Properties
    private var visionRequests: [VNRequest] = []
    private var isProcessingFrame: Bool = false
    private var lastQRCodeDetectionTime: Date = .distantPast
    private let qrCodeDetectionInterval: TimeInterval = 0.3 // Scan toutes les 0.3s

    // MARK: - QR Code Visual Marker
    private var qrCodeMarkerNode: SCNNode?

    // MARK: - Configuration
    private let sphereRadius: CGFloat = 0.05
    private let sphereColor = UIColor.systemGreen
    private let restoredSphereColor = UIColor.systemBlue

    override init() {
        super.init()
        setupSceneView()
        setupVision()
    }

    // MARK: - Setup
    private func setupSceneView() {
        sceneView = ARSCNView()
        sceneView.delegate = self
        sceneView.session.delegate = self
        sceneView.autoenablesDefaultLighting = true
        sceneView.automaticallyUpdatesLighting = true
        sceneView.debugOptions = [.showFeaturePoints]
    }

    /// Configure Vision pour la détection de QR Code
    private func setupVision() {
        let barcodeRequest = VNDetectBarcodesRequest { [weak self] request, error in
            self?.handleBarcodeDetection(request: request, error: error)
        }
        barcodeRequest.symbologies = [.qr]
        visionRequests = [barcodeRequest]
    }

    /// Configure avec les données du QR Code
    func configure(with qrData: QRCodeData) {
        self.qrData = qrData

        print("🔍 [ARManager] Configuration avec QR Code ID: '\(qrData.id)', nom: '\(qrData.nom)'")

        // Vérifier s'il existe des données sauvegardées pour ce QR Code
        if let existingSession = DataManager.shared.getSession(forQRCodeId: qrData.id) {
            print("✅ [ARManager] Session existante trouvée!")
            print("   - Points sauvegardés: \(existingSession.points.count)")
            for (index, point) in existingSession.points.enumerated() {
                print("   - Point \(index + 1): \(point.nom) à (\(point.relativeX), \(point.relativeY), \(point.relativeZ))")
            }

            self.currentSession = existingSession
            self.hasExistingData = !existingSession.points.isEmpty
            self.pointCounter = existingSession.points.count
            statusMessage = "Données existantes: \(existingSession.pointCount) points"
        } else {
            print("⚠️ [ARManager] Aucune session existante - création nouvelle session")
            // Créer une nouvelle session
            self.currentSession = PlantSession(qrData: qrData)
            DataManager.shared.saveSession(self.currentSession!)
            self.hasExistingData = false
            statusMessage = "Nouvelle session créée"
        }

        print("📊 [ARManager] hasExistingData = \(hasExistingData), pointCounter = \(pointCounter)")
    }

    /// Démarre la session AR
    func startSession() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        configuration.environmentTexturing = .automatic

        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isSearchingQRCode = true
        statusMessage = "Recherche du QR Code..."
    }

    /// Met en pause la session AR
    func pauseSession() {
        sceneView.session.pause()
    }

    // MARK: - QR Code Detection with Vision

    /// Traite un frame pour détecter les QR codes
    private func processFrameForQRCode() {
        guard isSearchingQRCode,
              !isProcessingFrame,
              Date().timeIntervalSince(lastQRCodeDetectionTime) > qrCodeDetectionInterval,
              let frame = sceneView.session.currentFrame else { return }

        isProcessingFrame = true
        lastQRCodeDetectionTime = Date()

        let pixelBuffer = frame.capturedImage

        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try imageRequestHandler.perform(self?.visionRequests ?? [])
            } catch {
                print("Erreur Vision: \(error)")
            }
            DispatchQueue.main.async {
                self?.isProcessingFrame = false
            }
        }
    }

    /// Gère la détection de codes-barres par Vision
    private func handleBarcodeDetection(request: VNRequest, error: Error?) {
        guard let results = request.results as? [VNBarcodeObservation],
              let qrData = self.qrData else { return }

        for barcode in results {
            guard let payload = barcode.payloadStringValue else { continue }

            // Vérifier si c'est le bon QR code (même ID)
            if let scannedData = QRCodeData.from(jsonString: payload),
               scannedData.id == qrData.id {

                // Calculer la position 3D du QR code
                DispatchQueue.main.async { [weak self] in
                    self?.calibrateWithDetectedQRCode(boundingBox: barcode.boundingBox)
                }
                return
            }
        }
    }

    /// Calibre avec le QR code détecté
    private func calibrateWithDetectedQRCode(boundingBox: CGRect) {
        guard let frame = sceneView.session.currentFrame,
              !qrCodeDetected else { return }

        // Convertir le boundingBox (coordonnées Vision) en point central (coordonnées écran)
        let viewSize = sceneView.bounds.size

        // Vision utilise un système de coordonnées normalisé (0-1) avec origine en bas à gauche
        // On doit le convertir en coordonnées écran
        let centerX = boundingBox.midX * viewSize.width
        let centerY = (1 - boundingBox.midY) * viewSize.height
        let screenPoint = CGPoint(x: centerX, y: centerY)

        // Faire un raycast pour trouver la position 3D
        if let query = sceneView.raycastQuery(from: screenPoint, allowing: .estimatedPlane, alignment: .any),
           let result = sceneView.session.raycast(query).first {

            // Position 3D du QR code
            let qrPosition = SIMD3<Float>(
                result.worldTransform.columns.3.x,
                result.worldTransform.columns.3.y,
                result.worldTransform.columns.3.z
            )

            setQRCodeOrigin(at: qrPosition, transform: result.worldTransform)

        } else {
            // Fallback: utiliser une estimation basée sur la distance
            // Estimer que le QR code est à environ 0.5m devant la caméra
            let cameraTransform = frame.camera.transform
            let cameraPosition = SIMD3<Float>(
                cameraTransform.columns.3.x,
                cameraTransform.columns.3.y,
                cameraTransform.columns.3.z
            )

            // Direction de la caméra (vers l'avant)
            let cameraForward = SIMD3<Float>(
                -cameraTransform.columns.2.x,
                -cameraTransform.columns.2.y,
                -cameraTransform.columns.2.z
            )

            // Position estimée du QR code (0.5m devant)
            let estimatedQRPosition = cameraPosition + (cameraForward * 0.5)

            setQRCodeOrigin(at: estimatedQRPosition, transform: cameraTransform)
        }
    }

    /// Définit l'origine au QR code détecté
    private func setQRCodeOrigin(at position: SIMD3<Float>, transform: simd_float4x4) {
        qrCodeWorldPosition = position
        qrCodeWorldTransform = transform
        referencePosition = position
        qrCodeDetected = true
        isSearchingQRCode = false

        // Ajouter un marqueur visuel à la position du QR code
        addQRCodeMarker(at: position)

        // Si on a des points existants, les restaurer
        if hasExistingData {
            restoreSavedPoints()
        }

        isReady = true
        statusMessage = "QR Code détecté! Prêt à placer des points."
        HapticManager.shared.success()
    }

    /// Ajoute un marqueur visuel à la position du QR code
    private func addQRCodeMarker(at position: SIMD3<Float>) {
        // Supprimer l'ancien marqueur si existant
        qrCodeMarkerNode?.removeFromParentNode()

        // Créer un marqueur pour visualiser la position du QR code
        let markerGeometry = SCNBox(width: 0.1, height: 0.005, length: 0.1, chamferRadius: 0.01)
        markerGeometry.firstMaterial?.diffuse.contents = UIColor.systemYellow.withAlphaComponent(0.8)
        markerGeometry.firstMaterial?.emission.contents = UIColor.systemYellow.withAlphaComponent(0.3)

        let markerNode = SCNNode(geometry: markerGeometry)
        markerNode.position = SCNVector3(position.x, position.y, position.z)

        // Ajouter un label "QR"
        let textGeometry = SCNText(string: "QR", extrusionDepth: 0.01)
        textGeometry.font = UIFont.systemFont(ofSize: 0.05, weight: .bold)
        textGeometry.firstMaterial?.diffuse.contents = UIColor.white

        let textNode = SCNNode(geometry: textGeometry)
        textNode.scale = SCNVector3(0.5, 0.5, 0.5)
        textNode.position = SCNVector3(-0.02, 0.02, 0)

        let billboardConstraint = SCNBillboardConstraint()
        billboardConstraint.freeAxes = .Y
        textNode.constraints = [billboardConstraint]

        markerNode.addChildNode(textNode)

        sceneView.scene.rootNode.addChildNode(markerNode)
        qrCodeMarkerNode = markerNode
    }

    /// Appelé manuellement pour forcer la calibration (fallback)
    func forceCalibration() {
        guard let currentPosition = getCurrentCameraPosition(),
              let currentTransform = getCurrentCameraTransform() else {
            statusMessage = "Position caméra non disponible"
            return
        }

        setQRCodeOrigin(at: currentPosition, transform: currentTransform)
    }

    /// Réinitialise pour une nouvelle recherche de QR code
    func resetCalibration() {
        qrCodeDetected = false
        isSearchingQRCode = true
        isReady = false
        qrCodeMarkerNode?.removeFromParentNode()
        qrCodeMarkerNode = nil

        // Supprimer les points affichés (mais pas les données sauvegardées)
        placedPoints.removeAll()

        // Recharger les données existantes
        if let qrData = qrData {
            configure(with: qrData)
        }

        statusMessage = "Recherche du QR Code..."
    }

    /// Restaure les points sauvegardés dans l'espace AR
    private func restoreSavedPoints() {
        guard let session = currentSession,
              let qrPosition = qrCodeWorldPosition else { return }

        statusMessage = "Restauration de \(session.points.count) points..."

        for savedPoint in session.points {
            // Calculer la position mondiale à partir de la position relative
            let worldPosition = qrPosition + savedPoint.relativePosition

            // Créer un anchor et une sphère
            let transform = matrix_identity_float4x4.translated(by: worldPosition)
            let anchor = ARAnchor(name: "RestoredPoint_\(savedPoint.id)", transform: transform)
            sceneView.session.add(anchor: anchor)

            // Ajouter au tableau local
            let plantPoint = PlantPoint(id: savedPoint.id, anchor: anchor, position: worldPosition)
            placedPoints.append(plantPoint)
        }

        // Mettre à jour le compteur et la référence
        pointCounter = session.points.count
        if let lastPoint = placedPoints.last {
            referencePosition = lastPoint.position
        }

        statusMessage = "\(session.points.count) points restaurés"
        HapticManager.shared.success()
    }

    /// Reconstruit tous les points à partir d'un point de référence connu
    /// Utilisé quand le QR code est perdu mais qu'on reconnaît un arbre existant
    /// - Parameters:
    ///   - knownPointId: L'ID du point dont on connaît la position actuelle
    ///   - currentPosition: La position actuelle de ce point dans l'espace AR
    func reconstructFromKnownPoint(knownPointId: Int, currentPosition: SIMD3<Float>) {
        guard let session = currentSession else {
            statusMessage = "Aucune session active"
            return
        }

        print("🔄 [ARManager] Reconstruction depuis point #\(knownPointId)")
        print("   - Position actuelle: \(currentPosition)")

        // Utiliser la fonction de reconstruction de PlantSession
        let reconstructedPositions = session.reconstructPositions(
            fromKnownPointId: knownPointId,
            knownPosition: currentPosition
        )

        if reconstructedPositions.isEmpty {
            statusMessage = "Point #\(knownPointId) non trouvé"
            return
        }

        // Supprimer les anciens points affichés
        placedPoints.removeAll()

        // Recalculer la position du QR code à partir du point connu
        if let knownSavedPoint = session.points.first(where: { $0.id == knownPointId }) {
            // Position QR = position connue - position relative au QR
            qrCodeWorldPosition = currentPosition - knownSavedPoint.relativePosition
            print("   - Position QR recalculée: \(qrCodeWorldPosition!)")
        }

        // Afficher tous les points reconstruits
        for savedPoint in session.points {
            guard let worldPosition = reconstructedPositions[savedPoint.id] else { continue }

            // Créer un anchor et une sphère
            let transform = matrix_identity_float4x4.translated(by: worldPosition)
            let anchor = ARAnchor(name: "ReconstructedPoint_\(savedPoint.id)", transform: transform)
            sceneView.session.add(anchor: anchor)

            // Ajouter au tableau local
            let plantPoint = PlantPoint(id: savedPoint.id, anchor: anchor, position: worldPosition)
            placedPoints.append(plantPoint)

            print("   - Point #\(savedPoint.id) reconstruit à \(worldPosition)")
        }

        // Mettre à jour l'état
        pointCounter = session.points.count
        if let lastPoint = placedPoints.last {
            referencePosition = lastPoint.position
        }

        qrCodeDetected = true
        isReady = true
        statusMessage = "\(session.points.count) points reconstruits depuis Arbre \(knownPointId)"
        HapticManager.shared.success()
    }

    /// Liste des points disponibles pour la reconstruction
    var availablePointsForReconstruction: [(id: Int, nom: String)] {
        guard let session = currentSession else { return [] }
        return session.points.map { (id: $0.id, nom: $0.nom) }
    }

    /// Place un nouveau point à la position actuelle (avec chaînage)
    func placePoint() {
        guard let currentPosition = getCurrentCameraPosition(),
              let qrPosition = qrCodeWorldPosition else {
            statusMessage = "Position non disponible. Calibrez d'abord le QR Code."
            return
        }

        // Calculer la position RELATIVE au QR Code
        let relativeToQR = currentPosition - qrPosition

        // Calculer la position RELATIVE au point PRÉCÉDENT (chaînage)
        let previousPointId: Int
        let relativeToPrevious: SIMD3<Float>
        let distanceFromPrevious: Float

        if let lastPoint = placedPoints.last {
            // Il y a un point précédent → chaînage
            previousPointId = lastPoint.id
            relativeToPrevious = currentPosition - lastPoint.position
            distanceFromPrevious = simd_distance(lastPoint.position, currentPosition)
        } else {
            // Premier point → relatif au QR code
            previousPointId = 0
            relativeToPrevious = relativeToQR
            distanceFromPrevious = simd_distance(qrPosition, currentPosition)
        }

        print("📍 [ARManager] Placement point avec CHAÎNAGE:")
        print("   - Position caméra: \(currentPosition)")
        print("   - Position QR: \(qrPosition)")
        print("   - Relatif au QR: \(relativeToQR)")
        print("   - Relatif au point précédent (#\(previousPointId)): \(relativeToPrevious)")
        print("   - Distance depuis précédent: \(distanceFromPrevious)m")

        // Créer l'anchor
        let transform = matrix_identity_float4x4.translated(by: currentPosition)
        let anchor = ARAnchor(name: "PlantPoint_\(pointCounter + 1)", transform: transform)
        sceneView.session.add(anchor: anchor)

        // Créer le point local
        pointCounter += 1
        let point = PlantPoint(id: pointCounter, anchor: anchor, position: currentPosition)
        placedPoints.append(point)

        // Sauvegarder dans SQLite avec chaînage complet
        let savedPoint = SavedPlantPoint(
            id: pointCounter,
            nom: "Arbre \(pointCounter)",
            relativeToQR: relativeToQR,
            relativeToPrevious: relativeToPrevious,
            previousPointId: previousPointId,
            distanceFromPrevious: distanceFromPrevious
        )

        // Ajouter à la session locale
        currentSession?.addPoint(savedPoint)

        // Sauvegarder directement dans SQLite
        if let qrId = qrData?.id {
            print("💾 [ARManager] Sauvegarde point chaîné dans SQLite pour QR ID: '\(qrId)'")
            DataManager.shared.addPoint(toSessionWithQRCodeId: qrId, point: savedPoint)
        } else {
            print("❌ [ARManager] ERREUR: qrData?.id est nil!")
        }

        // Ce point devient la nouvelle référence pour la distance affichée
        referencePosition = currentPosition
        distance = 0.0

        // Feedback
        HapticManager.shared.success()
        statusMessage = "Arbre \(pointCounter) placé et chaîné"
    }

    /// Récupère la position actuelle de la caméra
    private func getCurrentCameraPosition() -> SIMD3<Float>? {
        guard let frame = sceneView.session.currentFrame else { return nil }
        let transform = frame.camera.transform
        return SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    }

    /// Récupère la transformation actuelle de la caméra
    private func getCurrentCameraTransform() -> simd_float4x4? {
        return sceneView.session.currentFrame?.camera.transform
    }

    /// Crée un noeud sphère pour représenter un point planté
    private func createSphereNode(for point: PlantPoint, isRestored: Bool = false) -> SCNNode {
        let sphere = SCNSphere(radius: sphereRadius)
        let color = isRestored ? restoredSphereColor : sphereColor
        sphere.firstMaterial?.diffuse.contents = color
        sphere.firstMaterial?.emission.contents = color.withAlphaComponent(0.3)

        let sphereNode = SCNNode(geometry: sphere)

        // Label 3D
        let textGeometry = SCNText(string: point.nom, extrusionDepth: 0.01)
        textGeometry.font = UIFont.systemFont(ofSize: 0.1, weight: .bold)
        textGeometry.firstMaterial?.diffuse.contents = UIColor.white
        textGeometry.flatness = 0.1

        let textNode = SCNNode(geometry: textGeometry)
        textNode.scale = SCNVector3(0.5, 0.5, 0.5)

        let (min, max) = textGeometry.boundingBox
        let textWidth = (max.x - min.x) * 0.5
        textNode.position = SCNVector3(-textWidth / 2, Float(sphereRadius) + 0.05, 0)

        let billboardConstraint = SCNBillboardConstraint()
        billboardConstraint.freeAxes = .Y
        textNode.constraints = [billboardConstraint]

        sphereNode.addChildNode(textNode)

        return sphereNode
    }

    /// Nombre de points sauvegardés pour le QR actuel
    var savedPointsCount: Int {
        currentSession?.pointCount ?? 0
    }
}

// MARK: - ARSCNViewDelegate
extension ARManager: ARSCNViewDelegate {
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        // Plans détectés
        if let planeAnchor = anchor as? ARPlaneAnchor {
            DispatchQueue.main.async {
                self.surfaceCount += 1
            }

            let planeNode = createPlaneNode(for: planeAnchor)
            node.addChildNode(planeNode)
            return
        }

        // Points restaurés (bleus)
        if anchor.name?.starts(with: "RestoredPoint_") == true {
            if let point = placedPoints.first(where: { $0.anchor.identifier == anchor.identifier }) {
                let sphereNode = createSphereNode(for: point, isRestored: true)
                node.addChildNode(sphereNode)
            }
            return
        }

        // Nouveaux points (verts)
        if anchor.name?.starts(with: "PlantPoint_") == true {
            if let point = placedPoints.first(where: { $0.anchor.identifier == anchor.identifier }) {
                let sphereNode = createSphereNode(for: point, isRestored: false)
                node.addChildNode(sphereNode)
            }
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        if let planeNode = node.childNodes.first {
            updatePlaneNode(planeNode, for: planeAnchor)
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        // Scanner pour les QR codes pendant la recherche
        processFrameForQRCode()

        guard let currentPosition = getCurrentCameraPosition(),
              let reference = referencePosition else { return }

        let newDistance = simd_distance(reference, currentPosition)

        DispatchQueue.main.async {
            self.distance = newDistance
        }
    }

    private func createPlaneNode(for planeAnchor: ARPlaneAnchor) -> SCNNode {
        let plane = SCNPlane(
            width: CGFloat(planeAnchor.planeExtent.width),
            height: CGFloat(planeAnchor.planeExtent.height)
        )
        plane.firstMaterial?.diffuse.contents = UIColor.cyan.withAlphaComponent(0.3)
        plane.firstMaterial?.isDoubleSided = true

        let planeNode = SCNNode(geometry: plane)
        planeNode.position = SCNVector3(planeAnchor.center.x, 0, planeAnchor.center.z)
        planeNode.eulerAngles.x = -.pi / 2

        return planeNode
    }

    private func updatePlaneNode(_ node: SCNNode, for planeAnchor: ARPlaneAnchor) {
        guard let plane = node.geometry as? SCNPlane else { return }
        plane.width = CGFloat(planeAnchor.planeExtent.width)
        plane.height = CGFloat(planeAnchor.planeExtent.height)
        node.position = SCNVector3(planeAnchor.center.x, 0, planeAnchor.center.z)
    }
}

// MARK: - ARSessionDelegate
extension ARManager: ARSessionDelegate {
    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.statusMessage = "Erreur AR: \(error.localizedDescription)"
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        DispatchQueue.main.async {
            self.statusMessage = "Session interrompue"
        }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        DispatchQueue.main.async {
            self.statusMessage = "Session reprise - Recherche du QR Code..."
            self.qrCodeDetected = false
            self.isSearchingQRCode = true
            self.isReady = false
        }
    }
}

// MARK: - Matrix Extension
extension matrix_float4x4 {
    func translated(by translation: SIMD3<Float>) -> matrix_float4x4 {
        var result = self
        result.columns.3.x = translation.x
        result.columns.3.y = translation.y
        result.columns.3.z = translation.z
        return result
    }
}
