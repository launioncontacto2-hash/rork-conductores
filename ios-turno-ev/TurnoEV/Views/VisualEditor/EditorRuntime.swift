import SwiftUI
import UIKit

/// The canvas. A screen declares its blocks once and this container decides how they are
/// drawn: order, width, height, visibility, card model, chart shape and data source all
/// come from the editor's design, never from the screen itself.

// MARK: - Blocks

/// What the canvas has to draw for one element.
enum EditorContent {
    /// A view the screen owns, kept **unbuilt**. The editor can move, resize, hide or
    /// delete it.
    ///
    /// The closure is the whole point. Holding an `AnyView` meant the screen's
    /// `@ViewBuilder` ran the moment `blocks(...)` was called — before `EditorStack` had
    /// looked at the design and decided which elements it actually draws. Every block of
    /// the screen was materialised on every pass, including the ones the editor had hidden
    /// or deleted. Holding the builder instead defers that to the block that really mounts.
    case custom(() -> AnyView)
    /// A number the editor can re-draw with any of the eight card models.
    case kpi(EditorMetricSample)
    /// A data set the editor can re-draw with any compatible chart.
    case chart(EditorSeries)
}

/// A value with the shape a KPI needs, so the editor can point a card at another metric
/// without the screen knowing.
struct EditorMetricSample: Sendable {
    var value: String
    var caption: String?
    var progress: Double?

    init(value: String, caption: String? = nil, progress: Double? = nil) {
        self.value = value
        self.caption = caption
        self.progress = progress
    }
}

struct EditorBlock: Identifiable {
    let ref: EditorElementRef
    let content: EditorContent
    /// When true the canvas draws an editable title and subtitle above the content.
    var showsHeader: Bool = false

    var id: String { ref.id }

    /// A block the screen draws itself.
    static func custom(
        _ id: String,
        _ title: String,
        kind: EditorElementKind = .card,
        isCritical: Bool = false,
        width: EditorWidth = .full,
        @ViewBuilder content: @escaping () -> some View
    ) -> EditorBlock {
        EditorBlock(
            ref: EditorElementRef(
                id: id,
                title: title,
                kind: kind,
                isCritical: isCritical,
                defaultWidth: width,
                supportsDuplicate: false
            ),
            // Wrapped, not called: `content()` runs inside `EditorElementBody`, which only
            // exists for a block that survived the design's order, visibility and deletions.
            content: .custom { AnyView(content()) }
        )
    }

    /// A number. The canvas owns the drawing, so the model library applies.
    static func kpi(
        _ id: String,
        _ title: String,
        metric: EditorMetric,
        value: String,
        caption: String? = nil,
        progress: Double? = nil,
        width: EditorWidth = .half,
        model: EditorCardModel = .compact,
        isCritical: Bool = false
    ) -> EditorBlock {
        EditorBlock(
            ref: EditorElementRef(
                id: id,
                title: title,
                subtitle: caption,
                kind: .kpi,
                isCritical: isCritical,
                metric: metric,
                defaultWidth: width,
                defaultCardModel: model,
                supportsCardLibrary: true,
                supportsDataSource: true
            ),
            content: .kpi(EditorMetricSample(value: value, caption: caption, progress: progress))
        )
    }

    /// A data set. The canvas owns the drawing, so the chart library applies.
    static func chart(
        _ id: String,
        _ title: String,
        subtitle: String? = nil,
        series: EditorSeries,
        kind: EditorChartKind = .verticalBars,
        width: EditorWidth = .full
    ) -> EditorBlock {
        EditorBlock(
            ref: EditorElementRef(
                id: id,
                title: title,
                subtitle: subtitle,
                kind: .chart,
                defaultWidth: width,
                defaultChartKind: kind,
                supportsChartLibrary: true
            ),
            content: .chart(series),
            showsHeader: true
        )
    }
}

// MARK: - Canvas

