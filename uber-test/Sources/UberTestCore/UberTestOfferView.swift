import SwiftUI

public struct UberTestOfferView: View {
    @ObservedObject private var store: UberTestStore
    public init(store: UberTestStore) { self.store = store }
    public var body: some View {
        ZStack {
            LinearGradient(colors: [.black, Color(red: 0.08, green: 0.10, blue: 0.13)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            if let offer = store.queue.current {
                VStack(spacing: 18) {
                    Text("UBER TEST").font(.caption.weight(.bold)).tracking(2).foregroundStyle(.white.opacity(0.65))
                    Text("Nueva solicitud").font(.title2.weight(.semibold)).foregroundStyle(.white)
                    Text(offer.service).font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text("$\(offer.fare.description) \(offer.currency)").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 12) {
                        metric("RECÓGIDA", offer.pickup)
                        metric("DISTANCIA A RECOGIDA", String(format: "%.1f km", offer.pickupDistanceKm))
                        metric("VIAJE", String(format: "%.0f min · %.1f km", offer.tripDurationMinutes, offer.tripDistanceKm))
                        if let rating = offer.riderRating { metric("RATING", String(format: "%.2f ★", rating)) }
                    }.padding().background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                    ProgressView(value: Double(store.remainingSeconds), total: Double(max(offer.expiresAfterSeconds, 1))).tint(.orange)
                    Text("\(store.remainingSeconds)s").font(.headline.monospacedDigit()).foregroundStyle(.orange)
                    HStack(spacing: 14) {
                        Button("DESCARTAR", action: store.discard).buttonStyle(OfferButtonStyle(color: .gray))
                        Button("ACEPTAR", action: store.accept).buttonStyle(OfferButtonStyle(color: .green))
                    }
                }.padding(24)
            } else { Text("EN ESPERA DE VIAJES").font(.headline).foregroundStyle(.white.opacity(0.7)) }
        }
    }
    private func metric(_ title: String, _ value: String) -> some View { VStack(alignment: .leading) { Text(title).font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.55)); Text(value).font(.body.weight(.medium)).foregroundStyle(.white) } }
}
private struct OfferButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View { configuration.label.font(.headline.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 16).background(color.opacity(configuration.isPressed ? 0.55 : 0.9), in: Capsule()).foregroundStyle(.white) }
}
