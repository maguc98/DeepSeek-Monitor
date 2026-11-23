import SwiftUI
import Charts

private struct TokenSlice: Identifiable {
    let name: String
    let value: Int
    var id: String { name }
}

struct TokenCompositionPanel: View {
    let inputTokens: Int
    let cacheHitTokens: Int
    let cacheMissTokens: Int
    let outputTokens: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var totalProgress: Double = 0

    private var animatedTotal: Int {
        Int((Double(total) * totalProgress).rounded())
    }

    private func replayTotal() {
        guard !reduceMotion else {
            totalProgress = 1
            return
        }
        totalProgress = 0
        withAnimation(.easeOut(duration: 0.92)) {
            totalProgress = 1
        }
    }

    private var slices: [TokenSlice] {
        let plainInput = max(0, inputTokens - cacheHitTokens - cacheMissTokens)
        return [
            TokenSlice(name: "普通输入", value: plainInput),
            TokenSlice(name: "缓存命中", value: cacheHitTokens),
            TokenSlice(name: "缓存未命中", value: cacheMissTokens),
            TokenSlice(name: "输出", value: outputTokens)
        ].filter { $0.value > 0 }
    }

    private var total: Int { slices.reduce(0) { $0 + $1.value } }
    private var cacheTotal: Int { cacheHitTokens + cacheMissTokens }
    private var hitRate: Double? {
        guard cacheTotal > 0 else { return nil }
        return Double(cacheHitTokens) / Double(cacheTotal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Token 构成")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DSTheme.ink)
                Text("区分普通输入、缓存命中、缓存未命中与输出")
                    .font(.system(size: 11))
                    .foregroundStyle(DSTheme.secondary)
            }

            if slices.isEmpty {
                EmptyDataPanel(title: "暂无 Token 构成", message: "平台尚未返回可用于绘制的 Token 分类数据。", icon: "chart.pie")
            } else {
                Chart(slices) { slice in
                    SectorMark(
                        angle: .value("Token", slice.value),
                        innerRadius: .ratio(0.68),
                        angularInset: 2
                    )
                    .foregroundStyle(by: .value("类型", slice.name))
                }
                .frame(height: 200)
                .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
                .transaction { transaction in transaction.animation = nil }
                .dsSweepReveal(key: "\(total)|\(slices.map { "\($0.name):\($0.value)" }.joined(separator: "|"))")
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
                .overlay {
                    GeometryReader { geometry in
                        VStack(spacing: 4) {
                            Text(animatedTotal.formatted())
                                .contentTransition(.numericText())
                                .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                                .tracking(-0.45)
                                .lineLimit(1)
                                .minimumScaleFactor(0.62)
                                .frame(maxWidth: geometry.size.width * 0.48)
                                .foregroundStyle(DSTheme.ink)
                            Text("总 Token")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(DSTheme.secondary)
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .allowsHitTesting(false)
                    }
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("缓存命中率")
                            .font(.system(size: 11))
                            .foregroundStyle(DSTheme.secondary)
                        Text(hitRate.map { $0.formatted(.percent.precision(.fractionLength(1))) } ?? "—")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(DSTheme.mint)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("缓存 Token")
                            .font(.system(size: 11))
                            .foregroundStyle(DSTheme.secondary)
                        Text(cacheTotal.formatted())
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(DSTheme.ink)
                    }
                }
                .padding(12)
                .background(DSTheme.canvas, in: RoundedRectangle(cornerRadius: 13))
                .dsEntrance(delay: 0.24)
            }
        }
        .padding(15)
        .dsCard()
        .onAppear(perform: replayTotal)
        .onChange(of: total) { _, _ in replayTotal() }
        .onChange(of: reduceMotion) { _, shouldReduce in
            if shouldReduce { totalProgress = 1 }
        }
    }
}

struct UsageHeatmapPanel: View {
    let days: [PlatformDailyUsage]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

    private func intensity(_ value: Int, maximum: Int) -> Double {
        guard maximum > 0, value > 0 else { return 0.06 }
        return 0.16 + 0.84 * Double(value) / Double(maximum)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Token 活跃热力图")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DSTheme.ink)
                Text("最近 30 天 · 颜色越深代表当日 Token 越多")
                    .font(.system(size: 11))
                    .foregroundStyle(DSTheme.secondary)
            }

            if days.isEmpty {
                EmptyDataPanel(title: "暂无活跃数据", message: "成功同步日级 Token 数据后，这里会显示每天的使用强度。", icon: "calendar")
            } else {
                let maximum = max(1, days.map(\.totalTokens).max() ?? 1)
                LazyVGrid(columns: columns, spacing: 7) {
                    ForEach(days) { day in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(DSTheme.blue.opacity(intensity(day.totalTokens, maximum: maximum)))
                                .frame(height: 25)
                                .animation(.easeInOut(duration: 0.38), value: day.totalTokens)
                                .overlay {
                                    if day.totalTokens == 0 {
                                        RoundedRectangle(cornerRadius: 5)
                                            .stroke(DSTheme.line, lineWidth: 0.7)
                                    }
                                }
                            Text(day.date.formatted(.dateTime.day()))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(DSTheme.secondary)
                        }
                        .accessibilityLabel("\(day.date.formatted(date: .abbreviated, time: .omitted))，\(day.totalTokens.formatted()) Token")
                    }
                }

