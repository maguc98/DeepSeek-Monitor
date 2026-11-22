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
    @Published var isDashboardDataStale = false

    let platformSession = DeepSeekPlatformSession()
    private let hasLinkedAccountKey = "monitor.hasLinkedAccount"
    private let dashboardSnapshotKey = "monitor.dashboardSnapshot"

    init() {
        if UserDefaults.standard.bool(forKey: hasLinkedAccountKey),
           let snapshot = UserDefaults.standard.data(forKey: dashboardSnapshotKey),
           let decoded = try? JSONDecoder().decode(PlatformDashboardData.self, from: snapshot) {
            dashboardData = decoded
            isDashboardDataStale = true
            connectionState = .awaitingVerification
            route = .dashboard
            connectionMessage = "正在验证登录状态，暂时显示上次同步的数据。"
        }
    }

    func beginLogin() {
        connectionMessage = nil
        route = .login
    }

    func restoreSessionIfPossible() async {
        guard UserDefaults.standard.bool(forKey: hasLinkedAccountKey), !isSyncing else { return }
        if dashboardData == nil { route = .login }
        connectionState = .awaitingVerification
        connectionMessage = dashboardData == nil
            ? "正在恢复上次的 DeepSeek 登录状态…"
            : "正在验证登录状态，当前展示的是本机缓存。"
        isSyncing = true
        defer { isSyncing = false }

        do {
            await platformSession.loadPlatformPageAndWait()
            dashboardData = try await platformSession.fetchDashboard()
            connectionState = .connected
            isDashboardDataStale = false
            saveDashboardSnapshot()
            connectionMessage = dashboardData?.usageAvailable == true
                ? "已恢复登录并同步账户数据。"
                : "登录已恢复，但本次未获得用量统计数据。"
            route = .dashboard
        } catch {
            connectionState = .awaitingVerification
            isDashboardDataStale = dashboardData != nil
            connectionMessage = dashboardData == nil
                ? error.localizedDescription
                : "\(error.localizedDescription) 当前继续显示上次同步的缓存数据。"
            route = dashboardData == nil ? .login : .dashboard
        }
    }

    func finishLoginFlow() async {
        guard !isSyncing else { return }
        isSyncing = true
        connectionMessage = nil
        defer { isSyncing = false }

        do {
            dashboardData = try await platformSession.fetchDashboard()
            connectionState = .connected
            isDashboardDataStale = false
            UserDefaults.standard.set(true, forKey: hasLinkedAccountKey)
            saveDashboardSnapshot()
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
            isDashboardDataStale = false
            saveDashboardSnapshot()
            connectionMessage = dashboardData?.usageAvailable == true
                ? "数据同步完成。"
                : "账户已验证，但本次未获得用量统计数据。"
        } catch {
            isDashboardDataStale = dashboardData != nil
            connectionMessage = error.localizedDescription
            if let consoleError = error as? PlatformConsoleError {
                switch consoleError {
                case .unauthorized, .tokenNotFound, .pageNotReady:
                    connectionState = .awaitingVerification
                    route = .login
                default:
                    break
                }
            } else if dashboardData == nil {
                connectionState = .awaitingVerification
            }
        }
    }

    func clearCachedDashboard() {
        dashboardData = nil
        isDashboardDataStale = false
        UserDefaults.standard.removeObject(forKey: dashboardSnapshotKey)
        connectionMessage = "本机统计缓存已清除。"
    }

    func signOut() {
        dashboardData = nil
        isDashboardDataStale = false
        connectionMessage = nil
        connectionState = .notConnected
        UserDefaults.standard.set(false, forKey: hasLinkedAccountKey)
        UserDefaults.standard.removeObject(forKey: dashboardSnapshotKey)
        route = .welcome
        Task { await platformSession.clearWebSession() }
    }

    private func saveDashboardSnapshot() {
        guard let dashboardData,
              let encoded = try? JSONEncoder().encode(dashboardData) else { return }
        UserDefaults.standard.set(encoded, forKey: dashboardSnapshotKey)
    }
}

