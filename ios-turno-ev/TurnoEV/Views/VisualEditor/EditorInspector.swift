import SwiftUI
import UIKit

/// Properties panel of one element: everything the administrator can change without
/// writing a single instruction. Split in the same seven groups on every element, so the
/// place to look for a control is always the same.
struct EditorInspectorView: View {
    let block: EditorBlock

    @Environment(VisualEditorStore.self) private var editor
    @Environment(\.dismiss) private var dismiss

    @State private var tab: Tab = .content
    @State private var title: String = ""
    @State private var subtitle: String = ""
    @State private var isDeleteConfirmPresented: Bool = false
    @State private var isResetConfirmPresented: Bool = false
    @State private var loaded: Bool = false

    private enum Tab: String, CaseIterable, Identifiable {
        case content
        case design
        case size
        case data
        case visualization
        case behaviour
        case permissions

        var id: String { rawValue }

        var label: String {
            switch self {
            case .content: "Contenido"
            case .design: "Diseño"
            case .size: "Tamaño"
            case .data: "Datos"
            case .visualization: "Visualización"
            case .behaviour: "Comportamiento"
            case .permissions: "Permisos"
            }
        }

        var symbol: String {
            switch self {
            case .content: "textformat"
            case .design: "paintpalette.fill"
            case .size: "arrow.up.left.and.arrow.down.right"
            case .data: "cylinder.split.1x2.fill"
            case .visualization: "chart.bar.fill"
            case .behaviour: "slider.horizontal.3"
            case .permissions: "lock.fill"
            }
        }
    }

    private var screen: EditorScreen { editor.selection?.screen ?? .driverGoals }
    private var ref: EditorElementRef { block.ref }
    private var rules: EditorOverride { editor.override(screen, ref.id) }

