import SwiftUI

public struct UberTestOfferView: View {
    @ObservedObject private var store: UberTestStore
    @ObservedObject private var receiver: UberTestReceiverState
    @State private var actualFare = ""
    @State private var actualTripMinutes = ""
    @State private var actualTripKm = ""
    @State private var nextWaitMinutes = ""
    @State private var nextFare = ""
    private let signOut: () -> Void
    public init(store: UberTestStore, receiver: UberTestReceiverState, signOut: @escaping () -> Void) { self.store = store; self.receiver = receiver; self.signOut = signOut }
    public var body: some View {
        ZStack {
            LinearGradient(colors: [.black, Color(red: 0.08, green: 0.10, blue: 0.13)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            if let trip = store.activeTrip {
                activeTripView(trip)
            } else if let offer = store.queue.current {
                VStack(spacing: 18) {
                    HStack { Text("UBER TEST").font(.caption.weight(.bold)).tracking(2); Spacer(); Text(receiver.isActive ? "● ESTE IPHONE ACTIVO" : "ESTE IPHONE ESTÁ INACTIVO").font(.caption2.weight(.bold)).foregroundStyle(receiver.isActive ? .green : .red) }.foregroundStyle(.white.opacity(0.8))
                    VStack(alignment: .leading, spacing: 3) { Text("Conductor: \(receiver.displayName)"); Text("Identificador: \(receiver.employeeNumber)"); Text(receiver.receiverState).font(.caption.weight(.bold)); Text(receiver.linkState).font(.caption.weight(.bold)).foregroundStyle(receiver.linkState == "DORI ENLAZADO" ? .green : .orange) }.frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.white.opacity(0.85))
                    Text("Nueva solicitud").font(.title2.weight(.semibold)).foregroundStyle(.white)
                    Text(offer.service).font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text("$\(offer.fare.description) \(offer.currency)").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 12) {
                        metric("RECÓGIDA", offer.pickup)
                        if let pickupMinutes = offer.pickupMinutes {
                            metric("LLEGADA", String(format: "%.0f min · %.1f km", pickupMinutes, offer.pickupDistanceKm))
                        } else {
                            metric("DISTANCIA A RECOGIDA", String(format: "%.1f km", offer.pickupDistanceKm))
                        }
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
            } else { VStack(spacing: 20) { Text("EN ESPERA DE VIAJES").font(.headline).foregroundStyle(.white.opacity(0.7)); Text("Conductor: \(receiver.displayName)").foregroundStyle(.white); Text("Identificador: \(receiver.employeeNumber)").foregroundStyle(.white.opacity(0.8)); Text(receiver.linkState).font(.caption.weight(.bold)).foregroundStyle(.orange); Button("CERRAR SESIÓN", action: signOut).buttonStyle(.bordered).tint(.red) } }
        }
    }
    private func activeTripView(_ trip: UberTestOffer) -> some View {
        let fare = Double(actualFare)
        let minutes = Double(actualTripMinutes)
        let km = Double(actualTripKm)
        let canFinish = (fare ?? 0) > 0 && (minutes ?? 0) > 0 && (km ?? 0) > 0
        return VStack(spacing: 18) {
            Text("VIAJE TEST ACTIVO").font(.caption.weight(.bold)).tracking(2).foregroundStyle(.green)
            Text(trip.service).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text("Oferta \(trip.fare.description) \(trip.currency) · \(Int(trip.tripDurationMinutes.rounded())) min").foregroundStyle(.white.opacity(0.75))
            VStack(spacing: 12) {
                observedField("TARIFA REAL", text: $actualFare, unit: "MXN")
                observedField("MINUTOS REALES", text: $actualTripMinutes, unit: "min")
                observedField("KM REALES", text: $actualTripKm, unit: "km")
                observedField("ESPERA SIGUIENTE", text: $nextWaitMinutes, unit: "min · opcional")
                observedField("TARIFA SIGUIENTE", text: $nextFare, unit: "MXN · opcional")
            }.padding().background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            Text("Captura sólo datos observados. DORI no inventa resultados del viaje.").font(.caption).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
            Button("TERMINAR VIAJE TEST") {
                guard let fare, let minutes, let km else { return }
                store.completeTrip(observation: UberTestTripObservation(
                    actualFare: fare,
                    actualTripMinutes: minutes,
                    actualTripKm: km,
                    nextWaitMinutes: Double(nextWaitMinutes),
                    nextFare: Double(nextFare)
                ))
                actualFare = ""; actualTripMinutes = ""; actualTripKm = ""; nextWaitMinutes = ""; nextFare = ""
            }
            .buttonStyle(OfferButtonStyle(color: .green))
            .disabled(!canFinish)
            .opacity(canFinish ? 1 : 0.45)
        }.padding(24)
    }
    private func observedField(_ title: String, text: Binding<String>, unit: String) -> some View {
        HStack { Text(title).font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.65)); Spacer(); TextField("0", text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90).textFieldStyle(.roundedBorder); Text(unit).font(.caption2).foregroundStyle(.white.opacity(0.55)).frame(width: 90, alignment: .leading) }
    }
    private func metric(_ title: String, _ value: String) -> some View { VStack(alignment: .leading) { Text(title).font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.55)); Text(value).font(.body.weight(.medium)).foregroundStyle(.white) } }
}
private struct OfferButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View { configuration.label.font(.headline.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 16).background(color.opacity(configuration.isPressed ? 0.55 : 0.9), in: Capsule()).foregroundStyle(.white) }
}
