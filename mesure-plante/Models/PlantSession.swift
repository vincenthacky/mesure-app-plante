import Foundation

/// Session de plantation avec tous les points placés (positions relatives au QR Code)
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
}

/// Point sauvegardé avec position RELATIVE au QR Code
struct SavedPlantPoint: Codable, Identifiable {
    let id: Int
    let nom: String
    /// Position relative au QR Code (le QR Code est à 0,0,0)
    let relativeX: Float
    let relativeY: Float
    let relativeZ: Float
    /// Distance depuis le point précédent (pour info)
    let distanceFromPrevious: Float
    let timestamp: Date

    /// Initialisation depuis les coordonnées relatives
    init(id: Int, nom: String, relativePosition: SIMD3<Float>, distanceFromPrevious: Float) {
        self.id = id
        self.nom = nom
        self.relativeX = relativePosition.x
        self.relativeY = relativePosition.y
        self.relativeZ = relativePosition.z
        self.distanceFromPrevious = distanceFromPrevious
        self.timestamp = Date()
    }

    /// Initialisation complète (pour reconstruction depuis SQLite)
    init(id: Int, nom: String, relativeX: Float, relativeY: Float, relativeZ: Float, distanceFromPrevious: Float, timestamp: Date) {
        self.id = id
        self.nom = nom
        self.relativeX = relativeX
        self.relativeY = relativeY
        self.relativeZ = relativeZ
        self.distanceFromPrevious = distanceFromPrevious
        self.timestamp = timestamp
    }

    /// Position relative comme SIMD3
    var relativePosition: SIMD3<Float> {
        SIMD3<Float>(relativeX, relativeY, relativeZ)
    }
}