struct RootView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .id(routeKey)
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
        .buttonStyle(DSGlobalButtonStyle())
        .animation(DSMotion.page, value: routeKey)
        .transaction { transaction in
            if reduceMotion {
                transaction.disablesAnimations = true
                transaction.animation = nil
            }
        }
        .task {
            await session.restoreSessionIfPossible()
        }
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
    static let canvas = Color(red: 0.957, green: 0.961, blue: 0.980)
    static let card = Color.white
    static let blue = Color(red: 0.27, green: 0.47, blue: 0.94)
    static let purple = Color(red: 0.49, green: 0.36, blue: 0.88)
    static let mint = Color(red: 0.18, green: 0.68, blue: 0.53)
    static let coral = Color(red: 0.91, green: 0.38, blue: 0.43)
    static let ink = Color(red: 0.105, green: 0.125, blue: 0.20)
    static let secondary = Color(red: 0.45, green: 0.48, blue: 0.56)
    static let line = Color(red: 0.89, green: 0.90, blue: 0.94)

    static let brandGradient = LinearGradient(
        colors: [blue, purple], startPoint: .leading, endPoint: .trailing
    )
}

extension View {
    func dsCard(_ radius: CGFloat = 19) -> some View {
        background(DSTheme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(DSTheme.line.opacity(0.72), lineWidth: 0.8)
            }
            .shadow(color: DSTheme.ink.opacity(0.035), radius: 16, x: 0, y: 7)
            .modifier(DSEntranceModifier(delay: 0.025))
    }
}

