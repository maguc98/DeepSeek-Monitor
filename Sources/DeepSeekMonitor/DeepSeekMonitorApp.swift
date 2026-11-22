import SwiftUI
import WebKit
import Charts

@main
struct DeepSeekMonitorApp: App {
    @StateObject private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .preferredColorScheme(.light)
        }
    }
}

// MARK: - Session

enum RootRoute { case welcome, login, dashboard }

enum AccountConnectionState {
    case notConnected
    case awaitingVerification
    case connected

    var title: String {
        switch self {
        case .notConnected: return "尚未连接"
        case .awaitingVerification: return "等待账户校验"
        case .connected: return "已连接"
        }
    }
}

@MainActor
final class AppSession: ObservableObject {
    @Published var route: RootRoute = .welcome
    @Published var connectionState: AccountConnectionState = .notConnected
    @Published var dashboardData: PlatformDashboardData?
    @Published var connectionMessage: String?
    @Published var isSyncing = false

    let platformSession = DeepSeekPlatformSession()

    func beginLogin() {
        connectionMessage = nil
        route = .login
    }

    func finishLoginFlow() async {
        guard !isSyncing else { return }
        isSyncing = true
        connectionMessage = nil
        defer { isSyncing = false }

        do {
            dashboardData = try await platformSession.fetchDashboard()
            connectionState = .connected
            connectionMessage = dashboardData?.usageAvailable == true
                ? "账户与用量数据已同步。"
                : "账户会话有效，但用量统计接口暂未返回数据。"
            route = .dashboard
        } catch {
            connectionState = .awaitingVerification
            connectionMessage = error.localizedDescription
        }
    }

    func refreshPlatformData() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            dashboardData = try await platformSession.fetchDashboard()
            connectionState = .connected
            connectionMessage = dashboardData?.usageAvailable == true
                ? "数据同步完成。"
                : "账户已验证，但本次未获得用量统计数据。"
        } catch {
            connectionMessage = error.localizedDescription
            if dashboardData == nil {
                connectionState = .awaitingVerification
            }
        }
    }

    func signOut() {
        dashboardData = nil
        connectionMessage = nil
        connectionState = .notConnected
        route = .welcome
        Task { await platformSession.clearWebSession() }
    }
}

struct RootView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        Group {
            switch session.route {
            case .welcome:
                WelcomeView(onContinue: session.beginLogin)
            case .login:
                LoginView(
                    onCancel: { session.route = .welcome },
                    onFinished: session.finishLoginFlow
                )
            case .dashboard:
                DashboardShellView(onSignOut: session.signOut)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: routeKey)
    }

    private var routeKey: Int {
        switch session.route {
        case .welcome: return 0
        case .login: return 1
        case .dashboard: return 2
        }
    }
}

// MARK: - Visual system

enum DSTheme {
    static let canvas = Color(red: 0.965, green: 0.961, blue: 0.988)
    static let card = Color.white
    static let blue = Color(red: 0.24, green: 0.43, blue: 0.96)
    static let purple = Color(red: 0.48, green: 0.29, blue: 0.91)
    static let mint = Color(red: 0.19, green: 0.72, blue: 0.54)
    static let coral = Color(red: 0.94, green: 0.39, blue: 0.42)
    static let ink = Color(red: 0.12, green: 0.14, blue: 0.22)
    static let secondary = Color(red: 0.48, green: 0.49, blue: 0.57)
    static let line = Color(red: 0.91, green: 0.91, blue: 0.95)

    static let brandGradient = LinearGradient(
        colors: [blue, purple], startPoint: .leading, endPoint: .trailing
    )
}

extension View {
    func dsCard(_ radius: CGFloat = 19) -> some View {
        background(.white, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(DSTheme.line.opacity(0.65), lineWidth: 0.7)
            }
            .shadow(color: DSTheme.purple.opacity(0.045), radius: 13, x: 0, y: 6)
    }
}

struct PageHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundStyle(DSTheme.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(DSTheme.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
        .padding(.bottom, 2)
    }
}

struct EmptyDataPanel: View {
    let title: String
    let message: String
    var icon: String = "chart.xyaxis.line"

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(DSTheme.blue.opacity(0.8))
                .frame(width: 52, height: 52)
                .background(DSTheme.blue.opacity(0.08), in: Circle())
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DSTheme.ink)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(DSTheme.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 25)
        .padding(.horizontal, 18)
        .dsCard()
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 25, height: 25)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DSTheme.secondary)
            }
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(DSTheme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .dsCard(17)
    }
}

