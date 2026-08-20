import Foundation
import Observation

/// State of the visual editor: what is being edited, what each screen looks like after
/// the administrator's changes, and the trace of everything that was touched.
///
/// The store is deliberately isolated from every operational store. It can describe a
/// screen, it cannot produce a record.
@Observable
final class VisualEditorStore {
    nonisolated private struct PersistedState: Codable, Sendable {
        var layouts: [String: EditorLayout]
        var messages: [String: String]
        var versions: [EditorVersion]
        var audit: [EditorAuditEntry]
        /// Credential that opened the editor. Persisted so reviewing another role's
        /// interface — which replaces the session — does not lock the administrator out.
        var unlockedBy: String?
        var unlockedName: String?
    }

    private let storageKey = "turnoev.visualeditor.v1"
    private let historyLimit = 60
    private let auditLimit = 300

    /// Design of every screen, keyed by screen.
    private(set) var layouts: [String: EditorLayout] = [:]
    /// Rewritten system sentences, keyed by message key.
    private(set) var messageOverrides: [String: String] = [:]
    private(set) var versions: [EditorVersion] = []
    private(set) var audit: [EditorAuditEntry] = []

    /// Session history. It is not persisted: undo belongs to the sitting, the design belongs to the file.
    private(set) var past: [EditorStep] = []
    private(set) var future: [EditorStep] = []

    /// Account id of the laboratory credential that unlocked the editor.
    private(set) var unlockedBy: String?

    /// Floating access on the operational interfaces. On by default once unlocked.
    var showsFloatingHandle: Bool = true

    /// Edit mode is off until the administrator turns it on from the console.
    var isEditing: Bool = false
    /// Preview hides every editing control without leaving the mode.
    var isPreviewing: Bool = false
    var selection: EditorSelection?
    var device: EditorDevice = .phoneLarge

    var author: String = "Administrador de Pruebas"

    /// True while the administrator can actually manipulate elements on screen.
    var isLive: Bool { isEditing && !isPreviewing }

    var isUnlocked: Bool { unlockedBy != nil }

    init() { load() }

    // MARK: - Session

    /// Called whenever a session is observed. A laboratory credential unlocks the editor
    /// and keeps it unlocked while that administrator reviews other interfaces; a device
    /// that was never unlocked leaves everything inert.
    func observe(account: StaffAccount?) {
        guard EditorRules.unlocks(account: account), let account else { return }
        guard unlockedBy != account.id else { return }
        unlockedBy = account.id
        author = account.name
        persist()
    }

    /// Closes the door: the editor turns off and stops following any session.
    func lock() {
        unlockedBy = nil
        deactivate()
        persist()
    }

    func activate(author: String) {
        self.author = author
        isEditing = true
        isPreviewing = false
    }

    func deactivate() {
        isEditing = false
        isPreviewing = false
        selection = nil
    }

    // MARK: - Floating shortcut

    /// Where the administrator parked the floating access, as a fraction of the screen,
    /// so it never drifts back over a control he needs.
    var handlePosition: CGPoint {
        get {
            let x = UserDefaults.standard.object(forKey: "turnoev.editor.handle.x") as? Double
            let y = UserDefaults.standard.object(forKey: "turnoev.editor.handle.y") as? Double
            return CGPoint(x: x ?? 0.9, y: y ?? 0.6)
        }
        set {
            UserDefaults.standard.set(newValue.x, forKey: "turnoev.editor.handle.x")
            UserDefaults.standard.set(newValue.y, forKey: "turnoev.editor.handle.y")
        }
    }

    // MARK: - Reads

    func layout(_ screen: EditorScreen) -> EditorLayout {
        layouts[screen.rawValue] ?? EditorLayout()
    }

    func override(_ screen: EditorScreen, _ elementId: String) -> EditorOverride {
        layout(screen).overrides[elementId] ?? EditorOverride()
    }