struct EditorStack: View {
    let screen: EditorScreen
    let blocks: [EditorBlock]
    /// Resolves any metric of the controlled list, so a card pointed at another number
    /// still shows a real value.
    var sample: (EditorMetric) -> EditorMetricSample = { _ in EditorMetricSample(value: "—") }

    @Environment(VisualEditorStore.self) private var editor
    @State private var dropTarget: String?

    private var isLive: Bool { editor.isLive }

    /// Base blocks plus everything the editor added, in the order the design says.
    private var ordered: [EditorBlock] {
        let layout = editor.layout(screen)
        var all = blocks

        for added in layout.added {
            let source = blocks.first { $0.id == added.sourceId }
            all.append(
                EditorBlock(
                    ref: EditorElementRef(
                        id: added.id,
                        title: added.title,
                        kind: added.kind,
                        isAdded: true,
                        metric: added.metric,
                        defaultWidth: added.width,
                        defaultCardModel: added.cardModel,
                        supportsCardLibrary: true,
                        supportsDataSource: true
                    ),
                    content: source.flatMap { block -> EditorContent? in
                        if case .chart = block.content { return block.content }
                        return nil
                    } ?? .kpi(sample(added.metric))
                )
            )
        }

        let baseOrder = Dictionary(uniqueKeysWithValues: all.enumerated().map { ($0.element.id, $0.offset) })
        return all.sorted { left, right in
            let leftOrder = layout.overrides[left.id]?.order ?? baseOrder[left.id] ?? 0
            let rightOrder = layout.overrides[right.id]?.order ?? baseOrder[right.id] ?? 0
            if leftOrder == rightOrder { return (baseOrder[left.id] ?? 0) < (baseOrder[right.id] ?? 0) }
            return leftOrder < rightOrder
        }
    }

    /// What actually reaches the screen: deleted elements are gone and hidden ones only
    /// survive as a ghost while the administrator is editing.
    private var visible: [EditorBlock] {
        ordered.filter { block in
            let rules = editor.override(screen, block.id)
            if rules.isDeleted { return false }
            if rules.isHidden { return isLive }
            return true
        }
    }

    var body: some View {
        // Two paths on purpose. With the editor off — which is every real session — the
        // canvas is a plain stack: no gestures, no overlays, no drag targets, no
        // animation. All the editing machinery only exists while an administrator is
        // actually editing.
        if editor.isEditing {
            editingStack
        } else {
            plainStack
        }
    }