struct StatusBanner: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(DSTheme.blue)
                .font(.system(size: 17))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DSTheme.ink)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(DSTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(DSTheme.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 15))
    }
}

// MARK: - Welcome and sign-in

private struct WelcomeFeature: Identifiable {
    let icon: String
    let title: String
    var id: String { title }
}

struct WelcomeView: View {
    let onContinue: () -> Void

    private let features: [WelcomeFeature] = [
        WelcomeFeature(icon: "creditcard", title: "账户余额与消费"),
        WelcomeFeature(icon: "chart.xyaxis.line", title: "API 用量统计"),
        WelcomeFeature(icon: "waveform.path", title: "Token 使用分析"),
        WelcomeFeature(icon: "square.grid.2x2", title: "模型消耗排行"),
        WelcomeFeature(icon: "arrow.triangle.2.circlepath", title: "与官方平台同步")
    ]

    var body: some View {
        ZStack {
            DSTheme.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer(minLength: 38)
                ZStack {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(DSTheme.brandGradient)
                        .frame(width: 104, height: 104)
                        .shadow(color: DSTheme.purple.opacity(0.25), radius: 18, x: 0, y: 10)
                    Image(systemName: "water.waves")
                        .font(.system(size: 45, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text("DeepSeek Monitor")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(DSTheme.ink)
                    .padding(.top, 20)
                Text("DeepSeek 开发者平台监控")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DSTheme.secondary)
                    .padding(.top, 7)

                VStack(alignment: .leading, spacing: 17) {
                    ForEach(features) { feature in
                        HStack(spacing: 13) {
                            Image(systemName: feature.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(DSTheme.blue)
                                .frame(width: 30, height: 30)
                                .background(DSTheme.blue.opacity(0.09),
                                            in: RoundedRectangle(cornerRadius: 9))
                            Text(feature.title)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(DSTheme.ink)
                        }
                    }
                }
                .frame(maxWidth: 245, alignment: .leading)
                .padding(.top, 34)

                Spacer(minLength: 28)
                Button(action: onContinue) {
                    HStack(spacing: 9) {
                        Text("连接 DeepSeek 账户")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(DSTheme.brandGradient, in: Capsule())
                    .shadow(color: DSTheme.blue.opacity(0.2), radius: 12, x: 0, y: 6)
                }
                .padding(.horizontal, 28)
                Text("使用 DeepSeek 官方平台登录")
                    .font(.system(size: 12))
                    .foregroundStyle(DSTheme.secondary)
                    .padding(.top, 14)
                    .padding(.bottom, 34)
            }
            .padding(.horizontal, 24)
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var session: AppSession
    let onCancel: () -> Void
    let onFinished: () async -> Void
    @State private var checking = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("取消", action: onCancel)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DSTheme.blue)
                Spacer()
                Text("登录 DeepSeek")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DSTheme.ink)
                Spacer()
                Color.clear.frame(width: 34, height: 20)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)

            HStack(spacing: 7) {
                Image(systemName: "lock.fill").font(.system(size: 10))
                Text("platform.deepseek.com")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Image(systemName: "arrow.clockwise").font(.system(size: 12))
            }
            .foregroundStyle(DSTheme.secondary)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(DSTheme.canvas, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 15)
            .padding(.bottom, 8)

            PlatformLoginWebView(session: session.platformSession)

            VStack(spacing: 9) {
                if let message = session.connectionMessage,
                   session.connectionState != .connected {
                    StatusBanner(title: "连接验证未完成", message: message)
                }
                Button {
                    Task {
                        checking = true
                        await onFinished()
                        checking = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        if checking { ProgressView().tint(.white) }
                        Text(checking ? "正在验证账户…" : "我已完成登录，验证账户")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(DSTheme.brandGradient, in: Capsule())
                }
                .disabled(checking || session.isSyncing)
                Text("应用会在 DeepSeek 官方网页会话中读取账户统计，不会收集密码。")
                    .font(.system(size: 11))
                    .foregroundStyle(DSTheme.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .background(.white)
        }
        .background { Color.white.ignoresSafeArea() }
    }
}

private struct PlatformLoginWebView: UIViewRepresentable {
    let session: DeepSeekPlatformSession

    func makeUIView(context: Context) -> WKWebView {
        session.loadLoginPage()
        return session.webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        session.loadLoginPage()
    }
}

// MARK: - Dashboard tabs

enum DashboardTab: String, CaseIterable, Identifiable {
    case overview = "总览"
    case analytics = "统计"
    case models = "模型"
    case records = "记录"
    case settings = "设置"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "house"
        case .analytics: return "chart.bar"
        case .models: return "hexagon"
        case .records: return "doc.text"
        case .settings: return "gearshape"
        }
    }

    var selectedIcon: String {
        switch self {
        case .overview: return "house.fill"
        case .analytics: return "chart.bar.fill"
        case .models: return "hexagon.fill"
        case .records: return "doc.text.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct DashboardShellView: View {
    let onSignOut: () -> Void
    @State private var selectedTab: DashboardTab = .overview

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    switch selectedTab {
                    case .overview: OverviewView()
                    case .analytics: AnalyticsView()
                    case .models: ModelsView()
                    case .records: RecordsView()
                    case .settings: SettingsView(onSignOut: onSignOut)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(spacing: 0) {
                    ForEach(DashboardTab.allCases) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: selectedTab == tab ? tab.selectedIcon : tab.icon)
                                    .font(.system(size: 19, weight: .medium))
                                Text(tab.rawValue)
                                    .font(.system(size: 10,
                                                  weight: selectedTab == tab ? .semibold : .regular))
                            }
                            .foregroundStyle(selectedTab == tab ? DSTheme.blue : DSTheme.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 5)
                .background(.white)
                .overlay(alignment: .top) {
                    Rectangle().fill(DSTheme.line).frame(height: 0.7)
                }
            }
            .background(DSTheme.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - Overview

struct OverviewView: View {
    @EnvironmentObject private var session: AppSession

    private var data: PlatformDashboardData? { session.dashboardData }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("DeepSeek Monitor")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(DSTheme.ink)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(session.connectionState == .connected ? DSTheme.mint : DSTheme.coral)
                                .frame(width: 7, height: 7)
                            Text(session.connectionState.title + " · " + syncTime)
                                .font(.system(size: 11))
                                .foregroundStyle(DSTheme.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        Task { await session.refreshPlatformData() }
                    } label: {
                        Image(systemName: session.isSyncing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DSTheme.blue)
                            .frame(width: 42, height: 42)
                            .background(.white, in: Circle())
                    }
                    .disabled(session.isSyncing)
                }
                .padding(.top, 14)

                VStack(alignment: .leading, spacing: 11) {
                    HStack {
                        Text("账户余额")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DSTheme.secondary)
                        Spacer()
                        Text(data == nil ? "等待验证" : "控制台实时数据")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DSTheme.purple)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(DSTheme.purple.opacity(0.09), in: Capsule())
                    }
                    Text(formatMoney(data?.totalBalance, currency: data?.currency ?? "CNY"))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(DSTheme.ink)
                    HStack(spacing: 14) {
                        Text("充值余额  " + formatMoney(data?.normalBalance, currency: data?.currency ?? "CNY"))
                        Text("赠金余额  " + formatMoney(data?.bonusBalance, currency: data?.currency ?? "CNY"))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DSTheme.secondary)
                }
                .padding(17)
                .dsCard(20)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 11) {
                    MetricCard(title: "今日消费", value: formatMoney(data?.todaySpend, currency: data?.currency ?? "CNY"), icon: "calendar", tint: DSTheme.coral)
                    MetricCard(title: "累计消费", value: formatMoney(data?.totalSpend, currency: data?.currency ?? "CNY"), icon: "chart.line.uptrend.xyaxis", tint: DSTheme.purple)
                    MetricCard(title: "今日调用", value: formatInteger(data?.todayRequests), icon: "arrow.left.arrow.right", tint: DSTheme.mint)
                    MetricCard(title: "今日 Token", value: formatInteger(data?.todayTokens), icon: "number", tint: DSTheme.blue)
                }

