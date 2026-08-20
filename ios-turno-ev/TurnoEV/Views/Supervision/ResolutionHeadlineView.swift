import SwiftUI

/// How the Resolver ausencias card speaks. A normal day says one line; only a case the
/// engine could not close asks the supervisor for anything.

/// One line of the card: an icon, a colour and a very short sentence.
struct ResolutionHeadlineLine: Identifiable {
    let id: String
    let text: String
    let symbol: String
    let tint: Color
    var isLead: Bool = false
}

extension ResolutionHeadline {
    var isEscalated: Bool {
        if case .escalated = self { return true }
        return false
    }

    var symbol: String {
        switch self {
        case .clear: "checkmark.seal.fill"
        case .resolving: "gearshape.2.fill"
        case .resolved: "checkmark.seal.fill"
        case .escalated: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .clear, .resolved: SupTone.good
        case .resolving: SupTone.cool
        case .escalated: SupTone.warn
        }
    }

    var lines: [ResolutionHeadlineLine] {
        switch self {
        case .clear:
            return [
                ResolutionHeadlineLine(
                    id: "clear",
                    text: "Plantilla completa",
                    symbol: "checkmark.circle.fill",
                    tint: SupTone.good,
                    isLead: true
                ),
                ResolutionHeadlineLine(
                    id: "clear-detail",
                    text: "Sin acciones necesarias",
                    symbol: "minus",
                    tint: Palette.textMuted
                ),
            ]

        case .resolving(let absences, let reserves, let resolved):
            var lines = [
                ResolutionHeadlineLine(
                    id: "absences",
                    text: absences == 1 ? "1 ausencia detectada" : "\(absences) ausencias detectadas",
                    symbol: "person.fill.xmark",
                    tint: SupTone.bad,
                    isLead: true
                ),
                ResolutionHeadlineLine(
                    id: "searching",
                    text: absences == 1 ? "Buscando sustituto…" : "\(absences) en proceso de solución",
                    symbol: "gearshape.2.fill",
                    tint: SupTone.cool
                ),
            ]
            if resolved > 0 {
                lines.append(
                    ResolutionHeadlineLine(
                        id: "resolved",
                        text: resolved == 1 ? "1 resuelta" : "\(resolved) resueltas",
                        symbol: "checkmark.circle.fill",
                        tint: SupTone.good
                    )
                )
            }
            lines.append(
                ResolutionHeadlineLine(
                    id: "reserves",
                    text: reserves == 1
                        ? "1 unidad de reserva disponible"
                        : "\(reserves) unidades de reserva disponibles",
                    symbol: "car.side.fill",
                    tint: reserves > 0 ? SupTone.cool : Palette.textMuted
                )
            )
            return lines

        case .resolved(let count, let substitute, let eta):
            var lines = [
                ResolutionHeadlineLine(
                    id: "resolved",
                    text: count == 1 ? "Ausencia resuelta" : "\(count) ausencias resueltas",
                    symbol: "checkmark.circle.fill",
                    tint: SupTone.good,
                    isLead: true
                )
            ]
            if let substitute {
                lines.append(
                    ResolutionHeadlineLine(
                        id: "substitute",
                        text: "Sustituto asignado · \(substitute)",
                        symbol: "person.fill.checkmark",
                        tint: Palette.textMuted
                    )
                )
            }
            if let eta {
                lines.append(
                    ResolutionHeadlineLine(
                        id: "eta",
                        text: "ETA \(Fmt.clock(eta))",
                        symbol: "clock.fill",
                        tint: Palette.textMuted
                    )
                )
            }
            return lines

        case .escalated(let count):
            return [
                ResolutionHeadlineLine(
                    id: "escalated",
                    text: count == 1 ? "Intervención requerida" : "\(count) casos requieren intervención",
                    symbol: "exclamationmark.triangle.fill",
                    tint: SupTone.warn,
                    isLead: true
                ),
                ResolutionHeadlineLine(
                    id: "escalated-detail",
                    text: "El motor no pudo resolverlo solo",
                    symbol: "hand.raised.fill",
                    tint: Palette.textMuted
                ),
            ]
        }
    }
}
