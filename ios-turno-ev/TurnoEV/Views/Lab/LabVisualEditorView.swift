import SwiftUI
import UIKit

/// Console of the visual editor. It is the door: the mode is switched on here, and from
/// here the administrator sees everything the sitting produced — hidden elements, saved
/// versions, rewritten sentences and the audit of every change.
struct LabVisualEditorView: View {
    @Environment(LabStore.self) private var lab
    @Environment(FleetStore.self) private var fleet
    @Environment(VisualEditorStore.self) private var editor

    @State private var screen: EditorScreen = .driverGoals
    @State private var isVersionSheetPresented: Bool = false
    @State private var isMessagesPresented: Bool = false
    @State private var isResetConfirmPresented: Bool = false
    @State private var versionName: String = ""

    private var canOpen: Bool {
        EditorRules.canOpen(isUnlocked: editor.isUnlocked, mode: lab.mode)
    }

    var body: some View {
        LabScreen(section: .visualEditor) {
            if canOpen {
                activationCard
                screenPicker
                deviceCard
                historyCard
                hiddenCard
                versionsCard
                messagesCard
                auditCard
                publishCard
                resetCard
            } else {
                lockedCard
            }
        }
        .sheet(isPresented: $isMessagesPresented) {
            EditorMessagesView()
        }
    }

    // MARK: - Access

