import UIKit

/// Gestionnaire des retours haptiques
final class HapticManager {
    static let shared = HapticManager()

    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let notificationGenerator = UINotificationFeedbackGenerator()

    private init() {
        impactGenerator.prepare()
        notificationGenerator.prepare()
    }

    /// Vibration de succès (point placé)
    func success() {
        notificationGenerator.notificationOccurred(.success)
    }

    /// Vibration d'erreur
    func error() {
        notificationGenerator.notificationOccurred(.error)
    }

    /// Vibration d'avertissement
    func warning() {
        notificationGenerator.notificationOccurred(.warning)
    }

    /// Vibration légère (interaction)
    func impact() {
        impactGenerator.impactOccurred()
    }
}