    private var plainStack: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { item in
                EditorRowLayout(spacing: 10) {
                    ForEach(item.element) { block in
                        EditorElementBody(
                            screen: screen,
                            block: block,
                            rules: editor.override(screen, block.id),
                            sample: sample
                        )
                        .frame(minHeight: minimumHeight(block))
                        .layoutValue(key: EditorSpanKey.self, value: columns(block))
                        .id(block.id)
                    }
                }
                .padding(.bottom, rowSpacing(item.element))
            }
        }
    }

    private var editingStack: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { item in
                EditorRowLayout(spacing: 10) {
                    ForEach(item.element) { block in
                        cell(block)
                            .layoutValue(key: EditorSpanKey.self, value: columns(block))
                            .id(block.id)
                    }
                }
                .padding(.bottom, rowSpacing(item.element))
            }

            if isLive {
                dropTail
            }
        }
        .animation(.smooth(duration: 0.28), value: editor.layout(screen))
    }

    private func minimumHeight(_ block: EditorBlock) -> CGFloat? {
        (editor.override(screen, block.id).height?.minimum).map { CGFloat($0) }
    }

    /// Packs the elements into four-column rows without ever letting one overflow.
    private var rows: [[EditorBlock]] {
        var packed: [[EditorBlock]] = []
        var current: [EditorBlock] = []
        var used = 0

        for block in visible {
            let span = columns(block)
            if used + span > 4, !current.isEmpty {
                packed.append(current)
                current = []
                used = 0
            }
            current.append(block)
            used += span
        }
        if !current.isEmpty { packed.append(current) }
        return packed
    }

    private func columns(_ block: EditorBlock) -> Int {
        (editor.override(screen, block.id).width ?? block.ref.defaultWidth).columns
    }

    private func rowSpacing(_ row: [EditorBlock]) -> Double {
        row.compactMap { editor.override(screen, $0.id).spacing?.value }.max() ?? EditorSpacing.normal.value
    }

    // MARK: - One element

    @ViewBuilder
    private func cell(_ block: EditorBlock) -> some View {
        let rules = editor.override(screen, block.id)
        let isSelected = editor.selection == EditorSelection(screen: screen, elementId: block.id)

        VStack(alignment: .leading, spacing: 0) {
            if dropTarget == block.id, isLive { EditorDropGuide() }

            EditorElementBody(
                screen: screen,
                block: block,
                rules: rules,
                sample: sample
            )
            .frame(minHeight: minimumHeight(block))
            .opacity(rules.isHidden ? 0.32 : 1)
            .overlay(alignment: .topLeading) {
                if isLive, rules.isHidden { EditorHiddenTag() }
            }
            .overlay {
                if isLive {
                    EditorSelectionChrome(
                        block: block,
                        isSelected: isSelected,
                        width: rules.width ?? block.ref.defaultWidth
                    )
                }
            }
            .contentShape(.rect)
            .onLongPressGesture(minimumDuration: 0.32) {
                guard isLive else { return }
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                editor.selection = EditorSelection(screen: screen, elementId: block.id)
            }
        }
        .modifier(
            EditorDragging(
                isEnabled: isLive,
                id: block.id,
                onDrop: { moved in place(moved, before: block) },
                isTargeted: Binding(
                    get: { dropTarget == block.id },
                    set: { dropTarget = $0 ? block.id : (dropTarget == block.id ? nil : dropTarget) }
                )
            )
        )
    }

    /// Tail slot, so an element can be dropped at the very end of the screen.
    private var dropTail: some View {
        Color.clear
            .frame(height: dropTarget == "__tail" ? 46 : 26)
            .overlay {
                if dropTarget == "__tail" { EditorDropGuide() }
            }
            .dropDestination(for: String.self) { items, _ in
                guard let moved = items.first else { return false }
                place(moved, before: nil)
                return true
            } isTargeted: { targeted in
                dropTarget = targeted ? "__tail" : (dropTarget == "__tail" ? nil : dropTarget)
            }
    }

    private func place(_ movedId: String, before block: EditorBlock?) {
        let sequence = ordered
        guard let moved = sequence.first(where: { $0.id == movedId }) else { return }
        let refs = sequence.map(\.ref)
        let target = block.flatMap { destination in sequence.firstIndex { $0.id == destination.id } } ?? sequence.count - 1
        editor.move(element: moved.ref, to: target, screen: screen, ordered: refs)
        dropTarget = nil
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}

/// Drag and drop is only wired while the editor is live, so a driver never picks up a card.
private struct EditorDragging: ViewModifier {
    let isEnabled: Bool
    let id: String
    let onDrop: (String) -> Void
    @Binding var isTargeted: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .draggable(id) {
                    Image(systemName: "square.on.square.dashed")
                        .font(.title2)
                        .padding(16)
                        .background(LabTone.accent.opacity(0.9), in: .rect(cornerRadius: 14))
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let moved = items.first, moved != id else { return false }
                    onDrop(moved)
                    return true
                } isTargeted: { isTargeted = $0 }
        } else {
            content
        }
    }
}

// MARK: - Element body