struct PageHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                 .font(.system(size: 24, weight: .bold, design: .rounded))
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
        .dsEntrance(delay: 0.02)
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
                .contentTransition(.numericText())
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundStyle(DSTheme.ink)
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
            .dsEntrance()
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
        .dsEntrance()
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
    @EnvironmentObject private var session: AppSession
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("monitor.syncInterval") private var syncInterval = "每 5 分钟"
    let onSignOut: () -> Void
    @State private var selectedTab: DashboardTab = .overview

    private var autoRefreshTaskID: String {
        "\(syncInterval)-\(scenePhase == .active ? "active" : "inactive")"
    }

    private var autoRefreshInterval: Int? {
        switch syncInterval {
        case "每 1 分钟": return 60
        case "每 5 分钟": return 300
        case "每 15 分钟": return 900
        default: return nil
        }
    }
    var body: some View {        NavigationStack {
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
                .id(selectedTab)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.18), value: selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(spacing: 0) {
                    ForEach(DashboardTab.allCases) { tab in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) { selectedTab = tab }
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
                .animation(.easeInOut(duration: 0.18), value: selectedTab)
                .padding(.top, 5)
                .background(.white)
                .overlay(alignment: .top) {
                    Rectangle().fill(DSTheme.line).frame(height: 0.7)
                }
            }
            .background(DSTheme.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sensoryFeedback(.selection, trigger: selectedTab)
        }
        .task(id: autoRefreshTaskID) {
            guard scenePhase == .active, let interval = autoRefreshInterval else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                } catch {
                    break
                }
                guard !Task.isCancelled, scenePhase == .active else { break }
                await session.refreshPlatformData()
            }
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
                            Text(session.connectionState.title + " · " + syncTime + (session.isDashboardDataStale ? " · 缓存" : ""))
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
                        .contentTransition(.numericText())
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(DSTheme.ink)
                    HStack(spacing: 14) {
                        Text("充值余额  " + formatMoney(data?.normalBalance, currency: data?.currency ?? "CNY"))
                        Text("赠金余额  " + formatMoney(data?.bonusBalance, currency: data?.currency ?? "CNY"))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DSTheme.secondary)

                    Link(destination: URL(string: "https://platform.deepseek.com/top_up")!) {
                        HStack(spacing: 7) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text("立即充值")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text("前往 DeepSeek 官方平台")
                                .font(.system(size: 10, weight: .medium))
                                .opacity(0.78)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .background(DSTheme.brandGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("前往 DeepSeek 官方充值页面")
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
                    title: session.isDashboardDataStale ? "正在使用缓存数据" : session.connectionState.title,
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
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [DSTheme.purple.opacity(0.22), DSTheme.purple.opacity(0.015)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            LineMark(
                                x: .value("日期", point.date),
                                y: .value("费用", NSDecimalNumber(decimal: point.cost).doubleValue)
                            )
                            .foregroundStyle(DSTheme.purple)
                            .lineStyle(StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.monotone)
                            PointMark(
                                x: .value("日期", point.date),
                                y: .value("费用", NSDecimalNumber(decimal: point.cost).doubleValue)
                            )
                            .foregroundStyle(.white)
                            .symbolSize(34)
                            .annotation(position: .overlay) {
                                Circle().fill(DSTheme.purple).frame(width: 5, height: 5)
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: true))
                        .chartYAxis {
                            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                                AxisGridLine().foregroundStyle(DSTheme.line.opacity(0.8))
                                AxisValueLabel().foregroundStyle(DSTheme.secondary)
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                                AxisGridLine().foregroundStyle(.clear)
                                AxisValueLabel().foregroundStyle(DSTheme.secondary)
                            }
                        }
                        .chartPlotStyle { plot in
                            plot.padding(.top, 8).padding(.trailing, 8)
                        }
                        .frame(height: 190)
                        .animation(DSMotion.data, value: recent.last?.date)
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
        .animation(DSMotion.data, value: data?.synchronizedAt)
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
    @EnvironmentObject private var session: AppSession
    @State private var selectedRange: UsageRange = .week
    @State private var selectedMetric: UsageMetric = .spend
    @State private var selectedDate: Date?

    private var data: PlatformDashboardData? { session.dashboardData }
    private var visibleDays: [PlatformDailyUsage] {
        guard let days = data?.dailyUsage else { return [] }
        switch selectedRange {
        case .day, .custom: return []
        case .week: return Array(days.suffix(7))
        case .month: return Array(days.suffix(30))
        }
    }
    private var visibleHours: [PlatformHourlyUsage] { data?.hourlyUsage ?? [] }
    private var selectedPoint: PlatformDailyUsage? {
        guard selectedRange != .day, let selectedDate else { return nil }
        return visibleDays.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }
    private var selectedHour: PlatformHourlyUsage? {
        guard selectedRange == .day, let selectedDate else { return nil }
        return visibleHours.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }
    private var metricAvailable: Bool {
        if selectedRange == .day {
            switch selectedMetric {
            case .spend: return data?.hourlyCostUsageAvailable == true
            case .inputTokens, .outputTokens, .requests:
                return data?.hourlyTokenUsageAvailable == true
            }
        }
        switch selectedMetric {
        case .spend: return data?.costUsageAvailable == true
        case .inputTokens, .outputTokens, .requests:
            return data?.tokenUsageAvailable == true
        }
    }
    private var selectedValue: String {
        if selectedRange == .day {
            if let selectedHour { return displayValue(for: selectedHour) }
            guard !visibleHours.isEmpty else { return "—" }
        } else {
            if let selectedPoint { return displayValue(for: selectedPoint) }
            guard !visibleDays.isEmpty else { return "—" }
        }

        switch selectedMetric {
        case .spend:
            return formatMoney(summarySpend, currency: data?.currency ?? "CNY")
        case .inputTokens:
            return formatInteger(summaryInput)
        case .outputTokens:
            return formatInteger(summaryOutput)
        case .requests:
            return formatInteger(summaryRequests)
        }
    }

    private var summaryInput: Int {
        if selectedRange == .day { return visibleHours.reduce(0) { $0 + $1.inputTokens } }
        return visibleDays.reduce(0) { $0 + $1.inputTokens }
    }
    private var summaryOutput: Int {
        if selectedRange == .day { return visibleHours.reduce(0) { $0 + $1.outputTokens } }
        return visibleDays.reduce(0) { $0 + $1.outputTokens }
    }
    private var summaryCache: Int {
        if selectedRange == .day { return visibleHours.reduce(0) { $0 + $1.cacheTokens } }
        return visibleDays.reduce(0) { $0 + $1.cacheTokens }
    }

    private var summaryCacheHit: Int {
        if selectedRange == .day { return visibleHours.reduce(0) { $0 + $1.cacheHitTokens } }
        return visibleDays.reduce(0) { $0 + $1.cacheHitTokens }
    }
    private var summaryCacheMiss: Int {
        if selectedRange == .day { return visibleHours.reduce(0) { $0 + $1.cacheMissTokens } }
        return visibleDays.reduce(0) { $0 + $1.cacheMissTokens }
    }
    private var summaryRequests: Int {
        if selectedRange == .day { return visibleHours.reduce(0) { $0 + $1.requests } }
        return visibleDays.reduce(0) { $0 + $1.requests }
    }
    private var summarySpend: Decimal {
        if selectedRange == .day { return visibleHours.reduce(Decimal.zero) { $0 + $1.cost } }
        return visibleDays.reduce(Decimal.zero) { $0 + $1.cost }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "用量统计", subtitle: "平台统计 · GMT+8")
                HStack(spacing: 5) {
                    ForEach(UsageRange.allCases) { range in
                        Button {
                            selectedRange = range
                            selectedDate = nil
                        } label: {
                            Text(range.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(selectedRange == range ? DSTheme.blue : DSTheme.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(selectedRange == range ? DSTheme.blue.opacity(0.08) : .clear,
                                            in: Capsule())
                        }
                        .buttonStyle(DSGlobalButtonStyle())
                    }
                }
                .padding(5)
                .background(.white, in: Capsule())

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(UsageMetric.allCases) { metric in
                            Button {
                                selectedMetric = metric
                                selectedDate = nil
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
                            .buttonStyle(DSGlobalButtonStyle())
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 11) {
                    HStack {
                        Text(metricTitle)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(DSTheme.ink)
                        Spacer()
                        Text(metricAvailable ? selectedValue : "暂无数据")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DSTheme.purple)
                    }

                    if selectedRange == .custom {
                        EmptyDataPanel(
                            title: "自定义范围尚未开放",
                            message: "目前支持 24 小时、最近 7 天和最近 30 天。"
                        )
                    } else if !metricAvailable {
                        EmptyDataPanel(
                            title: "该指标暂不可用",
                            message: "本次同步没有成功取得这一类统计数据，请稍后刷新。",
                            icon: "chart.xyaxis.line"
                        )
                    } else if selectedRange == .day && visibleHours.isEmpty {
                        EmptyDataPanel(
                            title: "暂无小时级数据",
                            message: "今天的单日统计接口尚未返回小时桶。可以刷新后重试。",
                            icon: "clock"
                        )
                    } else if selectedRange != .day && visibleDays.isEmpty {
                        EmptyDataPanel(
                            title: "暂无趋势数据",
                            message: "平台目前没有返回所选时间范围内的日统计记录。"
                        )
                    } else if selectedRange == .day {
                        Chart(visibleHours) { point in
                            AreaMark(
                                x: .value("小时", point.date),
                                y: .value("数值", chartValue(point))
                            )
                            .foregroundStyle(LinearGradient(
                                colors: [DSTheme.purple.opacity(0.20), DSTheme.purple.opacity(0.015)],
                                startPoint: .top, endPoint: .bottom
                            ))
                            LineMark(
                                x: .value("小时", point.date),
                                y: .value("数值", chartValue(point))
                            )
                            .foregroundStyle(DSTheme.purple)
                            .lineStyle(StrokeStyle(lineWidth: 2.7, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.monotone)
                            if let selectedHour {
                                RuleMark(x: .value("选中时间", selectedHour.date))
                                    .foregroundStyle(DSTheme.blue.opacity(0.78))
                                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                                    .annotation(position: .top, spacing: 7) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(selectedHour.date.formatted(date: .omitted, time: .shortened))
                                                .font(.system(size: 10, weight: .semibold))
                                            Text(displayValue(for: selectedHour))
                                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                        }
                                        .foregroundStyle(DSTheme.ink)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 7)
                                        .background(.white, in: RoundedRectangle(cornerRadius: 9))
                                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(DSTheme.line, lineWidth: 0.8))
                                        .shadow(color: DSTheme.ink.opacity(0.08), radius: 8, y: 3)
                                    }
                            }
                        }
                        .chartXSelection(value: $selectedDate)
                        .chartYAxis {
                            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                                AxisGridLine().foregroundStyle(DSTheme.line.opacity(0.8))
                                AxisValueLabel().foregroundStyle(DSTheme.secondary)
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                                AxisGridLine().foregroundStyle(.clear)
                                AxisValueLabel().foregroundStyle(DSTheme.secondary)
                            }
                        }
                        .chartPlotStyle { plot in plot.padding(.top, 8).padding(.trailing, 8) }
                        .frame(height: 220)
                        .animation(DSMotion.data, value: visibleHours.last?.date)
                        HStack {
                            Text(selectedHour.map { $0.date.formatted(date: .omitted, time: .shortened) } ?? "今天")
                            Spacer()
                            Text("单日接口 · 小时桶")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(DSTheme.secondary)
                    } else {
                        Chart(visibleDays) { point in
                            AreaMark(
                                x: .value("日期", point.date),
                                y: .value("数值", chartValue(point))
                            )
                            .foregroundStyle(LinearGradient(
                                colors: [DSTheme.purple.opacity(0.20), DSTheme.purple.opacity(0.015)],
                                startPoint: .top, endPoint: .bottom
                            ))
                            LineMark(
                                x: .value("日期", point.date),
                                y: .value("数值", chartValue(point))
                            )
                            .foregroundStyle(DSTheme.purple)
                            .lineStyle(StrokeStyle(lineWidth: 2.7, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.monotone)
                            if let selectedPoint {
                                RuleMark(x: .value("选中日期", selectedPoint.date))
                                    .foregroundStyle(DSTheme.blue.opacity(0.78))
                                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                                    .annotation(position: .top, spacing: 7) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(selectedPoint.date.formatted(date: .abbreviated, time: .omitted))
                                                .font(.system(size: 10, weight: .semibold))
                                            Text(displayValue(for: selectedPoint))
                                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                        }
                                        .foregroundStyle(DSTheme.ink)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 7)
                                        .background(.white, in: RoundedRectangle(cornerRadius: 9))
                                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(DSTheme.line, lineWidth: 0.8))
                                        .shadow(color: DSTheme.ink.opacity(0.08), radius: 8, y: 3)
                                    }
                            }
                        }
                        .chartXSelection(value: $selectedDate)
                        .chartYAxis {
                            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                                AxisGridLine().foregroundStyle(DSTheme.line.opacity(0.8))
                                AxisValueLabel().foregroundStyle(DSTheme.secondary)
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                                AxisGridLine().foregroundStyle(.clear)
                                AxisValueLabel().foregroundStyle(DSTheme.secondary)
                            }
                        }
                        .chartPlotStyle { plot in plot.padding(.top, 8).padding(.trailing, 8) }
                        .frame(height: 220)
                        .animation(DSMotion.data, value: visibleDays.last?.date)
                        HStack {
                            Text(selectedPoint?.date.formatted(date: .abbreviated, time: .omitted) ?? "最近 \(selectedRange.rawValue)")
                            Spacer()
                            Text("拖动图表查看数据")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(DSTheme.secondary)
                    }
                }
                .padding(15)
                .dsCard()

                VStack(alignment: .leading, spacing: 13) {
                    Text("用量总览（\(selectedRange.rawValue)）")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(DSTheme.ink)
                    summaryRow("消费", value: ((selectedRange == .day
                               ? data?.hourlyCostUsageAvailable
                               : data?.costUsageAvailable) == true)
                               ? formatMoney(summarySpend, currency: data?.currency ?? "CNY") : "—",
                               icon: "yensign.circle")
                    Divider().overlay(DSTheme.line)
                    summaryRow("输入 Token", value: ((selectedRange == .day
                               ? data?.hourlyTokenUsageAvailable
                               : data?.tokenUsageAvailable) == true)
                               ? formatInteger(summaryInput) : "—", icon: "arrow.down.circle")
                    Divider().overlay(DSTheme.line)
                    summaryRow("输出 Token", value: ((selectedRange == .day
                               ? data?.hourlyTokenUsageAvailable
                               : data?.tokenUsageAvailable) == true)
                               ? formatInteger(summaryOutput) : "—", icon: "arrow.up.circle")
                    Divider().overlay(DSTheme.line)
                    summaryRow("缓存 Token", value: ((selectedRange == .day
                               ? data?.hourlyTokenUsageAvailable
                               : data?.tokenUsageAvailable) == true)
                               ? formatInteger(summaryCache) : "—", icon: "tray")
                    Divider().overlay(DSTheme.line)
                    summaryRow("API 请求", value: ((selectedRange == .day
                               ? data?.hourlyTokenUsageAvailable
                               : data?.tokenUsageAvailable) == true)
                               ? formatInteger(summaryRequests) : "—", icon: "arrow.left.arrow.right")
                }
                .padding(15)
                .dsCard()

                TokenCompositionPanel(
                    inputTokens: summaryInput,
                    cacheHitTokens: summaryCacheHit,
                    cacheMissTokens: summaryCacheMiss,
                    outputTokens: summaryOutput
                )

                TokenTrendComparisonPanel(days: visibleDays)

                UsageHeatmapPanel(days: Array((data?.dailyUsage ?? []).suffix(30)))
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 16)
        }
        .background(DSTheme.canvas)
        .animation(DSMotion.selection, value: selectedRange)
        .animation(DSMotion.selection, value: selectedMetric)
        .animation(DSMotion.data, value: data?.synchronizedAt)
    }
    private var metricTitle: String {
        switch selectedMetric {
        case .spend: return "消费趋势"
        case .inputTokens: return "输入 Token 趋势"
        case .outputTokens: return "输出 Token 趋势"
        case .requests: return "API 请求趋势"
        }
    }

    private func displayValue(for point: PlatformDailyUsage) -> String {
        switch selectedMetric {
        case .spend: return formatMoney(point.cost, currency: data?.currency ?? "CNY")
        case .inputTokens: return formatInteger(point.inputTokens)
        case .outputTokens: return formatInteger(point.outputTokens)
        case .requests: return formatInteger(point.requests)
        }    }

    private func displayValue(for point: PlatformHourlyUsage) -> String {
        switch selectedMetric {
        case .spend: return formatMoney(point.cost, currency: data?.currency ?? "CNY")
        case .inputTokens: return formatInteger(point.inputTokens)
        case .outputTokens: return formatInteger(point.outputTokens)
        case .requests: return formatInteger(point.requests)
        }
    }

    private func chartValue(_ point: PlatformDailyUsage) -> Double {
        switch selectedMetric {
        case .spend: return NSDecimalNumber(decimal: point.cost).doubleValue
        case .inputTokens: return Double(point.inputTokens)
        case .outputTokens: return Double(point.outputTokens)
        case .requests: return Double(point.requests)
        }
    }

    private func chartValue(_ point: PlatformHourlyUsage) -> Double {
        switch selectedMetric {
        case .spend: return NSDecimalNumber(decimal: point.cost).doubleValue
        case .inputTokens: return Double(point.inputTokens)
        case .outputTokens: return Double(point.outputTokens)
        case .requests: return Double(point.requests)
        }
    }

    private func summaryRow(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(DSTheme.blue).frame(width: 20)
            Text(title).font(.system(size: 13)).foregroundStyle(DSTheme.ink)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
                .foregroundStyle(DSTheme.secondary)
        }
    }
}

