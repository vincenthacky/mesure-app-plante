import Foundation
import ARKit

/// Structure représentant un point de plantation placé dans l'espace AR
struct PlantPoint: Identifiable {
    let id: Int
    let nom: String
    let anchor: ARAnchor
    let position: SIMD3<Float>
    let timestamp: Date

    init(id: Int, anchor: ARAnchor, position: SIMD3<Float>) {
        self.id = id
        self.nom = "Arbre \(id)"
        self.anchor = anchor
        self.position = position
        self.timestamp = Date()
    }
}