private struct EditorElementBody: View {
    let screen: EditorScreen
    let block: EditorBlock
    let rules: EditorOverride
    let sample: (EditorMetric) -> EditorMetricSample

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if block.showsHeader {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rules.title ?? block.ref.title)
                        .font(.system(.subheadline, weight: .black))
                    if let subtitle = rules.subtitle ?? block.ref.subtitle {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textMuted)
                    }
                }
            }

            content
        }
        .padding(block.showsHeader ? 16 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(EditorPanelBackground(isOn: block.showsHeader))
    }

    @ViewBuilder
    private var content: some View {
        switch block.content {
        case .custom(let build):
            // The screen's `@ViewBuilder` runs here, at the point of use.
            build()

        case .kpi(let original):
            let metric = rules.metric ?? block.ref.metric
            let resolved = rules.metric == nil ? original : sample(rules.metric ?? .earningsToday)
            EditorCardView(
                model: rules.cardModel ?? block.ref.defaultCardModel,
                title: rules.title ?? (rules.metric?.label ?? block.ref.title),
                value: resolved.value,
                caption: rules.subtitle ?? resolved.caption,
                progress: resolved.progress,
                symbol: metric?.symbol ?? "square.grid.2x2.fill"
            )

        case .chart(let series):
            EditorChartView(
                kind: resolvedChart(for: series),
                series: series,
                options: EditorChartOptions(
                    showsValues: rules.showsValues ?? true,
                    showsLegend: rules.showsLegend ?? false,
                    showsLabels: rules.showsLabels ?? true,
                    height: chartHeight
                )
            )
        }
    }

    /// Never render a shape the data cannot support, even if an old design asked for it.
    private func resolvedChart(for series: EditorSeries) -> EditorChartKind {
        let requested = rules.chartKind ?? block.ref.defaultChartKind
        let available = EditorChartKind.available(for: series)
        return available.contains(requested) ? requested : (available.first ?? .verticalBars)
    }

    private var chartHeight: Double {
        switch rules.height ?? .normal {
        case .compact: 96
        case .automatic, .normal: 150
        case .large: 210
        }
    }
}

private struct EditorPanelBackground: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content.panel()
        } else {
            content
        }
    }
}

// MARK: - Chrome

/// Dashed frame, name tag and the ••• button of a selected element.
private struct EditorSelectionChrome: View {
    let block: EditorBlock
    let isSelected: Bool
    let width: EditorWidth

    @Environment(VisualEditorStore.self) private var editor
    @State private var isInspectorPresented: Bool = false

    private var tint: Color { block.ref.isCritical ? LabTone.bad : LabTone.accent }

    var body: some View {
        RoundedRectangle(cornerRadius: 18)
            .strokeBorder(
                tint.opacity(isSelected ? 0.95 : 0.35),
                style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: isSelected ? [] : [4, 4])
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    HStack(spacing: 6) {
                        Text(width.label)
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(LabTone.canvas)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(tint, in: .capsule)

                        Button {
                            isInspectorPresented = true
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(LabTone.canvas)
                                .frame(width: 26, height: 22)
                                .background(tint, in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                    .offset(x: -6, y: -10)
                }
            }
            .overlay(alignment: .topLeading) {
                if isSelected {
                    HStack(spacing: 4) {
                        Image(systemName: block.ref.isCritical ? "lock.fill" : block.ref.kind.symbol)
                            .font(.system(size: 8, weight: .black))
                        Text(block.ref.isCritical ? "CRÍTICO" : block.ref.kind.label.uppercased())
                            .font(.system(size: 8, weight: .black))
                            .tracking(0.8)
                    }
                    .foregroundStyle(LabTone.canvas)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(tint, in: .capsule)
                    .offset(x: 8, y: -9)
                }
            }
            .allowsHitTesting(isSelected)
            .sheet(isPresented: $isInspectorPresented) {
                EditorInspectorView(block: block)
            }
    }
}

private struct EditorHiddenTag: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 8, weight: .black))
            Text("OCULTO")
                .font(.system(size: 8, weight: .black))
                .tracking(0.8)
        }
        .foregroundStyle(LabTone.canvas)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(LabTone.cool, in: .capsule)
        .padding(6)
    }
}

