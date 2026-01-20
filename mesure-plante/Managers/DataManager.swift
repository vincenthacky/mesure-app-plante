import Foundation

/// Gestionnaire de persistance des données (utilise SQLite)
final class DataManager {
    static let shared = DataManager()

    private let database = DatabaseManager.shared

    private init() {}

    // MARK: - Sessions

    /// Charge toutes les sessions sauvegardées
    func loadAllSessions() -> [PlantSession] {
        return database.getAllSessions()
    }

    /// Récupère la session pour un QR Code donné (par son ID)
    func getSession(forQRCodeId qrCodeId: String) -> PlantSession? {
        return database.getSession(forQRCodeId: qrCodeId)
    }

    /// Crée ou met à jour une session
    func saveSession(_ session: PlantSession) {
        database.saveSession(session)
    }

    /// Ajoute un point à une session existante
    func addPoint(toSessionWithQRCodeId qrCodeId: String, point: SavedPlantPoint) {
        database.addPoint(point, toSessionWithQRCodeId: qrCodeId)
    }

    /// Supprime une session
    func deleteSession(withQRCodeId qrCodeId: String) {
        database.deleteSession(forQRCodeId: qrCodeId)
    }

    /// Supprime toutes les sessions
    func deleteAllSessions() {
        database.deleteAllData()
    }

    // MARK: - Stats

    /// Nombre total de sessions
    var totalSessionsCount: Int {
        return database.totalSessionsCount
    }

    /// Nombre total de points placés (toutes sessions)
    var totalPointsCount: Int {
        return database.totalPointsCount
    }
}