    private var lockedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Editor no disponible", systemImage: "lock.fill")
                .font(.system(.subheadline, weight: .bold))
                .foregroundStyle(LabTone.bad)
            Text(lab.mode == .production
                 ? "Las interfaces solo se editan dentro del entorno de pruebas. En producción el editor queda cerrado para que ningún cambio de diseño alcance a un usuario real."
                 : "El editor visual solo abre con la credencial de Administrador de Pruebas. Inicia sesión con \(LabRules.adminEmail) para desbloquearlo en este dispositivo.")
                .font(.footnote)
                .foregroundStyle(LabTone.muted)
                .fixedSize(horizontal: false, vertical: true)
            if lab.mode == .production {
                Button("Entrar a modo prueba") { lab.setMode(.test) }
                    .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
            }
        }
        .padding(16)
        .labPanel()
    }

    // MARK: - Activation

    private var activationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "square.dashed.inset.filled")
                    .font(.system(.title3, weight: .black))
                    .foregroundStyle(editor.isEditing ? LabTone.canvas : LabTone.accent)
                    .frame(width: 46, height: 46)
                    .background(
                        editor.isEditing ? LabTone.accent : LabTone.accent.opacity(0.13),
                        in: .rect(cornerRadius: 15)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Editor visual")
                        .font(.system(.title3, weight: .black))
                        .foregroundStyle(.white)
                    Text(editor.isEditing ? "Modo edición activo" : "Modo edición apagado")
                        .font(.caption)
                        .foregroundStyle(editor.isEditing ? LabTone.accent : LabTone.muted)
                }
                Spacer(minLength: 0)
            }

            Text("Con el modo activo puedes navegar la aplicación normalmente y editar las pantallas donde estés: mantén presionado un elemento para seleccionarlo, arrástralo para moverlo y abre ••• para cambiar tamaño, modelo, gráfico, datos o texto.")
                .font(.footnote)
                .foregroundStyle(LabTone.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button(editor.isEditing ? "Salir del modo edición" : "Activar modo edición") {
                if editor.isEditing {
                    editor.deactivate()
                } else {
                    editor.activate(author: fleet.currentAccount?.name ?? "Administrador de Pruebas")
                }
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            }
            .buttonStyle(LabButtonStyle(kind: editor.isEditing ? .danger : .solid))

            if editor.isEditing {
                LabToggleRow(
                    title: "Vista previa",
                    subtitle: "Oculta los controles y muestra la pantalla tal como la verá el usuario.",
                    isOn: Binding(
                        get: { editor.isPreviewing },
                        set: { editor.isPreviewing = $0; editor.selection = nil }
                    )
                )

                Text("Para revisar la interfaz de otro rol usa «Ver aplicación como…» en Sistema. El editor te sigue a esa pantalla sin cambiar los permisos de nadie.")
                    .font(.caption2)
                    .foregroundStyle(LabTone.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LabToggleRow(
                title: "Acceso flotante en las interfaces",
                subtitle: "Botón arrastrable sobre conductor, supervisión y gerencia para encender y apagar la edición sin volver aquí.",
                isOn: Binding(
                    get: { editor.showsFloatingHandle },
                    set: { editor.showsFloatingHandle = $0 }
                )
            )
        }
        .padding(16)
        .labPanel()
    }

    // MARK: - Screen

    private var screenPicker: some View {
        VStack(alignment: .leading, spacing: 11) {
            LabCaps(text: "Pantalla en edición")
            ForEach(EditorScreen.allCases) { item in
                Button {
                    screen = item
                } label: {
                    LabRow(
                        title: item.label,
                        subtitle: editor.hasChanges(item)
                            ? "\(editor.layout(item).changeCount) cambios en el entorno de pruebas"
                            : "Diseño original",
                        detail: screen == item ? "Seleccionada" : nil,
                        symbol: item.symbol,
                        tint: editor.hasChanges(item) ? LabTone.accent : (screen == item ? LabTone.cool : LabTone.muted)
                    )
                }
                .buttonStyle(.plain)
            }
            Text("Las pantallas que aún no están instrumentadas se pueden editar en cuanto se conecten al lienzo; las que ya lo están responden de inmediato.")
                .font(.caption2)
                .foregroundStyle(LabTone.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .labPanel()
    }

    // MARK: - Devices

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            LabCaps(text: "Vista previa por dispositivo")
            LabOptionRow(
                label: "Ancho de referencia",
                options: EditorDevice.allCases,
                selection: Binding(
                    get: { editor.device },
                    set: { editor.device = $0 }
                ),
                title: \.label,
                symbol: \.symbol
            )

            EditorDeviceCanvas(device: editor.device, screen: screen)

            Text("La cuadrícula de cuatro columnas se recalcula con el ancho del dispositivo, así que ningún cambio puede dejar un elemento fuera de pantalla.")
                .font(.caption2)
                .foregroundStyle(LabTone.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .labPanel()
    }

    // MARK: - History

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                LabCaps(text: "Historial de la sesión")
                Spacer(minLength: 0)
                HStack(spacing: 7) {
                    Button("Deshacer") { editor.undo() }
                        .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
                        .disabled(!editor.canUndo)
                    Button("Rehacer") { editor.redo() }
                        .buttonStyle(LabButtonStyle(kind: .ghost, isCompact: true))
                        .disabled(!editor.canRedo)
                }
            }

            if editor.past.isEmpty {
                Text("Todavía no has movido nada en esta sesión.")
                    .font(.footnote)
                    .foregroundStyle(LabTone.muted)
            } else {
                ForEach(Array(editor.past.suffix(6).reversed().enumerated()), id: \.element.id) { item in
                    HStack(spacing: 9) {
                        Text("\(editor.past.count - item.offset)")
                            .font(.system(size: 10, weight: .black))
                            .monospacedDigit()
                            .foregroundStyle(LabTone.canvas)
                            .frame(width: 20, height: 20)
                            .background(LabTone.accent, in: .circle)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.element.summary)
                                .font(.system(.footnote, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(item.element.screen.label)
                                .font(.caption2)
                                .foregroundStyle(LabTone.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .labFlat()
                }
            }
        }
        .padding(16)
        .labPanel()
    }

    // MARK: - Hidden and deleted

    private var hiddenCard: some View {
        let layout = editor.layout(screen)
        let hidden = layout.hiddenIds
        let deleted = layout.deletedIds

        return VStack(alignment: .leading, spacing: 11) {
            LabCaps(text: "Elementos ocultos y eliminados")

            if hidden.isEmpty, deleted.isEmpty {
                Text("Todo lo de \(screen.label) está visible.")
                    .font(.footnote)
                    .foregroundStyle(LabTone.muted)
            } else {
                ForEach(hidden, id: \.self) { id in
                    restoreRow(id: id, isDeleted: false)
                }
                ForEach(deleted, id: \.self) { id in
                    restoreRow(id: id, isDeleted: true)
                }
                Text("Ocultar y eliminar son cosas distintas: lo oculto sigue calculándose y solo deja de dibujarse; lo eliminado sale del diseño de esta interfaz. Ninguno de los dos toca datos ni lógica.")
                    .font(.caption2)
                    .foregroundStyle(LabTone.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .labPanel()
    }

    private func restoreRow(id: String, isDeleted: Bool) -> some View {
        LabRow(
            title: id,
            subtitle: isDeleted ? "Eliminado del diseño" : "Oculto en la interfaz",
            symbol: isDeleted ? "trash.fill" : "eye.slash.fill",
            tint: isDeleted ? LabTone.bad : LabTone.cool
        ) {
            Button("Restaurar") {
                editor.restore(screen: screen, elementId: id, title: id)
            }
            .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
        }
    }

    // MARK: - Versions

    private var versionsCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                LabCaps(text: "Versiones guardadas")
                Spacer(minLength: 0)
                Button("Guardar versión") {
                    versionName = "\(screen.label) v\(editor.versions(for: screen).count + 1)"
                    isVersionSheetPresented = true
                }
                .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
            }

            let saved = editor.versions(for: screen)
            if saved.isEmpty {
                Text("Guarda una versión para poder volver a este diseño más adelante.")
                    .font(.footnote)
                    .foregroundStyle(LabTone.muted)
            } else {
                ForEach(saved) { version in
                    VStack(alignment: .leading, spacing: 9) {
                        LabRow(
                            title: version.name,
                            subtitle: "\(version.changeCount) cambios · \(version.author)",
                            detail: Fmt.dateShort(version.createdAt),
                            symbol: "square.stack.3d.up.fill"
                        )
                        HStack(spacing: 7) {
                            Button("Restaurar") { editor.restoreVersion(version) }
                                .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
                            Button("Duplicar") { editor.duplicateVersion(version) }
                                .buttonStyle(LabButtonStyle(kind: .ghost, isCompact: true))
                            Button("Eliminar") { editor.deleteVersion(version) }
                                .buttonStyle(LabButtonStyle(kind: .danger, isCompact: true))
                        }
                    }
                }
            }
        }
        .padding(16)
        .labPanel()
        .alert("Guardar versión", isPresented: $isVersionSheetPresented) {
            TextField("Nombre", text: $versionName)
            Button("Guardar") { editor.saveVersion(name: versionName, screen: screen) }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Queda una copia del diseño actual de \(screen.label) que podrás previsualizar, restaurar o duplicar.")
        }
    }

    // MARK: - Messages

    private var messagesCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            LabCaps(text: "Mensajes del sistema")
            Text("Alertas, avisos, confirmaciones, estados vacíos, errores e instrucciones. Se edita la frase, nunca la lógica que la dispara.")
                .font(.footnote)
                .foregroundStyle(LabTone.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                LabChip(text: "\(editor.messages.count) claves", symbol: "text.quote")
                let edited = editor.messages.filter(\.isEdited).count
                if edited > 0 {
                    LabChip(text: "\(edited) editados", symbol: "pencil", tint: LabTone.good)
                }
            }

            Button("Abrir biblioteca de mensajes") { isMessagesPresented = true }
                .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
        }
        .padding(16)
        .labPanel()
    }

    // MARK: - Audit

    private var auditCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            LabCaps(text: "Auditoría del editor")

            if editor.audit.isEmpty {
                Text("Sin cambios registrados.")
                    .font(.footnote)
                    .foregroundStyle(LabTone.muted)
            } else {
                ForEach(editor.audit.prefix(8)) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(entry.previousValue)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(LabTone.muted)
                                .strikethrough()
                                .lineLimit(1)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(LabTone.muted)
                            Text(entry.newValue)
                                .font(.system(size: 11, weight: .black))
                                .foregroundStyle(LabTone.accent)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        Text("\(entry.change) · \(entry.elementTitle)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(entry.screen.label) · \(entry.author) · \(Fmt.dateShort(entry.createdAt)) \(Fmt.clock(entry.createdAt))")
                            .font(.caption2)
                            .foregroundStyle(LabTone.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(11)
                    .labFlat()
                }
            }
        }
        .padding(16)
        .labPanel()
    }

    // MARK: - Publish

    private var publishCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            LabCaps(text: "Publicar")
            Text(EditorRules.publishNotice)
                .font(.footnote)
                .foregroundStyle(LabTone.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button("Publicar cambios a producción") {}
                .buttonStyle(LabButtonStyle(kind: .ghost))
                .disabled(!EditorRules.isPublishingEnabled)
            LabChip(text: "Solo entorno de pruebas", symbol: "testtube.2", tint: LabTone.cool)

            Button("Cerrar el editor en este dispositivo") { editor.lock() }
                .buttonStyle(LabButtonStyle(kind: .ghost, isCompact: true))
        }
        .padding(16)
        .labPanel()
    }

    private var resetCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            LabCaps(text: "Restablecer")
            Button("Restablecer \(screen.label)") { isResetConfirmPresented = true }
                .buttonStyle(LabButtonStyle(kind: .danger, isCompact: true))
                .disabled(!editor.hasChanges(screen))
        }
        .padding(16)
        .labPanel()
        .confirmationDialog(
            "¿Restablecer el diseño original de \(screen.label)?",
            isPresented: $isResetConfirmPresented,
            titleVisibility: .visible
        ) {
            Button("Restablecer pantalla", role: .destructive) { editor.resetScreen(screen) }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se pierden los \(editor.layout(screen).changeCount) cambios de esta pantalla. Las versiones guardadas se conservan.")
        }
    }
}

