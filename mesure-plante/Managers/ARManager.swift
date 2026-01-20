import ARKit
import SceneKit
import Combine

/// Gestionnaire principal de la session ARKit avec support QR Code comme ancre
final class ARManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var distance: Float = 0.0
    @Published var surfaceCount: Int = 0
    @Published var placedPoints: [PlantPoint] = []
    @Published var isReady: Bool = false
    @Published var statusMessage: String = "Initialisation..."
    @Published var qrCodeDetected: Bool = false
    @Published var hasExistingData: Bool = false

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

    // MARK: - Configuration
    private let sphereRadius: CGFloat = 0.05
    private let sphereColor = UIColor.systemGreen
    private let restoredSphereColor = UIColor.systemBlue // Points restaurés en bleu

    override init() {
        super.init()
        setupSceneView()
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

    /// Configure avec les données du QR Code
    func configure(with qrData: QRCodeData) {
        self.qrData = qrData

        // Vérifier s'il existe des données sauvegardées pour ce QR Code
        if let existingSession = DataManager.shared.getSession(forQRCodeId: qrData.id) {
            self.currentSession = existingSession
            self.hasExistingData = !existingSession.points.isEmpty
            self.pointCounter = existingSession.points.count
            statusMessage = "Données existantes: \(existingSession.pointCount) points"
        } else {
            // Créer une nouvelle session
            self.currentSession = PlantSession(qrData: qrData)
            DataManager.shared.saveSession(self.currentSession!)
            self.hasExistingData = false
            statusMessage = "Nouvelle session créée"
        }
    }

    /// Démarre la session AR
    func startSession() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        configuration.environmentTexturing = .automatic

        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        statusMessage = "Scannez le QR Code pour calibrer..."
    }

    /// Met en pause la session AR
    func pauseSession() {
        sceneView.session.pause()
    }

    /// Appelé quand le QR Code est détecté visuellement (depuis la caméra)
    func setQRCodeAsOrigin() {
        guard let currentPosition = getCurrentCameraPosition(),
              let currentTransform = getCurrentCameraTransform() else {
            statusMessage = "Position caméra non disponible"
            return
        }

        // Le QR Code est devant la caméra, on utilise la position actuelle comme référence
        qrCodeWorldPosition = currentPosition
        qrCodeWorldTransform = currentTransform
        referencePosition = currentPosition
        qrCodeDetected = true

        // Si on a des points existants, les restaurer
        if hasExistingData {
            restoreSavedPoints()
        }

        isReady = true
        statusMessage = "QR Code calibré. Prêt à placer des points."
        HapticManager.shared.success()
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

    /// Place un nouveau point à la position actuelle
    func placePoint() {
        guard let currentPosition = getCurrentCameraPosition(),
              let qrPosition = qrCodeWorldPosition else {
            statusMessage = "Position non disponible. Calibrez d'abord le QR Code."
            return
        }

        // Calculer la distance depuis la référence
        let distanceFromRef = referencePosition.map { simd_distance($0, currentPosition) } ?? 0

        // Calculer la position RELATIVE au QR Code
        let relativePosition = currentPosition - qrPosition

        // Créer l'anchor
        let transform = matrix_identity_float4x4.translated(by: currentPosition)
        let anchor = ARAnchor(name: "PlantPoint_\(pointCounter + 1)", transform: transform)
        sceneView.session.add(anchor: anchor)

        // Créer le point local
        pointCounter += 1
        let point = PlantPoint(id: pointCounter, anchor: anchor, position: currentPosition)
        placedPoints.append(point)

        // Sauvegarder dans SQLite
        let savedPoint = SavedPlantPoint(
            id: pointCounter,
            nom: "Arbre \(pointCounter)",
            relativePosition: relativePosition,
            distanceFromPrevious: distanceFromRef
        )

        // Ajouter à la session locale
        currentSession?.addPoint(savedPoint)

        // Sauvegarder directement dans SQLite
        if let qrId = qrData?.id {
            DataManager.shared.addPoint(toSessionWithQRCodeId: qrId, point: savedPoint)
        }

        // Ce point devient la nouvelle référence
        referencePosition = currentPosition
        distance = 0.0

        // Feedback
        HapticManager.shared.success()
        statusMessage = "Arbre \(pointCounter) placé et sauvegardé"
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
            self.statusMessage = "Session reprise - Recalibrez le QR Code"
            self.qrCodeDetected = false
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
