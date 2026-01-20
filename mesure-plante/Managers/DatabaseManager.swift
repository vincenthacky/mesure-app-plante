import Foundation
import SQLite3

/// Gestionnaire de base de données SQLite
final class DatabaseManager {
    static let shared = DatabaseManager()

    private var db: OpaquePointer?
    private let dbName = "mesure_plante.sqlite"

    private var dbURL: URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent(dbName)
    }

    private init() {
        openDatabase()
        createTables()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Database Setup

    private func openDatabase() {
        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            print("Erreur ouverture base de données: \(String(cString: sqlite3_errmsg(db)))")
        } else {
            print("Base de données ouverte: \(dbURL.path)")
        }
    }

    private func createTables() {
        // Table des sessions
        let createSessionsTable = """
        CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY,
            qr_code_id TEXT UNIQUE NOT NULL,
            plantation_name TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        """

        // Table des points
        let createPointsTable = """
        CREATE TABLE IF NOT EXISTS points (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_qr_code_id TEXT NOT NULL,
            point_number INTEGER NOT NULL,
            nom TEXT NOT NULL,
            relative_x REAL NOT NULL,
            relative_y REAL NOT NULL,
            relative_z REAL NOT NULL,
            distance_from_previous REAL NOT NULL,
            timestamp REAL NOT NULL,
            FOREIGN KEY (session_qr_code_id) REFERENCES sessions(qr_code_id) ON DELETE CASCADE
        );
        """

        // Index pour améliorer les performances
        let createIndex = """
        CREATE INDEX IF NOT EXISTS idx_points_session ON points(session_qr_code_id);
        """

        executeSQL(createSessionsTable)
        executeSQL(createPointsTable)
        executeSQL(createIndex)
    }

    private func executeSQL(_ sql: String) {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) != SQLITE_DONE {
                print("Erreur exécution SQL: \(String(cString: sqlite3_errmsg(db)))")
            }
        } else {
            print("Erreur préparation SQL: \(String(cString: sqlite3_errmsg(db)))")
        }
        sqlite3_finalize(statement)
    }

    // MARK: - Sessions CRUD

    /// Insère ou met à jour une session
    func saveSession(_ session: PlantSession) {
        print("💾 [DB] saveSession() appelé - QR ID: '\(session.qrCodeId)', Nom: '\(session.plantationName)'")

        let sql = """
        INSERT OR REPLACE INTO sessions (id, qr_code_id, plantation_name, latitude, longitude, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            let idString = session.id.uuidString
            let qrCodeId = session.qrCodeId
            let plantationName = session.plantationName

            idString.withCString { idCString in
                qrCodeId.withCString { qrIdCString in
                    plantationName.withCString { nameCString in
                        sqlite3_bind_text(statement, 1, idCString, -1, nil)
                        sqlite3_bind_text(statement, 2, qrIdCString, -1, nil)
                        sqlite3_bind_text(statement, 3, nameCString, -1, nil)
                        sqlite3_bind_double(statement, 4, session.latitude)
                        sqlite3_bind_double(statement, 5, session.longitude)
                        sqlite3_bind_double(statement, 6, session.createdAt.timeIntervalSince1970)
                        sqlite3_bind_double(statement, 7, session.updatedAt.timeIntervalSince1970)

                        if sqlite3_step(statement) == SQLITE_DONE {
                            print("✅ [DB] Session sauvegardée avec succès!")
                        } else {
                            print("❌ [DB] Erreur sauvegarde session: \(String(cString: sqlite3_errmsg(self.db)))")
                        }
                    }
                }
            }
        } else {
            print("❌ [DB] Erreur préparation SQL: \(String(cString: sqlite3_errmsg(db)))")
        }
        sqlite3_finalize(statement)
    }

    /// Récupère une session par QR Code ID
    func getSession(forQRCodeId qrCodeId: String) -> PlantSession? {
        print("🔍 [DB] getSession() appelé pour QR ID: '\(qrCodeId)'")

        let sql = "SELECT id, qr_code_id, plantation_name, latitude, longitude, created_at, updated_at FROM sessions WHERE qr_code_id = ?;"

        var statement: OpaquePointer?
        var session: PlantSession?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            qrCodeId.withCString { qrIdCString in
                sqlite3_bind_text(statement, 1, qrIdCString, -1, nil)

                if sqlite3_step(statement) == SQLITE_ROW {
                    let idString = String(cString: sqlite3_column_text(statement, 0))
                    let qrId = String(cString: sqlite3_column_text(statement, 1))
                    let name = String(cString: sqlite3_column_text(statement, 2))
                    let lat = sqlite3_column_double(statement, 3)
                    let lon = sqlite3_column_double(statement, 4)
                    let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
                    let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))

                    print("✅ [DB] Session trouvée: '\(name)' (QR ID: '\(qrId)')")

                    // Récupérer les points associés
                    let points = getPoints(forQRCodeId: qrId)
                    print("📊 [DB] Points récupérés: \(points.count)")

                    session = PlantSession(
                        id: UUID(uuidString: idString) ?? UUID(),
                        qrCodeId: qrId,
                        plantationName: name,
                        latitude: lat,
                        longitude: lon,
                        createdAt: createdAt,
                        updatedAt: updatedAt,
                        points: points
                    )
                } else {
                    print("⚠️ [DB] Aucune session trouvée pour QR ID: '\(qrCodeId)'")
                }
            }
        } else {
            print("❌ [DB] Erreur préparation SQL: \(String(cString: sqlite3_errmsg(db)))")
        }
        sqlite3_finalize(statement)
        return session
    }

    /// Récupère toutes les sessions
    func getAllSessions() -> [PlantSession] {
        let sql = "SELECT id, qr_code_id, plantation_name, latitude, longitude, created_at, updated_at FROM sessions ORDER BY updated_at DESC;"

        var statement: OpaquePointer?
        var sessions: [PlantSession] = []

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let idString = String(cString: sqlite3_column_text(statement, 0))
                let qrId = String(cString: sqlite3_column_text(statement, 1))
                let name = String(cString: sqlite3_column_text(statement, 2))
                let lat = sqlite3_column_double(statement, 3)
                let lon = sqlite3_column_double(statement, 4)
                let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
                let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))

                let points = getPoints(forQRCodeId: qrId)

                let session = PlantSession(
                    id: UUID(uuidString: idString) ?? UUID(),
                    qrCodeId: qrId,
                    plantationName: name,
                    latitude: lat,
                    longitude: lon,
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    points: points
                )
                sessions.append(session)
            }
        }
        sqlite3_finalize(statement)
        return sessions
    }

    /// Supprime une session et ses points
    func deleteSession(forQRCodeId qrCodeId: String) {
        // Supprimer les points d'abord
        deletePoints(forQRCodeId: qrCodeId)

        // Supprimer la session
        let sql = "DELETE FROM sessions WHERE qr_code_id = ?;"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, qrCodeId, -1, nil)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    // MARK: - Points CRUD

    /// Ajoute un point à une session
    func addPoint(_ point: SavedPlantPoint, toSessionWithQRCodeId qrCodeId: String) {
        print("💾 [DB] addPoint() appelé - QR ID: '\(qrCodeId)', Point: \(point.nom)")

        let sql = """
        INSERT INTO points (session_qr_code_id, point_number, nom, relative_x, relative_y, relative_z, distance_from_previous, timestamp)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            // Utiliser withCString pour éviter les problèmes de mémoire
            qrCodeId.withCString { qrIdCString in
                point.nom.withCString { nomCString in
                    sqlite3_bind_text(statement, 1, qrIdCString, -1, nil)
                    sqlite3_bind_int(statement, 2, Int32(point.id))
                    sqlite3_bind_text(statement, 3, nomCString, -1, nil)
                    sqlite3_bind_double(statement, 4, Double(point.relativeX))
                    sqlite3_bind_double(statement, 5, Double(point.relativeY))
                    sqlite3_bind_double(statement, 6, Double(point.relativeZ))
                    sqlite3_bind_double(statement, 7, Double(point.distanceFromPrevious))
                    sqlite3_bind_double(statement, 8, point.timestamp.timeIntervalSince1970)

                    if sqlite3_step(statement) == SQLITE_DONE {
                        print("✅ [DB] Point sauvegardé avec succès!")
                    } else {
                        print("❌ [DB] Erreur ajout point: \(String(cString: sqlite3_errmsg(self.db)))")
                    }
                }
            }
        } else {
            print("❌ [DB] Erreur préparation SQL: \(String(cString: sqlite3_errmsg(db)))")
        }
        sqlite3_finalize(statement)

        // Mettre à jour le timestamp de la session
        updateSessionTimestamp(forQRCodeId: qrCodeId)

        // Vérification: compter les points après insertion
        let count = getPoints(forQRCodeId: qrCodeId).count
        print("📊 [DB] Nombre de points pour '\(qrCodeId)' après insertion: \(count)")
    }

    /// Récupère tous les points d'une session
    func getPoints(forQRCodeId qrCodeId: String) -> [SavedPlantPoint] {
        let sql = "SELECT point_number, nom, relative_x, relative_y, relative_z, distance_from_previous, timestamp FROM points WHERE session_qr_code_id = ? ORDER BY point_number ASC;"

        var statement: OpaquePointer?
        var points: [SavedPlantPoint] = []

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            qrCodeId.withCString { qrIdCString in
                sqlite3_bind_text(statement, 1, qrIdCString, -1, nil)

                while sqlite3_step(statement) == SQLITE_ROW {
                    let pointNumber = Int(sqlite3_column_int(statement, 0))
                    let nom = String(cString: sqlite3_column_text(statement, 1))
                    let relX = Float(sqlite3_column_double(statement, 2))
                    let relY = Float(sqlite3_column_double(statement, 3))
                    let relZ = Float(sqlite3_column_double(statement, 4))
                    let distance = Float(sqlite3_column_double(statement, 5))
                    let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))

                    let point = SavedPlantPoint(
                        id: pointNumber,
                        nom: nom,
                        relativeX: relX,
                        relativeY: relY,
                        relativeZ: relZ,
                        distanceFromPrevious: distance,
                        timestamp: timestamp
                    )
                    points.append(point)
                }
            }
        }
        sqlite3_finalize(statement)
        return points
    }

    /// Supprime tous les points d'une session
    private func deletePoints(forQRCodeId qrCodeId: String) {
        let sql = "DELETE FROM points WHERE session_qr_code_id = ?;"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, qrCodeId, -1, nil)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    /// Met à jour le timestamp d'une session
    private func updateSessionTimestamp(forQRCodeId qrCodeId: String) {
        let sql = "UPDATE sessions SET updated_at = ? WHERE qr_code_id = ?;"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_double(statement, 1, Date().timeIntervalSince1970)
            sqlite3_bind_text(statement, 2, qrCodeId, -1, nil)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    // MARK: - Stats

    /// Nombre total de sessions
    var totalSessionsCount: Int {
        let sql = "SELECT COUNT(*) FROM sessions;"
        var statement: OpaquePointer?
        var count = 0

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        return count
    }

    /// Nombre total de points
    var totalPointsCount: Int {
        let sql = "SELECT COUNT(*) FROM points;"
        var statement: OpaquePointer?
        var count = 0

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        return count
    }

    // MARK: - Maintenance

    /// Supprime toutes les données
    func deleteAllData() {
        executeSQL("DELETE FROM points;")
        executeSQL("DELETE FROM sessions;")
    }
}
