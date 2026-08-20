import SwiftUI
import UIKit

/// Floating access to the editor. It rides on top of the driver, supervisor and manager
/// interfaces so the administrator never has to walk back to the laboratory to switch the
/// mode on or off.
///
/// It is deliberately small and draggable: whatever it covers, the administrator moves it
/// out of the way with a finger, and the app remembers where he left it. It exists only
/// for the laboratory credential inside the test environment, so no operator can ever
/// meet it.
struct EditorFloatingHandle: View {
    @Environment(VisualEditorStore.self) private var editor
    @Environment(LabStore.self) private var lab
    @Environment(FleetStore.self) private var fleet

    /// Which screen the shortcut edits, decided by the interface it is floating over.
    let screen: EditorScreen

    @State private var position: CGPoint = .zero
    @State private var drag: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var isExpanded: Bool = false
    @State private var isConsolePresented: Bool = false
    @State private var placed: Bool = false

    private var isAvailable: Bool {
        EditorRules.canOpen(isUnlocked: editor.isUnlocked, mode: lab.mode) && editor.showsFloatingHandle
    }

    private var tint: Color {
        guard editor.isEditing else { return LabTone.muted }
        return editor.isPreviewing ? LabTone.cool : LabTone.accent
    }

    var body: some View {
        GeometryReader { proxy in
            if isAvailable {
                let size = proxy.size

                content
                    .position(
                        x: position.x + drag.width,
                        y: position.y + drag.height
                    )
                    .gesture(
                        DragGesture(minimumDistance: 6)
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                    isExpanded = false
                                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                }
                                drag = value.translation
                            }
                            .onEnded { value in
                                // Park it inside the safe rectangle so it can never end up
                                // off screen or under the status bar.
                                let x = min(max(position.x + value.translation.width, 46), size.width - 46)
                                let y = min(max(position.y + value.translation.height, 84), size.height - 96)
                                position = CGPoint(x: x, y: y)
                                drag = .zero
                                isDragging = false
                                editor.handlePosition = CGPoint(
                                    x: x / max(size.width, 1),
                                    y: y / max(size.height, 1)
                                )
                            }
                    )
                    .onAppear {
                        guard !placed else { return }
                        placed = true
                        let stored = editor.handlePosition
                        position = CGPoint(
                            x: min(max(stored.x * size.width, 46), size.width - 46),
                            y: min(max(stored.y * size.height, 84), size.height - 96)
                        )
                    }
            }
        }
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $isConsolePresented) {
            EditorQuickConsoleView(screen: screen)
        }
    }

    // MARK: - Bubble

    private var content: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if isExpanded { actions }
            bubble
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: isExpanded)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
    }

    private var bubble: some View {
        Button {
            guard !isDragging else { return }
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                isExpanded.toggle()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(editor.isEditing ? tint : LabTone.surface.opacity(0.94))
                    .overlay {
                        Circle().stroke(tint.opacity(editor.isEditing ? 0 : 0.6), lineWidth: 1.5)
                    }
                    .shadow(color: .black.opacity(0.45), radius: isDragging ? 18 : 10, y: isDragging ? 10 : 5)

                Image(systemName: editor.isEditing
                      ? (editor.isPreviewing ? "eye.fill" : "square.dashed.inset.filled")
                      : "square.dashed")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(editor.isEditing ? LabTone.canvas : tint)
            }
            .frame(width: 50, height: 50)
            .scaleEffect(isDragging ? 1.12 : 1)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if editor.isEditing, editor.layout(screen).changeCount > 0 {
                Text("\(editor.layout(screen).changeCount)")
                    .font(.system(size: 9, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(LabTone.canvas)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(LabTone.good, in: .capsule)
                    .offset(x: 4, y: -2)
            }
        }
        .accessibilityLabel(editor.isEditing ? "Editor visual activo" : "Activar editor visual")
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(alignment: .trailing, spacing: 7) {
            action(
                editor.isEditing ? "Apagar edición" : "Activar edición",
                symbol: editor.isEditing ? "power" : "square.dashed.inset.filled",
                tint: editor.isEditing ? LabTone.bad : LabTone.accent
            ) {
                if editor.isEditing {
                    editor.deactivate()
                } else {
                    editor.activate(author: fleet.currentAccount?.name ?? editor.author)
                }
            }

            if editor.isEditing {
                action(
                    editor.isPreviewing ? "Volver a editar" : "Vista previa",
                    symbol: editor.isPreviewing ? "pencil" : "eye",
                    tint: LabTone.cool
                ) {
                    editor.isPreviewing.toggle()
                    editor.selection = nil
                }

                action("Deshacer", symbol: "arrow.uturn.backward", tint: LabTone.accentSoft, enabled: editor.canUndo) {
                    editor.undo()
                }

                action("Rehacer", symbol: "arrow.uturn.forward", tint: LabTone.accentSoft, enabled: editor.canRedo) {
                    editor.redo()
                }

                action("Panel del editor", symbol: "slider.horizontal.3", tint: LabTone.accent) {
                    isConsolePresented = true
                }
            }
        }
        .transition(.scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity))
    }

    private func action(
        _ title: String,
        symbol: String,
        tint: Color,
        enabled: Bool = true,
        perform: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            perform()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isExpanded = false }
        } label: {
            HStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(enabled ? .white : LabTone.muted.opacity(0.6))
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(enabled ? tint : LabTone.muted.opacity(0.6))
                    .frame(width: 20)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(LabTone.surface.opacity(0.96), in: .capsule)
            .overlay { Capsule().stroke(LabTone.hairline, lineWidth: 1) }
            .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Compact console reachable from the floating access, so the administrator can review
/// what he changed, restore something or jump to the message library without leaving the
/// interface he is editing.
struct EditorQuickConsoleView: View {
    let screen: EditorScreen

    @Environment(VisualEditorStore.self) private var editor
    @Environment(\.dismiss) private var dismiss

    @State private var isMessagesPresented: Bool = false
    @State private var isResetPresented: Bool = false
    @State private var isVersionPresented: Bool = false
    @State private var versionName: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                LabBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        summary
                        history
                        restorable
                        tools
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 36)
                }
            }
            .navigationTitle("Editor · \(screen.label)")
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
            .sheet(isPresented: $isMessagesPresented) { EditorMessagesView() }
        }
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
        .presentationBackground(LabTone.canvas)
        .preferredColorScheme(.dark)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 9) {
            LabCaps(text: "Esta pantalla")
            HStack(spacing: 9) {
                LabChip(
                    text: "\(editor.layout(screen).changeCount) cambios",
                    symbol: "square.dashed.inset.filled",
                    tint: editor.hasChanges(screen) ? LabTone.accent : LabTone.muted
                )
                LabChip(text: editor.isPreviewing ? "Previsualizando" : "Editando", symbol: editor.isPreviewing ? "eye.fill" : "pencil", tint: LabTone.cool)
                Spacer(minLength: 0)
            }
            Text("Mantén presionado cualquier elemento de la pantalla para seleccionarlo, arrástralo para moverlo y abre ••• para cambiar tamaño, modelo, gráfico, datos o texto.")
                .font(.caption2)
                .foregroundStyle(LabTone.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .labPanel()
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                LabCaps(text: "Historial")
                Spacer(minLength: 0)
                Button("Deshacer") { editor.undo() }
                    .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
                    .disabled(!editor.canUndo)
                Button("Rehacer") { editor.redo() }
                    .buttonStyle(LabButtonStyle(kind: .ghost, isCompact: true))
                    .disabled(!editor.canRedo)
            }

            if editor.past.isEmpty {
                Text("Sin cambios en esta sesión.")
                    .font(.footnote)
                    .foregroundStyle(LabTone.muted)
            } else {
                ForEach(editor.past.suffix(4).reversed()) { step in
                    Text("· \(step.summary)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .labPanel()
    }

    @ViewBuilder
    private var restorable: some View {
        let layout = editor.layout(screen)
        let ids = layout.hiddenIds + layout.deletedIds

        if !ids.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                LabCaps(text: "Ocultos y eliminados")
                ForEach(ids, id: \.self) { id in
                    HStack(spacing: 9) {
                        Image(systemName: layout.deletedIds.contains(id) ? "trash.fill" : "eye.slash.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(layout.deletedIds.contains(id) ? LabTone.bad : LabTone.cool)
                        Text(id)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Button("Restaurar") { editor.restore(screen: screen, elementId: id, title: id) }
                            .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))
                    }
                    .padding(10)
                    .labFlat()
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .labPanel()
        }
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 9) {
            LabCaps(text: "Acciones")
            Button("Guardar versión") {
                versionName = "\(screen.label) v\(editor.versions(for: screen).count + 1)"
                isVersionPresented = true
            }
            .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))

            Button("Mensajes del sistema") { isMessagesPresented = true }
                .buttonStyle(LabButtonStyle(kind: .soft, isCompact: true))

            Button("Restablecer pantalla") { isResetPresented = true }
                .buttonStyle(LabButtonStyle(kind: .danger, isCompact: true))
                .disabled(!editor.hasChanges(screen))

            Text(EditorRules.publishNotice)
                .font(.caption2)
                .foregroundStyle(LabTone.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .labPanel()
        .alert("Guardar versión", isPresented: $isVersionPresented) {
            TextField("Nombre", text: $versionName)
            Button("Guardar") { editor.saveVersion(name: versionName, screen: screen) }
            Button("Cancelar", role: .cancel) {}
        }
        .confirmationDialog(
            "¿Restablecer el diseño original de \(screen.label)?",
            isPresented: $isResetPresented,
            titleVisibility: .visible
        ) {
            Button("Restablecer pantalla", role: .destructive) { editor.resetScreen(screen) }
            Button("Cancelar", role: .cancel) {}
        }
    }
}

// MARK: - Attachment

extension View {
    /// Puts the floating access on top of an operational interface. It draws nothing when
    /// the editor is locked, so the layout of the real app is untouched.
    func editorFloatingAccess(_ screen: EditorScreen) -> some View {
        overlay { EditorFloatingHandle(screen: screen) }
    }
}