// MARK: - Device canvas

/// Scaled silhouette of the screen at the width of a device, to catch a layout that would
/// break before it reaches anybody.
private struct EditorDeviceCanvas: View {
    let device: EditorDevice
    let screen: EditorScreen

    @Environment(VisualEditorStore.self) private var editor

    var body: some View {
        let layout = editor.layout(screen)
        let widths = layout.overrides.compactMapValues(\.width)

        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: device.symbol)
                    .font(.system(size: 10, weight: .bold))
                Text("\(Int(device.width)) pt · 4 columnas de \(Int((device.width - 32 - 30) / 4)) pt")
                    .font(.system(size: 10, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(LabTone.muted)

            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LabTone.accent.opacity(0.16))
                        .frame(height: 34)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(LabTone.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                }
            }

            Text(widths.isEmpty
                 ? "Ningún elemento cambió de ancho en esta pantalla."
                 : "\(widths.count) elementos con ancho personalizado. Todos caben en la cuadrícula.")
                .font(.caption2)
                .foregroundStyle(LabTone.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .labFlat()
    }
}

// MARK: - Messages library

/// Every sentence the system prints, searchable and rewritable, with its variables kept
/// alive: a message can change its words, never its data.
struct EditorMessagesView: View {
    @Environment(VisualEditorStore.self) private var editor
    @Environment(\.dismiss) private var dismiss