/// Alignment guide shown where the dragged element is going to land.
private struct EditorDropGuide: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(LabTone.accent)
                .frame(width: 7, height: 7)
            Capsule()
                .fill(LabTone.accent)
                .frame(height: 3)
            Circle()
                .fill(LabTone.accent)
                .frame(width: 7, height: 7)
        }
        .padding(.vertical, 7)
        .transition(.opacity)
    }
}

// MARK: - Grid layout

struct EditorSpanKey: LayoutValueKey {
    static let defaultValue: Int = 4
}

/// Four-column row. Each element takes the exact fraction its span asks for, so the grid
/// stays honest on every device instead of stretching to fill.
struct EditorRowLayout: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.replacingUnspecifiedDimensions().width
        let widths = widths(for: subviews, total: total)
        let height = zip(subviews, widths).map { subview, width in
            subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        }.max() ?? 0
        return CGSize(width: total, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = widths(for: subviews, total: bounds.width)
        var x = bounds.minX
        for (index, subview) in subviews.enumerated() {
            let width = widths[index]
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                proposal: ProposedViewSize(width: width, height: nil)
            )
            x += width + spacing
        }
    }

    private func widths(for subviews: Subviews, total: CGFloat) -> [CGFloat] {
        let gaps = spacing * CGFloat(max(0, subviews.count - 1))
        let available = max(0, total - gaps)
        let spans = subviews.map { CGFloat($0[EditorSpanKey.self]) }
        let requested = spans.reduce(0, +)
        // A row never asks for more than the four columns it has.
        let divisor = max(4, requested)
        return spans.map { available * $0 / divisor }
    }
}

// MARK: - Screen chrome

/// Banner every edited interface wears while the mode is on, plus the quick controls the
/// administrator needs without going back to the console.
struct EditorModeBar: View {
    let screen: EditorScreen

    @Environment(VisualEditorStore.self) private var editor
    @State private var isLibraryPresented: Bool = false

    var body: some View {
        if editor.isEditing {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: editor.isPreviewing ? "eye.fill" : "square.dashed.inset.filled")
                            .font(.system(size: 10, weight: .black))
                        Text(editor.isPreviewing ? "PREVISUALIZANDO" : "MODO EDITOR")
                            .font(.system(size: 10, weight: .black))
                            .tracking(1.1)
                    }
                    .foregroundStyle(LabTone.canvas)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(editor.isPreviewing ? LabTone.cool : LabTone.accent, in: .capsule)

                    Text(screen.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(LabTone.accentSoft)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    barButton("arrow.uturn.backward", enabled: editor.canUndo) { editor.undo() }
                    barButton("arrow.uturn.forward", enabled: editor.canRedo) { editor.redo() }
                    barButton("plus.square.on.square", enabled: !editor.isPreviewing) { isLibraryPresented = true }
                    barButton(editor.isPreviewing ? "pencil" : "eye") {
                        editor.isPreviewing.toggle()
                        editor.selection = nil
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(LabTone.surface.opacity(0.97))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(LabTone.accent.opacity(0.5)).frame(height: 1)
                }
            }
            .sheet(isPresented: $isLibraryPresented) {
                EditorComponentLibraryView(screen: screen)
            }
        }
    }

    private func barButton(_ symbol: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(enabled ? LabTone.accent : LabTone.muted.opacity(0.5))
                .frame(width: 30, height: 26)
                .background(LabTone.raised, in: .rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

extension View {
    /// Puts a screen under the editor: the bar on top and the tap-to-deselect behaviour.
    func editorScreen(_ screen: EditorScreen) -> some View {
        modifier(EditorScreenModifier(screen: screen))
    }
}

private struct EditorScreenModifier: ViewModifier {
    let screen: EditorScreen
    @Environment(VisualEditorStore.self) private var editor

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            EditorModeBar(screen: screen)
            content
        }
        .onDisappear {
            if editor.selection?.screen == screen { editor.selection = nil }
        }
    }
}
