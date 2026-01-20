import Foundation

/// Structure représentant les données d'un QR Code de plantation
struct QRCodeData: Codable, Identifiable {
    let id: String
    let nom: String
    let lat: Double
    let lon: Double

    /// Valide que toutes les données requises sont présentes et valides
    var isValid: Bool {
        return !id.isEmpty && !nom.isEmpty
    }

    /// Crée une instance à partir d'une chaîne JSON
    static func from(jsonString: String) -> QRCodeData? {
        guard let data = jsonString.data(using: .utf8) else { return nil }

        do {
            let decoder = JSONDecoder()
            let qrData = try decoder.decode(QRCodeData.self, from: data)
            return qrData.isValid ? qrData : nil
        } catch {
            print("Erreur de décodage QR Code: \(error)")
            return nil
        }
    }
}