// MARK: - Model analytics

struct ModelsView: View {
    @EnvironmentObject private var session: AppSession
    @State private var selectedRange = "7 天"

    private var data: PlatformDashboardData? { session.dashboardData }

    private var selectedDays: [PlatformDailyUsage] {
        guard let days = data?.dailyUsage, selectedRange != "12 个月" else { return [] }
        return Array(days.suffix(selectedRange == "7 天" ? 7 : 30))
    }

    private var modelRows: [PlatformDailyModelUsage] {
        var result: [String: PlatformDailyModelUsage] = [:]
        for day in selectedDays {
            for item in day.models {
                let previous = result[item.model]
                result[item.model] = PlatformDailyModelUsage(
                    id: item.model,
                    model: item.model,
                    cost: (previous?.cost ?? 0) + item.cost,
                    inputTokens: (previous?.inputTokens ?? 0) + item.inputTokens,
                    cacheTokens: (previous?.cacheTokens ?? 0) + item.cacheTokens,
                    outputTokens: (previous?.outputTokens ?? 0) + item.outputTokens,
                    requests: (previous?.requests ?? 0) + item.requests
                )
            }
        }
        return result.values.sorted { $0.cost > $1.cost }
    }

    private var totalModelCost: Decimal {
        modelRows.reduce(Decimal.zero) { $0 + $1.cost }
    }