    @State private var search: String = ""
    @State private var group: String = "Todos"
    @State private var drafts: [String: String] = [:]

    private var groups: [String] { ["Todos"] + EditorMessageCatalog.groups }

    private var filtered: [EditorMessage] {
        editor.messages.filter { message in
            let matchesGroup = group == "Todos" || message.group == group
            let query = search.trimmingCharacters(in: .whitespaces).lowercased()
            let matchesSearch = query.isEmpty
                || message.key.lowercased().contains(query)
                || message.text.lowercased().contains(query)
            return matchesGroup && matchesSearch
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LabBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        LabOptionRow(
                            label: "Categoría",
                            options: groups,
                            selection: $group,
                            title: { $0 }
                        )

                        ForEach(filtered) { message in
                            messageCard(message)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .searchable(text: $search, prompt: "Clave o texto")
            .navigationTitle("Mensajes del sistema")
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
    }

    private func messageCard(_ message: EditorMessage) -> some View {
        let draft = drafts[message.key] ?? message.text
        let pending = EditorMessage(
            key: message.key,
            text: draft,
            defaultText: message.defaultText,
            group: message.group,
            variables: message.variables,
            usage: message.usage
        )

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(message.key)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(LabTone.accent)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if message.isEdited {
                    LabChip(text: "Editado", symbol: "pencil", tint: LabTone.good)
                }
            }

            Text(message.usage)
                .font(.caption2)
                .foregroundStyle(LabTone.muted)
                .fixedSize(horizontal: false, vertical: true)

            TextField(
                "Texto",
                text: Binding(
                    get: { drafts[message.key] ?? message.text },
                    set: { drafts[message.key] = $0 }
                ),
                axis: .vertical
            )
            .font(.system(.footnote, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(2...5)
            .padding(11)
            .labFlat(cornerRadius: 13)

            if !message.variables.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(message.variables, id: \.self) { variable in
                            LabChip(text: "{\(variable)}", symbol: "curlybraces", tint: LabTone.cool)
                        }
                    }
                    Text("Vista previa: \(pending.preview(samples: EditorMessageCatalog.samples))")
                        .font(.caption2)
                        .foregroundStyle(LabTone.accentSoft)
                        .fixedSize(horizontal: false, vertical: true)

                    if !pending.droppedVariables.isEmpty {
                        Text("Faltan las variables \(pending.droppedVariables.map { "{\($0)}" }.joined(separator: ", ")). Sin ellas el mensaje quedaría fijo y perdería el dato real.")
                            .font(.caption2)
                            .foregroundStyle(LabTone.bad)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: 7) {
                Button("Guardar") {
                    editor.updateMessage(key: message.key, text: draft)
                    drafts.removeValue(forKey: message.key)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
                .disabled(draft == message.text || !pending.droppedVariables.isEmpty)

                if message.isEdited {
                    Button("Texto original") {
                        editor.resetMessage(key: message.key)
                        drafts.removeValue(forKey: message.key)
                    }
                    .buttonStyle(LabButtonStyle(kind: .ghost, isCompact: true))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .labPanel()
    }
}
