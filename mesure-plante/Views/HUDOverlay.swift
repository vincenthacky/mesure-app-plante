import SwiftUI

/// Overlay HUD affichant les informations de mesure
struct HUDOverlay: View {
    let referenceName: String
    let distance: Float
    let surfaceCount: Int
    let pointCount: Int
    let statusMessage: String

    var body: some View {
        VStack(spacing: 0) {
            // HUD en haut
            VStack(alignment: .leading, spacing: 8) {
                HUDRow(icon: "mappin.circle.fill", label: "Réf", value: referenceName)
                HUDRow(icon: "ruler.fill", label: "Distance", value: String(format: "%.2f m", distance))
                HUDRow(icon: "square.stack.3d.up.fill", label: "Surfaces", value: "\(surfaceCount)")
                HUDRow(icon: "leaf.fill", label: "Points placés", value: "\(pointCount)")
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding()

            Spacer()

            // Message de statut en bas
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
                    .padding(.bottom, 8)
            }
        }
    }
}

/// Ligne d'information du HUD
struct HUDRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.green)
                .frame(width: 24)

            Text(label + ":")
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .font(.system(.body, design: .rounded))
    }
}

#Preview {
    ZStack {
        Color.black
        HUDOverlay(
            referenceName: "Plantation-aka",
            distance: 3.24,
            surfaceCount: 3,
            pointCount: 5,
            statusMessage: "Arbre 5 placé"
        )
    }
}