    private var hasCostBreakdown: Bool {
        data?.costUsageAvailable == true && modelRows.contains { $0.cost > 0 }
    }

    private var hasTokenBreakdown: Bool {
        data?.tokenUsageAvailable == true && !modelRows.isEmpty
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 15) {
                PageHeader(title: "模型统计", subtitle: "按模型查看消费与 Token 分布")

                HStack(spacing: 5) {
                    ForEach(["7 天", "30 天", "12 个月"], id: \.self) { range in
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
                        .buttonStyle(DSGlobalButtonStyle())
                    }
                }
                .padding(5)
                .background(.white, in: Capsule())

                if selectedRange == "12 个月" {
                    EmptyDataPanel(
                        title: "暂无 12 个月历史",
                        message: "当前适配器只请求最近 30 天的控制台日级数据。不会用 30 天数据填充全年图表。",
                        icon: "calendar"
                    )
                } else if !hasCostBreakdown && !hasTokenBreakdown {
                    EmptyDataPanel(
                        title: "暂无模型统计",
                        message: "成功读取平台按模型统计的用量后，这里会显示模型消费占比与 Token 排行。",
                        icon: "chart.pie"
                    )
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("模型消费占比")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(DSTheme.ink)
                        if hasCostBreakdown {
                            Chart(modelRows.filter { $0.cost > 0 }) { model in
                                SectorMark(
                                    angle: .value("消费", NSDecimalNumber(decimal: model.cost).doubleValue),
                                    innerRadius: .ratio(0.58),
                                    angularInset: 2
                                )
                                .foregroundStyle(by: .value("模型", model.model))
                            }
                            .frame(height: 205)
                            .chartLegend(position: .bottom, alignment: .leading)
                            HStack {
                                Text("合计")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(DSTheme.secondary)
                                Spacer()
                                Text(formatMoney(totalModelCost, currency: data?.currency ?? "CNY"))
                                    .font(.system(size: 21, weight: .bold, design: .rounded))
                                    .foregroundStyle(DSTheme.ink)
                            }
                        } else {
                            EmptyDataPanel(
                                title: "费用数据暂不可用",
                                message: "当前可以展示 Token 与请求量，但没有取得模型费用桶。",
                                icon: "yensign.circle"
                            )
                        }
                    }
                    .padding(15)
                    .dsCard()

                    ModelRequestDistributionPanel(models: modelRows)
                    ModelTokenComparisonPanel(models: modelRows)

                    VStack(alignment: .leading, spacing: 13) {
                        Text("模型消耗排行")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(DSTheme.ink)
                        ForEach(modelRows) { model in
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(DSTheme.blue.opacity(0.10))
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        Image(systemName: "cpu")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(DSTheme.blue)
                                    }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.model)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(DSTheme.ink)
                                    Text(data?.tokenUsageAvailable == true
                                         ? "输入 \(formatInteger(model.inputTokens)) · 缓存 \(formatInteger(model.cacheTokens)) · 输出 \(formatInteger(model.outputTokens))"
                                         : "Token 数据暂不可用")
                                        .font(.system(size: 10))
                                        .foregroundStyle(DSTheme.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(data?.costUsageAvailable == true
                                         ? formatMoney(model.cost, currency: data?.currency ?? "CNY") : "—")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundStyle(DSTheme.ink)
                                    Text("请求 \(formatInteger(model.requests))")
                                        .font(.system(size: 10))
                                        .foregroundStyle(DSTheme.secondary)
                                }
                            }
                            .padding(.vertical, 5)
                            if model.id != modelRows.last?.id {
                                Divider().overlay(DSTheme.line)
                            }
                        }
                    }
                    .padding(15)
                    .dsCard()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(DSTheme.canvas)
        .animation(DSMotion.selection, value: selectedRange)
        .animation(DSMotion.data, value: data?.synchronizedAt)
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
                .foregroundStyle(DSTheme.secondary)            }
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
                            .buttonStyle(DSGlobalButtonStyle())
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

                Link(destination: URL(string: "https://platform.deepseek.com/top_up")!) {
                    settingsRow("账户充值", detail: "打开 DeepSeek 官方充值页面", icon: "creditcard")
                }
                .buttonStyle(.plain)
                .background(.white, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .dsCard()
                .accessibilityLabel("前往 DeepSeek 官方充值页面")

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
                    settingsRow("数据缓存", detail: "最近一次统计快照保存在本机", icon: "externaldrive")
                    settingsDivider
                    Button(role: .destructive) {
                        session.clearCachedDashboard()
                    } label: {
                        settingsRow(
                            "清除缓存",
                            detail: session.dashboardData == nil ? "暂无缓存" : "清除统计快照",
                            icon: "trash",
                            tint: DSTheme.coral
                        )
                    }
                    .buttonStyle(DSGlobalButtonStyle())
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
                    Text("退出 DeepSeek 账户")
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