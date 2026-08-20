import SwiftUI

/// The eight card models and the ten chart shapes the editor can swap between.
/// Both families read the same value the screen already computed: changing the model
/// changes the drawing, never the source of the number.

// MARK: - Cards

struct EditorCardView: View {
    let model: EditorCardModel
    let title: String
    let value: String
    var caption: String?
    var progress: Double?
    var symbol: String = "square.grid.2x2.fill"
    var tint: Color = Palette.volt

    var body: some View {
        switch model {
        case .compact: compact
        case .bigNumber: bigNumber
        case .horizontal: horizontal
        case .progress: progressCard
        case .icon: iconCard
        case .minimal: minimal
        case .featured: featured
        case .alert: alert
        }
    }

    private var compact: some View {
        VStack(alignment: .leading, spacing: 5) {
            CapsLabel(text: title)
            Text(value)
                .font(.system(.title3, weight: .black))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption {
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .panelFlat(cornerRadius: 18)
    }

    private var bigNumber: some View {
        VStack(alignment: .leading, spacing: 2) {
            CapsLabel(text: title)
            Text(value)
                .font(.system(size: 38, weight: .black))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let caption {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panel(cornerRadius: 20)
    }

    private var horizontal: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.footnote, weight: .bold))
                if let caption {
                    Text(caption)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textMuted)
                }
            }
            Spacer(minLength: 8)
            Text(value)
                .font(.system(.title3, weight: .black))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .panelFlat(cornerRadius: 18)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                CapsLabel(text: title)
                Spacer(minLength: 4)
                Text(value)
                    .font(.system(.subheadline, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            EditorTrack(progress: progress ?? 0, tint: tint)
            if let caption {
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .panel(cornerRadius: 20)
    }

    private var iconCard: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(.title3, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 46, height: 46)
                .background(tint.opacity(0.13), in: .rect(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(.title3, weight: .black))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(cornerRadius: 20)
    }

    private var minimal: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(.title3, weight: .black))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title.uppercased())
                .font(.system(size: 9, weight: .black))
                .tracking(1)
                .foregroundStyle(Palette.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    private var featured: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.2)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Palette.canvas.opacity(0.75))

            Text(value)
                .font(.system(size: 34, weight: .black))
                .monospacedDigit()
                .foregroundStyle(Palette.canvas)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            if let caption {
                Text(caption)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.canvas.opacity(0.75))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [tint, tint.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 22)
        )
    }

    private var alert: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(Palette.amber)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(.footnote, weight: .black))
                    Spacer(minLength: 4)
                    Text(value)
                        .font(.system(.subheadline, weight: .black))
                        .monospacedDigit()
                        .foregroundStyle(Palette.amber)
                }
                if let caption {
                    Text(caption)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.amber.opacity(0.10), in: .rect(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(Palette.amber.opacity(0.4), lineWidth: 1) }
    }
}

private struct EditorTrack: View {
    let progress: Double
    var tint: Color = Palette.volt

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.surfaceRaised)
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * max(0, min(1, progress)))
            }
        }
        .frame(height: 8)
    }
}

// MARK: - Charts

/// How a chart is configured once the administrator has touched it.
struct EditorChartOptions: Sendable {
    var showsValues: Bool = true
    var showsLegend: Bool = false
    var showsLabels: Bool = true
    var height: Double = 150
}

struct EditorChartView: View {
    let kind: EditorChartKind
    let series: EditorSeries
    var options: EditorChartOptions = EditorChartOptions()
    var tint: Color = Palette.volt

    var body: some View {
        VStack(spacing: 10) {
            chart
            if options.showsLegend { legend }
        }
    }

    @ViewBuilder
    private var chart: some View {
        switch kind {
        case .verticalBars: verticalBars
        case .horizontalBars: horizontalBars
        case .line: EditorLineChart(series: series, tint: tint, filled: false, options: options)
        case .area: EditorLineChart(series: series, tint: tint, filled: true, options: options)
        case .donut: EditorPieChart(series: series, tint: tint, isDonut: true, options: options)
        case .pie: EditorPieChart(series: series, tint: tint, isDonut: false, options: options)
        case .radialProgress: radialProgress
        case .progressBar: progressBar
        case .kpiCards: kpiCards
        case .number: number
        }
    }

    private var peak: Double { max(series.peak, 1) }

