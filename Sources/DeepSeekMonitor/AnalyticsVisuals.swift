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
                        innerRadius: .ratio(0.62),
                        angularInset: 2
                    )
                    .foregroundStyle(by: .value("类型", slice.name))
                }
                .frame(height: 190)
                .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
                .overlay {
                    VStack(spacing: 3) {
                        Text(total.formatted())
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(DSTheme.ink)
                        Text("总 Token")
                            .font(.system(size: 10))
                            .foregroundStyle(DSTheme.secondary)
                    }
                    .allowsHitTesting(false)
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
            }
        }
        .padding(15)
        .dsCard()
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
                        .foregroundStyle(DSTheme.blue.opacity(0.12))
                        LineMark(
                            x: .value("日期", day.date),
                            y: .value("Token", day.inputTokens),
                            series: .value("类型", "输入")
                        )
                        .foregroundStyle(DSTheme.blue)
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("日期", day.date),
                            y: .value("Token", day.outputTokens),
                            series: .value("类型", "输出")
                        )
                        .foregroundStyle(DSTheme.purple.opacity(0.10))
                        LineMark(
                            x: .value("日期", day.date),
                            y: .value("Token", day.outputTokens),
                            series: .value("类型", "输出")
                        )
                        .foregroundStyle(DSTheme.purple)
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 190)
            }
        }
        .padding(15)
        .dsCard()
    }
}