    var body: some View {
        NavigationStack {
            ZStack {
                LabBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        tabs

                        switch tab {
                        case .content: contentSection
                        case .design: designSection
                        case .size: sizeSection
                        case .data: dataSection
                        case .visualization: visualizationSection
                        case .behaviour: behaviourSection
                        case .permissions: permissionsSection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Propiedades")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(LabTone.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") { dismiss() }
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(LabTone.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
        .presentationBackground(LabTone.canvas)
        .preferredColorScheme(.dark)
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        title = rules.title ?? ref.title
        subtitle = rules.subtitle ?? (ref.subtitle ?? "")
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: ref.kind.symbol)
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(LabTone.accent)
                    .frame(width: 34, height: 34)
                    .background(LabTone.accent.opacity(0.13), in: .rect(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text(rules.title ?? ref.title)
                        .font(.system(.subheadline, weight: .black))
                        .foregroundStyle(.white)
                    Text("\(ref.kind.label) · \(screen.label)")
                        .font(.caption2)
                        .foregroundStyle(LabTone.muted)
                }
                Spacer(minLength: 0)
                if ref.isCritical {
                    LabChip(text: "Crítico", symbol: "lock.fill", tint: LabTone.bad)
                }
            }

            Text(rules.isPristine ? "Sin cambios respecto al diseño original." : "Cambios: \(rules.summary).")
                .font(.caption2)
                .foregroundStyle(LabTone.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .labPanel()
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(Tab.allCases) { item in
                    Button {
                        tab = item
                    } label: {
                        LabChip(text: item.label, symbol: item.symbol, tint: LabTone.accent, filled: tab == item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    // MARK: - Content

    @ViewBuilder
    private var contentSection: some View {
        if block.showsHeader || ref.isAdded {
            group("Textos") {
                LabField(label: "Título", text: $title)
                LabField(label: "Subtítulo o mensaje", text: $subtitle)

                HStack(spacing: 8) {
                    Button("Guardar texto") {
                        editor.setTitle(title, screen: screen, element: ref)
                        editor.setSubtitle(subtitle, screen: screen, element: ref)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                    .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))

                    Button("Texto original") {
                        title = ref.title
                        subtitle = ref.subtitle ?? ""
                        editor.setTitle(ref.title, screen: screen, element: ref)
                        editor.setSubtitle(ref.subtitle ?? "", screen: screen, element: ref)
                    }
                    .buttonStyle(LabButtonStyle(kind: .ghost, isCompact: true))
                }

                Text("El texto se guarda de inmediato en el entorno de pruebas. Producción no cambia.")
                    .font(.caption2)
                    .foregroundStyle(LabTone.muted)
            }
        } else {
            group("Textos") {
                Text("Este elemento dibuja su propio contenido, así que sus frases no se editan desde aquí. Los mensajes del sistema que muestra se cambian en «Mensajes del sistema» del editor.")
                    .font(.footnote)
                    .foregroundStyle(LabTone.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Design

    @ViewBuilder
    private var designSection: some View {
        if ref.supportsCardLibrary {
            group("Modelo de tarjeta") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
                    ForEach(EditorCardModel.allCases) { model in
                        Button {
                            editor.setCardModel(model, screen: screen, element: ref)
                        } label: {
                            EditorCardThumbnail(
                                model: model,
                                isSelected: (rules.cardModel ?? ref.defaultCardModel) == model
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Cambiar el modelo no toca la fuente de datos ni la lógica: el número sigue siendo el mismo.")
                    .font(.caption2)
                    .foregroundStyle(LabTone.muted)
            }
        } else {
            group("Modelo") {
                Text("Este elemento no forma parte de la biblioteca de tarjetas. Puedes moverlo, redimensionarlo, ocultarlo o eliminarlo del diseño.")
                    .font(.footnote)
                    .foregroundStyle(LabTone.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        group("Espacio inferior") {
            LabOptionRow(
                label: "Separación",
                options: EditorSpacing.allCases,
                selection: Binding(
                    get: { rules.spacing ?? .normal },
                    set: { editor.setSpacing($0, screen: screen, element: ref) }
                ),
                title: \.label
            )
        }
    }

    // MARK: - Size

    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            group("Ancho") {
                LabOptionRow(
                    label: "Columnas de la cuadrícula",
                    options: EditorWidth.allCases,
                    selection: Binding(
                        get: { rules.width ?? ref.defaultWidth },
                        set: { editor.setWidth($0, screen: screen, element: ref) }
                    ),
                    title: { "\($0.label) · \($0.shortLabel)" }
                )
                Text("La pantalla tiene cuatro columnas. Un elemento nunca puede salirse de ellas, así que el diseño sigue siendo responsive.")
                    .font(.caption2)
                    .foregroundStyle(LabTone.muted)
            }

            group("Alto") {
                LabOptionRow(
                    label: "Altura mínima",
                    options: EditorHeight.allCases,
                    selection: Binding(
                        get: { rules.height ?? .automatic },
                        set: { editor.setHeight($0, screen: screen, element: ref) }
                    ),
                    title: \.label
                )
            }

            group("Posición") {
                Text("Mantén presionado el elemento en la pantalla y arrástralo. Una guía marca dónde va a caer y los demás elementos se reacomodan solos.")
                    .font(.footnote)
                    .foregroundStyle(LabTone.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Data

    @ViewBuilder
    private var dataSection: some View {
        if ref.supportsDataSource {
            group("Fuente de datos") {
                if let current = rules.metric ?? ref.metric {
                    LabRow(
                        title: current.label,
                        subtitle: "Fuente actual",
                        symbol: current.symbol,
                        tint: LabTone.good
                    )
                }

                ForEach(EditorMetric.scope(for: screen)) { metric in
                    Button {
                        editor.setMetric(metric, screen: screen, element: ref)
                    } label: {
                        LabRow(
                            title: metric.label,
                            detail: (rules.metric ?? ref.metric) == metric ? "Seleccionada" : nil,
                            symbol: metric.symbol,
                            tint: (rules.metric ?? ref.metric) == metric ? LabTone.accent : LabTone.muted
                        )
                    }
                    .buttonStyle(.plain)
                }

                Text("Solo métricas de esta lista. El editor no puede consultar la base de datos por su cuenta.")
                    .font(.caption2)
                    .foregroundStyle(LabTone.muted)
            }
        } else {
            group("Fuente de datos") {
                Text("Este elemento está atado a la lógica de su pantalla y no admite cambio de métrica. Duplica un indicador si necesitas ver otro dato aquí.")
                    .font(.footnote)
                    .foregroundStyle(LabTone.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Visualization

    @ViewBuilder
    private var visualizationSection: some View {
        if case .chart(let series) = block.content {
            let options = EditorChartKind.available(for: series)
            group("Tipo de gráfico") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
                    ForEach(options) { kind in
                        Button {
                            editor.setChartKind(kind, screen: screen, element: ref)
                        } label: {
                            EditorChartThumbnail(
                                kind: kind,
                                series: series,
                                isSelected: (rules.chartKind ?? ref.defaultChartKind) == kind
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Solo aparecen las visualizaciones que estos datos admiten: \(series.points.count) puntos\(series.totalGoal != nil ? " con meta" : "")\(series.isComposition ? " que suman un total" : "").")
                    .font(.caption2)
                    .foregroundStyle(LabTone.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            group("Configuración") {
                LabToggleRow(
                    title: "Mostrar valores",
                    isOn: Binding(
                        get: { rules.showsValues ?? true },
                        set: { editor.setChartOption(screen: screen, element: ref, values: $0) }
                    )
                )
                LabToggleRow(
                    title: "Mostrar leyenda",
                    isOn: Binding(
                        get: { rules.showsLegend ?? false },
                        set: { editor.setChartOption(screen: screen, element: ref, legend: $0) }
                    )
                )
                LabToggleRow(
                    title: "Mostrar etiquetas",
                    isOn: Binding(
                        get: { rules.showsLabels ?? true },
                        set: { editor.setChartOption(screen: screen, element: ref, labels: $0) }
                    )
                )
                Text("Los datos originales no se pueden modificar desde el editor visual.")
                    .font(.caption2)
                    .foregroundStyle(LabTone.muted)
            }
        } else {
            group("Visualización") {
                Text("Este elemento no representa una serie de datos, así que no hay gráficos compatibles que ofrecer.")
                    .font(.footnote)
                    .foregroundStyle(LabTone.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Behaviour

    private var behaviourSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            group("Visibilidad") {
                LabToggleRow(
                    title: "Ocultar de esta interfaz",
                    subtitle: "Deja de mostrarse. Su lógica y sus datos siguen intactos.",
                    isOn: Binding(
                        get: { rules.isHidden },
                        set: { editor.setHidden($0, screen: screen, element: ref) }
                    )
                )
            }

            if ref.supportsDuplicate || ref.isAdded {
                group("Duplicar") {
                    Button("Duplicar elemento") {
                        editor.duplicate(element: ref, screen: screen, order: 999)
                        dismiss()
                    }
                    .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
                    Text("La copia aparece al final de la pantalla y puedes apuntarla a otro dato de la lista controlada.")
                        .font(.caption2)
                        .foregroundStyle(LabTone.muted)
                }
            }

            group("Restablecer y eliminar") {
                Button("Restablecer diseño original") { isResetConfirmPresented = true }
                    .buttonStyle(LabButtonStyle(kind: .ghost, isCompact: true))

                Button(ref.isCritical ? "Elemento crítico: no se puede eliminar" : "Eliminar del diseño") {
                    isDeleteConfirmPresented = true
                }
                .buttonStyle(LabButtonStyle(kind: .danger, isCompact: true))
                .disabled(ref.isCritical)

                Text("Eliminar solo quita su representación visual de esta interfaz. No borra datos, tablas, registros ni lógica.")
                    .font(.caption2)
                    .foregroundStyle(LabTone.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .confirmationDialog(
                editor.message("confirm_delete_element")?.text ?? "¿Deseas eliminar este elemento de esta interfaz?",
                isPresented: $isDeleteConfirmPresented,
                titleVisibility: .visible
            ) {
                Button("Eliminar", role: .destructive) {
                    editor.delete(screen: screen, element: ref)
                    dismiss()
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text(ref.supportsDataSource
                     ? "Podrás restaurarlo desde «Elementos ocultos y eliminados» del editor."
                     : "Este elemento alimenta otras vistas de la pantalla. Al quitarlo, la información que muestra deja de verse aquí.")
            }
            .confirmationDialog(
                "¿Restablecer el diseño original de este elemento?",
                isPresented: $isResetConfirmPresented,
                titleVisibility: .visible
            ) {
                Button("Restablecer", role: .destructive) {
                    editor.resetElement(screen: screen, element: ref)
                    dismiss()
                }
                Button("Cancelar", role: .cancel) {}
            }
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        group("Permisos del elemento") {
            permissionRow(
                "Se puede mover",
                allowed: !ref.isCritical,
                detail: ref.isCritical ? "Los elementos críticos conservan su lugar." : "Arrástralo a cualquier posición de la cuadrícula."
            )
            permissionRow("Se puede ocultar", allowed: !ref.isCritical, detail: "Sin afectar su lógica.")
            permissionRow(
                "Se puede eliminar",
                allowed: !ref.isCritical,
                detail: ref.isCritical
                    ? "Emergencia, finalizar turno, autorizaciones y seguridad nunca se eliminan."
                    : "Solo su representación visual."
            )
            permissionRow("Cambia de tamaño", allowed: true, detail: "Dentro de la cuadrícula de cuatro columnas.")
            permissionRow("Cambia de datos", allowed: ref.supportsDataSource, detail: "Lista controlada de métricas.")

            Text("Visible para el rol \(screen.role.label). El editor nunca cambia los permisos de nadie: solo describe cómo se ve su pantalla.")
                .font(.caption2)
                .foregroundStyle(LabTone.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func permissionRow(_ title: String, allowed: Bool, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: allowed ? "checkmark.circle.fill" : "lock.fill")
                .font(.system(.caption, weight: .bold))
                .foregroundStyle(allowed ? LabTone.good : LabTone.bad)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(LabTone.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .labFlat()
    }

    // MARK: - Shell

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            LabCaps(text: title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .labPanel()
    }
}

// MARK: - Thumbnails

/// Miniature of a card model, so the model is picked by looking, not by reading.
struct EditorCardThumbnail: View {
    let model: EditorCardModel
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EditorCardView(
                model: model,
                title: "Vehículos activos",
                value: "42",
                caption: "de 48 instalados",
                progress: 0.72,
                symbol: "car.side.fill",
                tint: LabTone.accent
            )
            .scaleEffect(0.78, anchor: .topLeading)
            .frame(height: 74, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .allowsHitTesting(false)

            HStack(spacing: 5) {
                Text("MODELO \(model.letter)")
                    .font(.system(size: 9, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(isSelected ? LabTone.accent : LabTone.muted)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(LabTone.accent)
                }
            }
            Text(model.label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LabTone.raised.opacity(0.55), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? LabTone.accent : LabTone.hairline, lineWidth: isSelected ? 1.6 : 1)
        }
    }
}

/// Miniature of a chart shape drawn with the real series.
struct EditorChartThumbnail: View {
    let kind: EditorChartKind
    let series: EditorSeries
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EditorChartView(
                kind: kind,
                series: series,
                options: EditorChartOptions(showsValues: false, showsLegend: false, showsLabels: false, height: 52),
                tint: LabTone.accent
            )
            .frame(height: 62, alignment: .center)
            .clipped()
            .allowsHitTesting(false)

            HStack(spacing: 5) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 9, weight: .bold))
                Text(kind.label)
                    .font(.system(size: 10, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .foregroundStyle(isSelected ? LabTone.accent : LabTone.muted)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LabTone.raised.opacity(0.55), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? LabTone.accent : LabTone.hairline, lineWidth: isSelected ? 1.6 : 1)
        }
    }
}

// MARK: - Component library

/// Catalogue of components that can be dropped into an existing screen. Every one of them
/// has to be pointed at a metric of the controlled list before it can be added.
struct EditorComponentLibraryView: View {
    let screen: EditorScreen

    @Environment(VisualEditorStore.self) private var editor
    @Environment(\.dismiss) private var dismiss

    @State private var kind: EditorElementKind = .kpi
    @State private var metric: EditorMetric = .earningsToday

    private let catalogue: [EditorElementKind] = [.kpi, .card, .progress, .notice, .text, .separator]

    var body: some View {
        NavigationStack {
            ZStack {
                LabBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 11) {
                            LabCaps(text: "Categoría")
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
                                ForEach(catalogue, id: \.self) { item in
                                    Button {
                                        kind = item
                                    } label: {
                                        VStack(spacing: 6) {
                                            Image(systemName: item.symbol)
                                                .font(.system(.footnote, weight: .bold))
                                            Text(item.label)
                                                .font(.system(size: 10, weight: .bold))
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.7)
                                        }
                                        .foregroundStyle(kind == item ? LabTone.canvas : LabTone.muted)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 13)
                                        .background(kind == item ? LabTone.accent : LabTone.raised.opacity(0.6), in: .rect(cornerRadius: 14))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(14)
                        .labPanel()

                        VStack(alignment: .leading, spacing: 11) {
                            LabCaps(text: "Fuente de datos")
                            ForEach(EditorMetric.scope(for: screen)) { option in
                                Button {
                                    metric = option
                                } label: {
                                    LabRow(
                                        title: option.label,
                                        detail: metric == option ? "Seleccionada" : nil,
                                        symbol: option.symbol,
                                        tint: metric == option ? LabTone.accent : LabTone.muted
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(14)
                        .labPanel()

                        VStack(alignment: .leading, spacing: 11) {
                            LabCaps(text: "Vista previa")
                            EditorCardView(
                                model: kind == .kpi ? .compact : .icon,
                                title: metric.label,
                                value: metric.unit.format(42),
                                caption: "Componente nuevo",
                                progress: 0.62,
                                symbol: metric.symbol,
                                tint: LabTone.accent
                            )
                            .allowsHitTesting(false)
                        }
                        .padding(14)
                        .labPanel()

                        Button("Añadir a \(screen.label)") {
                            editor.insert(kind: kind, metric: metric, screen: screen, order: 999)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            dismiss()
                        }
                        .buttonStyle(LabButtonStyle(kind: .solid))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Biblioteca")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(LabTone.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                        .foregroundStyle(LabTone.muted)
                }
            }
        }
        .presentationBackground(LabTone.canvas)
        .preferredColorScheme(.dark)
        .onAppear {
            metric = EditorMetric.scope(for: screen).first ?? .earningsToday
        }
    }
}