    private var verticalBars: some View {
        HStack(alignment: .bottom, spacing: 7) {
            ForEach(series.points) { point in
                VStack(spacing: 5) {
                    if options.showsValues {
                        Text(series.formatted(point.value))
                            .font(.system(size: 8, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    RoundedRectangle(cornerRadius: 6)
                        .fill(point.isHighlighted ? tint : tint.opacity(0.45))
                        .frame(height: max(4, options.height * 0.72 * (point.value / peak)))
                    if options.showsLabels {
                        Text(point.label)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(point.isHighlighted ? tint : Palette.textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: options.height, alignment: .bottom)
    }

    private var horizontalBars: some View {
        VStack(spacing: 7) {
            ForEach(series.points) { point in
                HStack(spacing: 8) {
                    if options.showsLabels {
                        Text(point.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.textMuted)
                            .frame(width: 46, alignment: .leading)
                            .lineLimit(1)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.surfaceRaised)
                            Capsule()
                                .fill(point.isHighlighted ? tint : tint.opacity(0.5))
                                .frame(width: proxy.size.width * (point.value / peak))
                        }
                    }
                    .frame(height: 12)
                    if options.showsValues {
                        Text(series.formatted(point.value))
                            .font(.system(size: 10, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.textMuted)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var radialProgress: some View {
        let goal = max(series.totalGoal ?? series.total, 1)
        return RingGauge(
            value: series.total,
            goal: goal,
            headline: series.formatted(series.total),
            caption: "de \(series.formatted(goal))"
        )
        .frame(height: options.height + 30)
    }

    private var progressBar: some View {
        let goal = max(series.totalGoal ?? series.total, 1)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(series.formatted(series.total))
                    .font(.system(.title3, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                Spacer()
                if options.showsValues {
                    Text("de \(series.formatted(goal))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.textMuted)
                }
            }
            ProgressTrack(value: series.total, goal: goal)
        }
    }

    private var kpiCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
            ForEach(series.points) { point in
                VStack(alignment: .leading, spacing: 3) {
                    Text(point.label.uppercased())
                        .font(.system(size: 9, weight: .black))
                        .tracking(0.8)
                        .foregroundStyle(Palette.textMuted)
                        .lineLimit(1)
                    Text(series.formatted(point.value))
                        .font(.system(.subheadline, weight: .black))
                        .monospacedDigit()
                        .foregroundStyle(point.isHighlighted ? tint : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .panelFlat(cornerRadius: 14)
            }
        }
    }

    private var number: some View {
        VStack(spacing: 3) {
            Text(series.formatted(series.total))
                .font(.system(size: 40, weight: .black))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if options.showsLabels {
                Text("\(series.points.count) periodos")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var legend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(series.points) { point in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(point.isHighlighted ? tint : tint.opacity(0.45))
                            .frame(width: 7, height: 7)
                        Text(point.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.textMuted)
                    }
                }
            }
        }
        .scrollClipDisabled()
    }
}

private struct EditorLineChart: View {
    let series: EditorSeries
    let tint: Color
    let filled: Bool
    let options: EditorChartOptions

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let peak = max(series.peak, 1)
                let points = series.points
                let stepX = points.count > 1 ? proxy.size.width / CGFloat(points.count - 1) : 0
                let coordinates = points.enumerated().map { index, point in
                    CGPoint(
                        x: CGFloat(index) * stepX,
                        y: proxy.size.height * (1 - CGFloat(point.value / peak))
                    )
                }

                ZStack {
                    if filled {
                        Path { path in
                            guard let first = coordinates.first else { return }
                            path.move(to: CGPoint(x: first.x, y: proxy.size.height))
                            for point in coordinates { path.addLine(to: point) }
                            path.addLine(to: CGPoint(x: coordinates.last?.x ?? 0, y: proxy.size.height))
                            path.closeSubpath()
                        }
                        .fill(LinearGradient(colors: [tint.opacity(0.38), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    }

                    Path { path in
                        guard let first = coordinates.first else { return }
                        path.move(to: first)
                        for point in coordinates.dropFirst() { path.addLine(to: point) }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                    ForEach(Array(coordinates.enumerated()), id: \.offset) { item in
                        Circle()
                            .fill(tint)
                            .frame(width: 6, height: 6)
                            .position(item.element)
                    }
                }
            }
            .frame(height: options.height)

            if options.showsLabels {
                HStack(spacing: 0) {
                    ForEach(series.points) { point in
                        Text(point.label)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Palette.textMuted)
                            .frame(maxWidth: .infinity)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
        }
    }
}

private struct EditorPieChart: View {
    let series: EditorSeries
    let tint: Color
    let isDonut: Bool
    let options: EditorChartOptions

    var body: some View {
        let total = max(series.total, 1)
        HStack(spacing: 16) {
            ZStack {
                ForEach(Array(slices(total: total).enumerated()), id: \.offset) { item in
                    Circle()
                        .trim(from: item.element.start, to: item.element.end)
                        .stroke(
                            tint.opacity(1 - Double(item.offset) * 0.13),
                            style: StrokeStyle(lineWidth: isDonut ? 26 : 70, lineCap: .butt)
                        )
                        .rotationEffect(.degrees(-90))
                }
                if isDonut, options.showsValues {
                    VStack(spacing: 1) {
                        Text(series.formatted(series.total))
                            .font(.system(.footnote, weight: .black))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("total")
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.textMuted)
                    }
                }
            }
            .frame(width: options.height, height: options.height)
            .padding(isDonut ? 13 : 35)

            if options.showsLabels {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(series.points.enumerated()), id: \.element.id) { item in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(tint.opacity(1 - Double(item.offset) * 0.13))
                                .frame(width: 8, height: 8)
                            Text(item.element.label)
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if options.showsValues {
                                Text(series.formatted(item.element.value))
                                    .font(.system(size: 10, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.textMuted)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func slices(total: Double) -> [(start: Double, end: Double)] {
        var cursor: Double = 0
        return series.points.map { point in
            let fraction = point.value / total
            let slice = (start: cursor, end: min(1, cursor + fraction))
            cursor += fraction
            return slice
        }
    }
}
