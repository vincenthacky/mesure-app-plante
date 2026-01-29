import Foundation

/// Session de plantation avec tous les points placés (positions relatives au QR Code ET chaînées)
struct PlantSession: Codable, Identifiable {
    let id: UUID
    let qrCodeId: String
    let plantationName: String
    let latitude: Double
    let longitude: Double
    let createdAt: Date
    var updatedAt: Date
    var points: [SavedPlantPoint]

    /// Initialisation depuis un QR Code (nouvelle session)
    init(qrData: QRCodeData) {
        self.id = UUID()
        self.qrCodeId = qrData.id
        self.plantationName = qrData.nom
        self.latitude = qrData.lat
        self.longitude = qrData.lon
        self.createdAt = Date()
        self.updatedAt = Date()
        self.points = []
    }

    /// Initialisation complète (pour reconstruction depuis SQLite)
    init(id: UUID, qrCodeId: String, plantationName: String, latitude: Double, longitude: Double, createdAt: Date, updatedAt: Date, points: [SavedPlantPoint]) {
        self.id = id
        self.qrCodeId = qrCodeId
        self.plantationName = plantationName
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.points = points
    }

    /// Ajoute un point à la session
    mutating func addPoint(_ point: SavedPlantPoint) {
        points.append(point)
        updatedAt = Date()
    }

    /// Nombre total de points
    var pointCount: Int {
        points.count
    }

    /// Reconstruit les positions de tous les points à partir d'un point de référence connu
    /// - Parameters:
    ///   - knownPointId: L'ID du point dont on connaît la position actuelle
    ///   - knownPosition: La position mondiale actuelle de ce point
    /// - Returns: Dictionnaire [pointId: position mondiale]
    func reconstructPositions(fromKnownPointId knownPointId: Int, knownPosition: SIMD3<Float>) -> [Int: SIMD3<Float>] {
        var positions: [Int: SIMD3<Float>] = [:]

        guard let knownIndex = points.firstIndex(where: { $0.id == knownPointId }) else {
            return positions
        }

        // Position du point connu
        positions[knownPointId] = knownPosition

        // Reconstruire vers l'avant (points suivants)
        var currentPosition = knownPosition
        for i in (knownIndex + 1)..<points.count {
            let point = points[i]
            // Position = position précédente + déplacement relatif
            currentPosition = currentPosition + point.relativeToePrevious
            positions[point.id] = currentPosition
        }

        // Reconstruire vers l'arrière (points précédents)
        currentPosition = knownPosition
        for i in stride(from: knownIndex - 1, through: 0, by: -1) {
            let point = points[i]
            let nextPoint = points[i + 1]
            // Position = position suivante - déplacement relatif du suivant
            currentPosition = currentPosition - nextPoint.relativeToePrevious
            positions[point.id] = currentPosition
        }

        return positions
    }
}

/// Point sauvegardé avec position RELATIVE au QR Code ET au point précédent (chaînage)
struct SavedPlantPoint: Codable, Identifiable {
    let id: Int
    let nom: String

    // Position relative au QR Code (origine absolue)
    let relativeX: Float
    let relativeY: Float
    let relativeZ: Float

    // Position relative au point PRÉCÉDENT (chaînage)
    // Pour le premier point, c'est identique à la position relative au QR
    let relativeToPreviousX: Float
    let relativeToPreviousY: Float
    let relativeToPreviousZ: Float

    // ID du point précédent (0 si c'est le premier point, référence au QR)
    let previousPointId: Int

    /// Distance depuis le point précédent (pour info rapide)
    let distanceFromPrevious: Float
    let timestamp: Date

    /// Initialisation complète avec chaînage
    init(id: Int, nom: String, relativeToQR: SIMD3<Float>, relativeToPrevious: SIMD3<Float>, previousPointId: Int, distanceFromPrevious: Float) {
        self.id = id
        self.nom = nom
        self.relativeX = relativeToQR.x
        self.relativeY = relativeToQR.y
        self.relativeZ = relativeToQR.z
        self.relativeToPreviousX = relativeToPrevious.x
        self.relativeToPreviousY = relativeToPrevious.y
        self.relativeToPreviousZ = relativeToPrevious.z
        self.previousPointId = previousPointId
        self.distanceFromPrevious = distanceFromPrevious
        self.timestamp = Date()
    }

    /// Initialisation complète (pour reconstruction depuis SQLite)
    init(id: Int, nom: String, relativeX: Float, relativeY: Float, relativeZ: Float,
         relativeToPreviousX: Float, relativeToPreviousY: Float, relativeToPreviousZ: Float,
         previousPointId: Int, distanceFromPrevious: Float, timestamp: Date) {
        self.id = id
        self.nom = nom
        self.relativeX = relativeX
        self.relativeY = relativeY
        self.relativeZ = relativeZ
        self.relativeToPreviousX = relativeToPreviousX
        self.relativeToPreviousY = relativeToPreviousY
        self.relativeToPreviousZ = relativeToPreviousZ
        self.previousPointId = previousPointId
        self.distanceFromPrevious = distanceFromPrevious
        self.timestamp = timestamp
    }

    /// Ancienne initialisation (compatibilité) - à supprimer après migration
    init(id: Int, nom: String, relativePosition: SIMD3<Float>, distanceFromPrevious: Float) {
        self.id = id
        self.nom = nom
        self.relativeX = relativePosition.x
        self.relativeY = relativePosition.y
        self.relativeZ = relativePosition.z
        // Par défaut, même valeur (pas de chaînage)
        self.relativeToPreviousX = relativePosition.x
        self.relativeToPreviousY = relativePosition.y
        self.relativeToPreviousZ = relativePosition.z
        self.previousPointId = 0
        self.distanceFromPrevious = distanceFromPrevious
        self.timestamp = Date()
    }

    /// Position relative au QR Code comme SIMD3
    var relativePosition: SIMD3<Float> {
        SIMD3<Float>(relativeX, relativeY, relativeZ)
    }

    /// Position relative au point précédent comme SIMD3
    var relativeToePrevious: SIMD3<Float> {
        SIMD3<Float>(relativeToPreviousX, relativeToPreviousY, relativeToPreviousZ)
    }
}