                StatusBanner(
                    title: session.connectionState.title,
                    message: session.connectionMessage ?? "尚未从 DeepSeek 控制台完成数据验证。"
                )

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("近 7 天消费趋势")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(DSTheme.ink)
                        Spacer()
                        Text(data?.currency == "USD" ? "$" : "¥")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DSTheme.secondary)
                    }

                    let recent = Array((data?.dailyUsage ?? []).suffix(7))
                    if recent.isEmpty {
                        EmptyDataPanel(
                            title: "暂无趋势数据",
                            message: "控制台用量接口尚未返回可绘制的日统计数据。"
                        )
                    } else {
                        Chart(recent) { point in
                            AreaMark(
                                x: .value("日期", point.date),
                                y: .value("费用", NSDecimalNumber(decimal: point.cost).doubleValue)
                            )
                            .foregroundStyle(DSTheme.purple.opacity(0.12))
                            LineMark(
                                x: .value("日期", point.date),
                                y: .value("费用", NSDecimalNumber(decimal: point.cost).doubleValue)
                            )
                            .foregroundStyle(DSTheme.purple)
                            .interpolationMethod(.catmullRom)
                            PointMark(
                                x: .value("日期", point.date),
                                y: .value("费用", NSDecimalNumber(decimal: point.cost).doubleValue)
                            )
                            .foregroundStyle(DSTheme.purple)
                        }
                        .frame(height: 175)
                    }
                }
                .padding(15)
                .dsCard()

                Text("最后同步：" + (data?.synchronizedAt.formatted(date: .abbreviated, time: .shortened) ?? "尚未同步"))
                    .font(.system(size: 10))
                    .foregroundStyle(DSTheme.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 15)
            }
            .padding(.horizontal, 16)
        }
        .background(DSTheme.canvas)
        .task {
            if session.dashboardData == nil {
                await session.refreshPlatformData()
            }
        }
    }

    private var syncTime: String {
        data?.synchronizedAt.formatted(date: .omitted, time: .shortened) ?? "尚未同步"
    }
}