    func hasChanges(_ screen: EditorScreen) -> Bool { !layout(screen).isPristine }

    var editedScreens: [EditorScreen] {
        EditorScreen.allCases.filter { hasChanges($0) }
    }

    /// Sentence the app should print for a key, after any rewrite.
    func message(_ key: String) -> EditorMessage? {
        guard var message = EditorMessageCatalog.defaults.first(where: { $0.key == key }) else { return nil }
        if let override = messageOverrides[key] { message.text = override }
        return message
    }

    var messages: [EditorMessage] {
        EditorMessageCatalog.defaults.map { base in
            var message = base
            if let override = messageOverrides[base.key] { message.text = override }
            return message
        }
    }

    // MARK: - Writes

    /// Every mutation of a design goes through here, so history, audit and persistence
    /// can never drift apart from what is on screen.
    private func mutate(
        _ screen: EditorScreen,
        elementId: String,
        elementTitle: String,
        change: String,
        previous: String,
        next: String,
        apply: (inout EditorLayout) -> Void
    ) {
        let before = layout(screen)
        var updated = before
        apply(&updated)
        guard updated != before else { return }

        layouts[screen.rawValue] = updated

        let step = EditorStep(
            id: "step-\(UUID().uuidString.prefix(6))",
            screen: screen,
            summary: "\(change) · \(elementTitle)",
            before: before,
            after: updated,
            createdAt: Date()
        )
        past.append(step)
        if past.count > historyLimit { past.removeFirst(past.count - historyLimit) }
        future.removeAll()

        audit.insert(
            EditorAuditEntry(
                id: "eda-\(UUID().uuidString.prefix(8))",
                screen: screen,
                elementId: elementId,
                elementTitle: elementTitle,
                change: change,
                previousValue: previous,
                newValue: next,
                author: author,
                createdAt: Date()
            ),
            at: 0
        )
        if audit.count > auditLimit { audit.removeLast(audit.count - auditLimit) }

        persist()
    }

    private func edit(
        _ screen: EditorScreen,
        _ element: EditorElementRef,
        change: String,
        previous: String,
        next: String,
        transform: (inout EditorOverride) -> Void
    ) {
        mutate(
            screen,
            elementId: element.id,
            elementTitle: element.title,
            change: change,
            previous: previous,
            next: next
        ) { layout in
            var current = layout.overrides[element.id] ?? EditorOverride()
            transform(&current)
            if current.isPristine {
                layout.overrides.removeValue(forKey: element.id)
            } else {
                layout.overrides[element.id] = current
            }
        }
    }

    // MARK: - Layout actions

    func setWidth(_ width: EditorWidth, screen: EditorScreen, element: EditorElementRef) {
        let before = override(screen, element.id).width ?? element.defaultWidth
        edit(screen, element, change: "Cambió el ancho", previous: before.label, next: width.label) {
            $0.width = width == element.defaultWidth ? nil : width
        }
    }

    func setHeight(_ height: EditorHeight, screen: EditorScreen, element: EditorElementRef) {
        let before = override(screen, element.id).height ?? .automatic
        edit(screen, element, change: "Cambió el alto", previous: before.label, next: height.label) {
            $0.height = height == .automatic ? nil : height
        }
    }

    func setSpacing(_ spacing: EditorSpacing, screen: EditorScreen, element: EditorElementRef) {
        let before = override(screen, element.id).spacing ?? .normal
        edit(screen, element, change: "Cambió el espacio", previous: before.label, next: spacing.label) {
            $0.spacing = spacing == .normal ? nil : spacing
        }
    }

    func setCardModel(_ model: EditorCardModel, screen: EditorScreen, element: EditorElementRef) {
        let before = override(screen, element.id).cardModel ?? element.defaultCardModel
        edit(screen, element, change: "Cambió el modelo de tarjeta", previous: before.label, next: model.label) {
            $0.cardModel = model
        }
    }