                HStack {
                    Text("\(days.first?.date.formatted(date: .abbreviated, time: .omitted) ?? "")")
                    Spacer()
                    Text("低")
                    ForEach(0..<4, id: \.self) { step in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(DSTheme.blue.opacity(0.16 + Double(step) * 0.26))
                            .frame(width: 12, height: 12)
                    }
                    Text("高")
                    Spacer()
                    Text("\(days.last?.date.formatted(date: .abbreviated, time: .omitted) ?? "")")
                }
                .font(.system(size: 9))
                .foregroundStyle(DSTheme.secondary)
            }
        }
        .padding(15)
        .dsCard()
    }
}

struct TokenTrendComparisonPanel: View {
    let days: [PlatformDailyUsage]

    private var trendMaximum: Double {
        let maximum = days.reduce(0) { current, day in
            max(current, max(day.inputTokens, day.outputTokens))
        }
        return Double(max(1, maximum)) * 1.12
    }

    private var trendAnimationKey: String {
        days.map { "\($0.date.timeIntervalSince1970):\($0.inputTokens):\($0.outputTokens)" }.joined(separator: "|")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("输入与输出趋势")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DSTheme.ink)

            if days.isEmpty {
                EmptyDataPanel(title: "暂无趋势数据", message: "同步日级 Token 数据后即可比较输入与输出。")
            } else {
                Chart {
                    ForEach(days) { day in
                        AreaMark(
                            x: .value("日期", day.date),
                            y: .value("Token", day.inputTokens),
                            series: .value("类型", "输入")
                        )
                        .foregroundStyle(LinearGradient(
                            colors: [DSTheme.blue.opacity(0.17), DSTheme.blue.opacity(0.01)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        LineMark(
                            x: .value("日期", day.date),
                            y: .value("Token", day.inputTokens),
                            series: .value("类型", "输入")
                        )
                        .foregroundStyle(DSTheme.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.linear)

                        AreaMark(
                            x: .value("日期", day.date),
                            y: .value("Token", day.outputTokens),
                            series: .value("类型", "输出")
                        )
                        .foregroundStyle(LinearGradient(
                            colors: [DSTheme.purple.opacity(0.15), DSTheme.purple.opacity(0.01)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        LineMark(
                            x: .value("日期", day.date),
                            y: .value("Token", day.outputTokens),
                            series: .value("类型", "输出")
                        )
                        .foregroundStyle(DSTheme.purple)
                        .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.linear)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(DSTheme.line.opacity(0.8))
                        AxisValueLabel().foregroundStyle(DSTheme.secondary)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(.clear)
                        AxisValueLabel()
                            .foregroundStyle(DSTheme.secondary)
                            .offset(y: 4)
                    }
                }
                .chartYScale(domain: (-max(0.15, trendMaximum * 0.14))...trendMaximum)
                .chartPlotStyle { plot in plot.padding(.top, 12).padding(.trailing, 10) }
                .chartLegend(position: .bottom, alignment: .leading, spacing: 14)
                .frame(height: 226)
                .animation(DSMotion.data, value: trendAnimationKey)
                .dsChartReveal(key: trendAnimationKey)
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .padding(15)
        .dsCard()
    }
}

struct ModelRequestDistributionPanel: View {
    let models: [PlatformDailyModelUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("模型请求占比")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DSTheme.ink)
            let items = models.filter { $0.requests > 0 }
            if items.isEmpty {
                EmptyDataPanel(title: "暂无请求分布", message: "平台没有返回模型请求次数。", icon: "chart.pie")
            } else {
                Chart(items) { item in
                    SectorMark(
                        angle: .value("请求", item.requests),
                        innerRadius: .ratio(0.60),
                        angularInset: 2
                    )
                    .foregroundStyle(by: .value("模型", item.model))
                }
                .frame(height: 190)
                .chartLegend(position: .bottom, alignment: .leading)
                .transaction { transaction in transaction.animation = nil }
                .dsSweepReveal(key: items.map { "\($0.model):\($0.requests)" }.joined(separator: "|"))
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
                HStack {
                    Text("总请求数")
                        .font(.system(size: 11))
                        .foregroundStyle(DSTheme.secondary)
                    Spacer()
                    Text(items.reduce(0) { $0 + $1.requests }.formatted())
                        .contentTransition(.numericText())
                        .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(DSTheme.ink)
                        .animation(DSMotion.data, value: items.reduce(0) { $0 + $1.requests })
                }
            }
        }
        .padding(15)
        .dsCard()
    }
}

struct ModelTokenComparisonPanel: View {
    let models: [PlatformDailyModelUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("各模型 Token 对比")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DSTheme.ink)
            if models.isEmpty {
                EmptyDataPanel(title: "暂无模型 Token", message: "同步模型级 Token 数据后会显示排行。")
            } else {
                Chart {
                    ForEach(models) { model in
                        BarMark(
                            x: .value("Token", model.inputTokens),
                            y: .value("模型", model.model),
                            height: .ratio(0.34)
                        )
                        .foregroundStyle(DSTheme.blue)
                        .position(by: .value("类型", "输入"))

                        BarMark(
                            x: .value("Token", model.outputTokens),
                            y: .value("模型", model.model),
                            height: .ratio(0.34)
                        )
                        .foregroundStyle(DSTheme.purple)
                        .position(by: .value("类型", "输出"))
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .chartXScale(domain: 0...max(1, models.map { max($0.inputTokens, $0.outputTokens) }.max() ?? 1))
                .frame(height: CGFloat(max(150, models.count * 48)))
                .animation(DSMotion.data, value: models.reduce(0) { $0 + $1.inputTokens + $1.outputTokens })
                .dsChartReveal(key: models.map { "\($0.model):\($0.inputTokens):\($0.outputTokens)" }.joined(separator: "|"))
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .padding(15)
        .dsCard()
    }
}