private func formatMoney(_ value: Decimal?, currency: String) -> String {
    guard let value else { return "—" }
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    let number = formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
    let symbol = currency == "USD" ? "$" : (currency == "CNY" ? "¥" : currency + " ")
    return symbol + number
}

private func formatInteger(_ value: Int?) -> String {
    guard let value else { return "—" }
    return value.formatted()
}

// MARK: - Usage analytics

enum UsageRange: String, CaseIterable, Identifiable {
    case day = "24 小时"
    case week = "7 天"
    case month = "30 天"
    case custom = "自定义"
    var id: String { rawValue }
}

enum UsageMetric: String, CaseIterable, Identifiable {
    case spend = "消费"
    case inputTokens = "输入 Token"
    case outputTokens = "输出 Token"
    case requests = "请求次数"
    var id: String { rawValue }
}

struct UsagePoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Double
}

struct AnalyticsView: View {
    @State private var selectedRange: UsageRange = .week
    @State private var selectedMetric: UsageMetric = .spend
    private let points: [UsagePoint] = []

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "用量统计", subtitle: "按时间范围查看平台用量")
                HStack(spacing: 5) {
                    ForEach(UsageRange.allCases) { range in
                        Button {
                            selectedRange = range
                        } label: {
                            Text(range.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(selectedRange == range ? DSTheme.blue : DSTheme.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(selectedRange == range ? DSTheme.blue.opacity(0.08) : .clear,
                                            in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(5)
                .background(.white, in: Capsule())

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(UsageMetric.allCases) { metric in
                            Button {
                                selectedMetric = metric
                            } label: {
                                Text(metric.rawValue)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(selectedMetric == metric ? .white : DSTheme.secondary)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 9)
                                    .background {
                                        if selectedMetric == metric {
                                            Capsule().fill(DSTheme.brandGradient)
                                        } else {
                                            Capsule().fill(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(metricTitle)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(DSTheme.ink)
                        Spacer()
                        Text("暂无数据")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DSTheme.secondary)
                    }
                    Chart(points) { point in
                        LineMark(
                            x: .value("时间", point.timestamp),
                            y: .value("数值", point.value)
                        )
                        .foregroundStyle(DSTheme.purple)
                        .interpolationMethod(.catmullRom)
                    }
                    .chartYScale(domain: 0...1)
                    .frame(height: 205)
                    .overlay {
                        VStack(spacing: 7) {
                            Image(systemName: "chart.xyaxis.line")
                                .font(.system(size: 23, weight: .light))
                            Text("等待真实用量数据")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(DSTheme.secondary)
                    }
                    Text("接入数据源后，支持点击折线节点查看该时间点的准确数值。")
                        .font(.system(size: 11))
                        .foregroundStyle(DSTheme.secondary)
                }
                .padding(15)
                .dsCard()

                VStack(alignment: .leading, spacing: 13) {
                    Text("用量总览（\(selectedRange.rawValue)）")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(DSTheme.ink)
                    summaryRow("输入 Token", icon: "arrow.down.circle")
                    Divider().overlay(DSTheme.line)
                    summaryRow("输出 Token", icon: "arrow.up.circle")
                    Divider().overlay(DSTheme.line)
                    summaryRow("缓存 Token", icon: "tray")
                    Divider().overlay(DSTheme.line)
                    summaryRow("API 请求", icon: "arrow.left.arrow.right")
                }
                .padding(15)
                .dsCard()
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 16)
        }
        .background(DSTheme.canvas)
    }

    private var metricTitle: String {
        switch selectedMetric {
        case .spend: return "消费趋势"
        case .inputTokens: return "输入 Token 趋势"
        case .outputTokens: return "输出 Token 趋势"
        case .requests: return "API 请求趋势"
        }
    }

    private func summaryRow(_ title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(DSTheme.blue).frame(width: 20)
            Text(title).font(.system(size: 13)).foregroundStyle(DSTheme.ink)
            Spacer()
            Text("—")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(DSTheme.secondary)
        }
    }
}

// MARK: - Model analytics

struct ModelsView: View {
    @State private var selectedRange = "7 天"
    private let ranges = ["7 天", "30 天", "12 个月"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 15) {
                PageHeader(title: "模型统计", subtitle: "按模型查看消费与 Token 分布")
                HStack(spacing: 5) {
                    ForEach(ranges, id: \.self) { range in
                        Button {
                            selectedRange = range
                        } label: {
                            Text(range)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(selectedRange == range ? .white : DSTheme.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(selectedRange == range ? DSTheme.brandGradient :
                                                LinearGradient(colors: [.clear, .clear],
                                                               startPoint: .leading, endPoint: .trailing),
                                            in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(5)
                .background(.white, in: Capsule())

                EmptyDataPanel(
                    title: "暂无模型统计",
                    message: "成功读取平台用量记录后，会在这里展示各模型的消费占比与排行。",
                    icon: "chart.pie"
                )

                VStack(alignment: .leading, spacing: 13) {
                    Text("模型消耗排行")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(DSTheme.ink)
                    HStack {
                        Text("模型")
                        Spacer()
                        Text("消费 / Token")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DSTheme.secondary)
                    Divider().overlay(DSTheme.line)
                    Text("连接数据源后显示模型明细")
                        .font(.system(size: 12))
                        .foregroundStyle(DSTheme.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 19)
                }
                .padding(15)
                .dsCard()
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 16)
        }
        .background(DSTheme.canvas)
    }
}

// MARK: - Request records and details

struct RequestRecord: Identifiable, Hashable {
    let id: String
    let model: String
    let createdAt: Date
    let inputTokens: Int?
    let outputTokens: Int?
    let cost: Decimal?
    let succeeded: Bool
}

struct RequestRecordRow: View {
    let record: RequestRecord

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: record.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(record.succeeded ? DSTheme.mint : DSTheme.coral)
                .font(.system(size: 17))
            VStack(alignment: .leading, spacing: 5) {
                Text(record.model)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DSTheme.ink)
                Text(record.createdAt.formatted(date: .numeric, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundStyle(DSTheme.secondary)
                HStack(spacing: 12) {
                    Text("输入 \(record.inputTokens.map(String.init) ?? "—")")
                    Text("输出 \(record.outputTokens.map(String.init) ?? "—")")
                }
                .font(.system(size: 10))
                .foregroundStyle(DSTheme.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text(record.cost.map { "¥\($0)" } ?? "—")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(DSTheme.ink)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DSTheme.secondary)
            }
        }
        .padding(14)
        .dsCard(15)
    }
}

struct RecordsView: View {
    @State private var selectedPeriod = "过去 7 天"
    @State private var selectedModel = "全部模型"
    @State private var records: [RequestRecord] = []

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 15) {
                PageHeader(title: "调用记录", subtitle: "查看 API 请求与费用明细")
                HStack(spacing: 9) {
                    Menu {
                        ForEach(["过去 24 小时", "过去 7 天", "过去 30 天"], id: \.self) { value in
                            Button(value) { selectedPeriod = value }
                        }
                    } label: { filterLabel(selectedPeriod) }

                    Menu {
                        ForEach(["全部模型", "DeepSeek-V4", "DeepSeek-Flash"], id: \.self) { value in
                            Button(value) { selectedModel = value }
                        }
                    } label: { filterLabel(selectedModel) }
                }
                if records.isEmpty {
                    EmptyDataPanel(
                        title: "暂无调用记录",
                        message: "目前验证到的控制台接口只提供每日、按模型汇总的数据，没有确认可读取逐条请求 ID 与请求内容的接口。为避免伪造调用记录，这里暂不生成明细。",
                        icon: "doc.text.magnifyingglass"
                    )
                    .padding(.top, 3)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(records) { record in
                            NavigationLink {
                                RecordDetailView(record: record)
                            } label: {
                                RequestRecordRow(record: record)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .background(DSTheme.canvas)
    }

    private func filterLabel(_ title: String) -> some View {
        HStack(spacing: 7) {
            Text(title).lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(DSTheme.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct RecordDetailView: View {
    let record: RequestRecord?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let record {
                    HStack(spacing: 9) {
                        Image(systemName: record.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(record.succeeded ? DSTheme.mint : DSTheme.coral)
                        Text(record.succeeded ? "调用成功" : "调用失败")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DSTheme.ink)
                    }
                    .padding(15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .dsCard()
                    VStack(spacing: 0) {
                        detailRow("模型", record.model)
                        detailRow("请求 ID", record.id)
                        detailRow("调用时间", record.createdAt.formatted(date: .numeric, time: .standard))
                        detailRow("输入 Token", record.inputTokens.map(String.init) ?? "—")
                        detailRow("输出 Token", record.outputTokens.map(String.init) ?? "—")
                        detailRow("本次费用", record.cost.map { "¥\($0)" } ?? "—")
                    }
                    .padding(.horizontal, 15)
                    .dsCard()
                } else {
                    EmptyDataPanel(
                        title: "暂无调用详情",
                        message: "选择一条已读取的真实调用记录后，这里会显示对应的请求详情。",
                        icon: "doc.text"
                    )
                }
            }
            .padding(16)
        }
        .background(DSTheme.canvas.ignoresSafeArea())
        .navigationTitle("详细详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 13)).foregroundStyle(DSTheme.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DSTheme.ink)
                .lineLimit(1)
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DSTheme.line).frame(height: 0.6)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject private var session: AppSession
    let onSignOut: () -> Void
    @AppStorage("monitor.syncInterval") private var syncInterval = "每 5 分钟"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 15) {
                PageHeader(title: "设置", subtitle: "账户与应用偏好")

                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(DSTheme.brandGradient)
                            .frame(width: 44, height: 44)
                        Image(systemName: "water.waves")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DeepSeek 账户")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DSTheme.ink)
                        Text("登录状态：" + session.connectionState.title)
                            .font(.system(size: 11))
                            .foregroundStyle(DSTheme.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DSTheme.secondary)
                }
                .padding(15)
                .dsCard()

                VStack(spacing: 0) {
                    HStack {
                        Label("数据同步", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        Picker("同步频率", selection: $syncInterval) {
                            Text("每 1 分钟").tag("每 1 分钟")
                            Text("每 5 分钟").tag("每 5 分钟")
                            Text("每 15 分钟").tag("每 15 分钟")
                            Text("手动").tag("手动")
                        }
                        .labelsHidden()
                        .tint(DSTheme.blue)
                    }
                    .padding(15)
                    settingsDivider
                    settingsRow("通知提醒", detail: "数据服务接入后启用", icon: "bell")
                    settingsDivider
                    settingsRow("数据缓存", detail: "本地存储", icon: "externaldrive")
                    settingsDivider
                    settingsRow("清除缓存", detail: "暂不可用", icon: "trash", tint: DSTheme.coral)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DSTheme.ink)
                .dsCard()

                VStack(spacing: 0) {
                    settingsRow("版本", detail: "0.1.0 · 初始界面版本", icon: "info.circle")
                    settingsDivider
                    settingsRow("反馈与建议", detail: "即将开放", icon: "envelope")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DSTheme.ink)
                .dsCard()

                Button(role: .destructive, action: onSignOut) {
                    Text("返回欢迎页面")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DSTheme.coral)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.top, 2)
                .padding(.bottom, 18)
            }
            .padding(.horizontal, 16)
        }
        .background(DSTheme.canvas)
    }

    private var settingsDivider: some View {
        Rectangle().fill(DSTheme.line).frame(height: 0.7).padding(.leading, 48)
    }

    private func settingsRow(_ title: String, detail: String, icon: String,
                             tint: Color = DSTheme.blue) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 22)
            Text(title)
            Spacer()
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(DSTheme.secondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DSTheme.secondary.opacity(0.7))
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 15)
        .contentShape(Rectangle())
    }
}