    func setChartKind(_ kind: EditorChartKind, screen: EditorScreen, element: EditorElementRef) {
        let before = override(screen, element.id).chartKind ?? element.defaultChartKind
        edit(screen, element, change: "Cambió la visualización", previous: before.label, next: kind.label) {
            $0.chartKind = kind
        }
    }

    func setMetric(_ metric: EditorMetric, screen: EditorScreen, element: EditorElementRef) {
        let before = override(screen, element.id).metric ?? element.metric
        edit(
            screen,
            element,
            change: "Cambió la fuente de datos",
            previous: before?.label ?? "original",
            next: metric.label
        ) {
            $0.metric = metric
        }
    }

    func setTitle(_ title: String, screen: EditorScreen, element: EditorElementRef) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let before = override(screen, element.id).title ?? element.title
        edit(screen, element, change: "Editó el título", previous: before, next: trimmed) {
            $0.title = trimmed.isEmpty || trimmed == element.title ? nil : trimmed
        }
    }

    func setSubtitle(_ subtitle: String, screen: EditorScreen, element: EditorElementRef) {
        let trimmed = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let before = override(screen, element.id).subtitle ?? (element.subtitle ?? "—")
        edit(screen, element, change: "Editó el texto", previous: before, next: trimmed) {
            $0.subtitle = trimmed.isEmpty || trimmed == element.subtitle ? nil : trimmed
        }
    }

    func setChartOption(
        screen: EditorScreen,
        element: EditorElementRef,
        values: Bool? = nil,
        legend: Bool? = nil,
        labels: Bool? = nil
    ) {
        let change: String
        let next: String
        if let values {
            change = "Valores del gráfico"
            next = values ? "visibles" : "ocultos"
        } else if let legend {
            change = "Leyenda del gráfico"
            next = legend ? "visible" : "oculta"
        } else if let labels {
            change = "Etiquetas del gráfico"
            next = labels ? "visibles" : "ocultas"
        } else {
            return
        }

        edit(screen, element, change: change, previous: "—", next: next) {
            if let values { $0.showsValues = values }
            if let legend { $0.showsLegend = legend }
            if let labels { $0.showsLabels = labels }
        }
    }

    /// Moves an element to a new position. The order of the whole screen is rewritten so
    /// nothing can end up sharing a slot.
    func move(element: EditorElementRef, to index: Int, screen: EditorScreen, ordered: [EditorElementRef]) {
        var ids = ordered.map(\.id)
        guard let current = ids.firstIndex(of: element.id) else { return }
        let target = max(0, min(ids.count - 1, index))
        guard current != target else { return }

        ids.remove(at: current)
        ids.insert(element.id, at: target)

        mutate(
            screen,
            elementId: element.id,
            elementTitle: element.title,
            change: "Movió el elemento",
            previous: "posición \(current + 1)",
            next: "posición \(target + 1)"
        ) { layout in
            for (position, id) in ids.enumerated() {
                if var existing = layout.overrides[id] {
                    existing.order = position
                    layout.overrides[id] = existing
                } else {
                    var fresh = EditorOverride()
                    fresh.order = position
                    layout.overrides[id] = fresh
                }
                if let addedIndex = layout.added.firstIndex(where: { $0.id == id }) {
                    layout.added[addedIndex].order = position
                }
            }
        }
    }

    func setHidden(_ hidden: Bool, screen: EditorScreen, element: EditorElementRef) {
        edit(
            screen,
            element,
            change: hidden ? "Ocultó el elemento" : "Restauró el elemento oculto",
            previous: hidden ? "visible" : "oculto",
            next: hidden ? "oculto" : "visible"
        ) {
            $0.isHidden = hidden
        }
    }

    func delete(screen: EditorScreen, element: EditorElementRef) {
        guard !element.isCritical else { return }
        if element.isAdded {
            mutate(
                screen,
                elementId: element.id,
                elementTitle: element.title,
                change: "Eliminó el elemento añadido",
                previous: element.title,
                next: "—"
            ) { layout in
                layout.added.removeAll { $0.id == element.id }
                layout.overrides.removeValue(forKey: element.id)
            }
            return
        }
        edit(screen, element, change: "Eliminó del diseño", previous: "en pantalla", next: "eliminado") {
            $0.isDeleted = true
            $0.isHidden = false
        }
    }

    func restore(screen: EditorScreen, elementId: String, title: String) {
        mutate(
            screen,
            elementId: elementId,
            elementTitle: title,
            change: "Restauró el elemento",
            previous: "fuera de la pantalla",
            next: "en pantalla"
        ) { layout in
            guard var current = layout.overrides[elementId] else { return }
            current.isHidden = false
            current.isDeleted = false
            if current.isPristine {
                layout.overrides.removeValue(forKey: elementId)
            } else {
                layout.overrides[elementId] = current
            }
        }
    }

    func duplicate(element: EditorElementRef, screen: EditorScreen, order: Int) {
        let copy = EditorAddedElement(
            id: "dup-\(UUID().uuidString.prefix(6))",
            sourceId: element.id,
            kind: element.kind,
            title: "\(element.title) (copia)",
            metric: element.metric ?? EditorMetric.scope(for: screen).first ?? .earningsToday,
            cardModel: override(screen, element.id).cardModel ?? element.defaultCardModel,
            width: override(screen, element.id).width ?? element.defaultWidth,
            order: order,
            createdAt: Date()
        )
        mutate(
            screen,
            elementId: copy.id,
            elementTitle: copy.title,
            change: "Duplicó el elemento",
            previous: element.title,
            next: copy.title
        ) { layout in
            layout.added.append(copy)
        }
    }

    /// Drops a component from the library at the end of a screen.
    func insert(kind: EditorElementKind, metric: EditorMetric, screen: EditorScreen, order: Int) {
        let element = EditorAddedElement(
            id: "new-\(UUID().uuidString.prefix(6))",
            sourceId: nil,
            kind: kind,
            title: metric.label,
            metric: metric,
            cardModel: kind == .kpi ? .compact : .icon,
            width: kind == .kpi ? .half : .full,
            order: order,
            createdAt: Date()
        )
        mutate(
            screen,
            elementId: element.id,
            elementTitle: element.title,
            change: "Añadió un componente",
            previous: "—",
            next: "\(kind.label) · \(metric.label)"
        ) { layout in
            layout.added.append(element)
        }
    }

    func resetElement(screen: EditorScreen, element: EditorElementRef) {
        mutate(
            screen,
            elementId: element.id,
            elementTitle: element.title,
            change: "Restableció el diseño original",
            previous: override(screen, element.id).summary,
            next: "diseño original"
        ) { layout in
            layout.overrides.removeValue(forKey: element.id)
            layout.added.removeAll { $0.id == element.id }
        }
    }

    func resetScreen(_ screen: EditorScreen) {
        mutate(
            screen,
            elementId: screen.rawValue,
            elementTitle: screen.label,
            change: "Restableció la pantalla completa",
            previous: "\(layout(screen).changeCount) cambios",
            next: "diseño original"
        ) { layout in
            layout = EditorLayout()
        }
        selection = nil
    }

    // MARK: - Messages

    func updateMessage(key: String, text: String) {
        guard let base = EditorMessageCatalog.defaults.first(where: { $0.key == key }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = messageOverrides[key] ?? base.defaultText
        guard trimmed != previous, !trimmed.isEmpty else { return }

        if trimmed == base.defaultText {
            messageOverrides.removeValue(forKey: key)
        } else {
            messageOverrides[key] = trimmed
        }

        audit.insert(
            EditorAuditEntry(
                id: "eda-\(UUID().uuidString.prefix(8))",
                screen: .driverShift,
                elementId: key,
                elementTitle: "Mensaje \(base.group.lowercased())",
                change: "Editó el mensaje del sistema",
                previousValue: previous,
                newValue: trimmed,
                author: author,
                createdAt: Date()
            ),
            at: 0
        )
        persist()
    }

    func resetMessage(key: String) {
        guard messageOverrides[key] != nil else { return }
        messageOverrides.removeValue(forKey: key)
        persist()
    }

    // MARK: - History

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    func undo() {
        guard let step = past.popLast() else { return }
        layouts[step.screen.rawValue] = step.before
        future.append(step)
        persist()
    }

    func redo() {
        guard let step = future.popLast() else { return }
        layouts[step.screen.rawValue] = step.after
        past.append(step)
        persist()
    }

    func clearHistory() {
        past.removeAll()
        future.removeAll()
    }

    // MARK: - Versions

    func saveVersion(name: String, screen: EditorScreen) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = versions.filter { $0.screen == screen }.count + 1
        let version = EditorVersion(
            id: "ver-\(UUID().uuidString.prefix(6))",
            name: trimmed.isEmpty ? "\(screen.label) v\(count)" : trimmed,
            screen: screen,
            layout: layout(screen),
            createdAt: Date(),
            author: author
        )
        versions.insert(version, at: 0)
        persist()
    }

    func versions(for screen: EditorScreen) -> [EditorVersion] {
        versions.filter { $0.screen == screen }
    }

    func restoreVersion(_ version: EditorVersion) {
        mutate(
            version.screen,
            elementId: version.id,
            elementTitle: version.name,
            change: "Restauró una versión guardada",
            previous: "\(layout(version.screen).changeCount) cambios",
            next: "\(version.changeCount) cambios"
        ) { layout in
            layout = version.layout
        }
    }

    func duplicateVersion(_ version: EditorVersion) {
        let copy = EditorVersion(
            id: "ver-\(UUID().uuidString.prefix(6))",
            name: "\(version.name) (copia)",
            screen: version.screen,
            layout: version.layout,
            createdAt: Date(),
            author: author
        )
        versions.insert(copy, at: 0)
        persist()
    }

    func deleteVersion(_ version: EditorVersion) {
        versions.removeAll { $0.id == version.id }
        persist()
    }

    // MARK: - Wipe

    func clearAll() {
        layouts = [:]
        messageOverrides = [:]
        versions = []
        audit = []
        clearHistory()
        selection = nil
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let state = try decoder.decode(PersistedState.self, from: data)
            layouts = state.layouts
            messageOverrides = state.messages
            versions = state.versions
            audit = state.audit
            unlockedBy = state.unlockedBy
            if let name = state.unlockedName { author = name }
        } catch {
            print("No se pudo leer el editor visual: \(error.localizedDescription)")
        }
    }

    private func persist() {
        let state = PersistedState(
            layouts: layouts,
            messages: messageOverrides,
            versions: versions,
            audit: audit,
            unlockedBy: unlockedBy,
            unlockedName: author
        )
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("No se pudo guardar el editor visual: \(error.localizedDescription)")
        }
    }
}

/// What the administrator has selected on screen.
nonisolated struct EditorSelection: Equatable, Sendable {
    let screen: EditorScreen
    let elementId: String
}

/// Everything the editor needs to know about an element, resolved at the call site.
/// The screen declares it once; the editor never guesses.
nonisolated struct EditorElementRef: Identifiable, Sendable {
    let id: String
    let title: String
    var subtitle: String?
    let kind: EditorElementKind
    var isCritical: Bool = false
    var isAdded: Bool = false
    var metric: EditorMetric?
    var defaultWidth: EditorWidth = .full
    var defaultCardModel: EditorCardModel = .compact
    var defaultChartKind: EditorChartKind = .verticalBars
    var supportsCardLibrary: Bool = false
    var supportsChartLibrary: Bool = false
    var supportsDataSource: Bool = false
    var supportsDuplicate: Bool = true
}
