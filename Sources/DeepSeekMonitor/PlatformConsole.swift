import Foundation
import WebKit

struct PlatformDailyUsage: Identifiable {
    let id: String
    let date: Date
    let cost: Decimal
    let inputTokens: Int
    let cacheHitTokens: Int
    let cacheMissTokens: Int
    let outputTokens: Int
    let requests: Int

    var totalTokens: Int {
        inputTokens + cacheHitTokens + cacheMissTokens + outputTokens
    }
}

struct PlatformModelUsage: Identifiable {
    let id: String
    let model: String
    let cost: Decimal
    let inputTokens: Int
    let outputTokens: Int
    let requests: Int
}

struct PlatformDashboardData {
    let currency: String
    let totalBalance: Decimal?
    let normalBalance: Decimal?
    let bonusBalance: Decimal?
    let totalSpend: Decimal?
    let monthSpend: Decimal?
    let todaySpend: Decimal?
    let todayRequests: Int?
    let todayTokens: Int?
    let dailyUsage: [PlatformDailyUsage]
    let modelUsage: [PlatformModelUsage]
    let synchronizedAt: Date
    let usageAvailable: Bool
}

enum PlatformConsoleError: LocalizedError {
    case pageNotReady
    case tokenNotFound
    case unauthorized
    case httpStatus(Int)
    case invalidResponse
    case businessError(String)

    var errorDescription: String? {
        switch self {
        case .pageNotReady:
            return "请先在内置网页中打开并登录 platform.deepseek.com。"
        case .tokenNotFound:
            return "网页登录状态尚未就绪。请重新打开 DeepSeek 平台并完成登录。"
        case .unauthorized:
            return "DeepSeek 登录状态已失效，请重新登录。"
        case .httpStatus(let status):
            return "DeepSeek 控制台暂时无法读取数据（HTTP \(status)）。"
        case .invalidResponse:
            return "DeepSeek 返回的数据格式暂时无法识别。"
        case .businessError(let code):
            return "DeepSeek 控制台返回业务错误：\(code)。"
        }
    }
}

/// Uses the user's existing WKWebView session to call same-origin console routes.
/// The session token is read inside page JavaScript and is never returned to native
/// code, logged, persisted separately, or sent to a third-party server. Console
/// routes are undocumented implementation details and may change.
@MainActor
final class DeepSeekPlatformSession: ObservableObject {
    let webView: WKWebView
    @Published private(set) var isAuthenticated = false
    @Published private(set) var lastError: String?

    private let platformHost = "platform.deepseek.com"
    private let platformTimeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView.allowsBackForwardNavigationGestures = true
    }

    func loadLoginPage() {
        if webView.url?.host == platformHost { return }
        guard let url = URL(string: "https://platform.deepseek.com/") else { return }
        webView.load(URLRequest(url: url))
    }

    func fetchDashboard() async throws -> PlatformDashboardData {
        guard webView.url?.host == platformHost else {
            throw PlatformConsoleError.pageNotReady
        }

        let summary = try await requestJSON(path: "/api/v0/users/get_user_summary")
        try validateBusinessEnvelope(summary)

        let range = currentMonthRange()
        let query = "start=\(range.start)&end=\(range.end)&tz=28800"
        async let amountTask = try? requestJSON(path: "/api/v0/usage/by_api_key/amount?\(query)")
        async let costTask = try? requestJSON(path: "/api/v0/usage/by_api_key/cost?\(query)")
        let (amount, cost) = await (amountTask, costTask)

        let data = PlatformDashboardParser.parse(
            summary: summary,
            amount: amount,
            cost: cost,
            now: Date(),
            timeZone: platformTimeZone
        )
        isAuthenticated = true
        lastError = nil
        return data
    }

    func clearWebSession() async {
        let store = webView.configuration.websiteDataStore
        let records: [WKWebsiteDataRecord] = await withCheckedContinuation { continuation in
            store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) {
                continuation.resume(returning: $0)
            }
        }
        let platformRecords = records.filter { $0.displayName.contains("deepseek.com") }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                for: platformRecords
            ) {
                continuation.resume()
            }
        }
        webView.loadHTMLString("", baseURL: nil)
        isAuthenticated = false
        lastError = nil
    }

    private func currentMonthRange() -> (start: Int, end: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = platformTimeZone
        let components = calendar.dateComponents([.year, .month], from: Date())
        let startDate = calendar.date(from: components) ?? Date()
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: startDate) ?? Date()
        return (Int(startDate.timeIntervalSince1970), Int(nextMonth.timeIntervalSince1970))
    }

    private func requestJSON(path: String) async throws -> [String: Any] {
        guard path.hasPrefix("/api/v0/") else {
            throw PlatformConsoleError.invalidResponse
        }

        let script = """
        const candidateKeys = ["userToken", "token", "authToken", "accessToken"];
        let pageToken = null;
        for (const key of candidateKeys) {
          const value = localStorage.getItem(key);
          if (typeof value === "string" && value.trim().length > 0) {
            pageToken = value.trim();
            break;
          }
        }
        if (!pageToken) {
          return { status: 470, body: "" };
        }
        const authorization = pageToken.startsWith("Bearer ")
          ? pageToken
          : "Bearer " + pageToken;
        const response = await fetch(path, {
          method: "GET",
          credentials: "include",
          headers: {
            "Accept": "application/json",
            "Authorization": authorization
          }
        });
        return { status: response.status, body: await response.text() };
        """

        let result = try await evaluateJavaScript(script, arguments: ["path": path])
        guard let response = result as? [String: Any],
              let status = response["status"] as? Int,
              let body = response["body"] as? String else {
            throw PlatformConsoleError.invalidResponse
        }

        if status == 470 { throw PlatformConsoleError.tokenNotFound }
        if status == 401 || status == 403 { throw PlatformConsoleError.unauthorized }
        guard (200..<300).contains(status) else {
            throw PlatformConsoleError.httpStatus(status)
        }
        guard let bodyData = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bodyData),
              let dictionary = json as? [String: Any] else {
            throw PlatformConsoleError.invalidResponse
        }
        return dictionary
    }

    private func evaluateJavaScript(_ body: String, arguments: [String: Any]) async throws -> Any {
        try await webView.callAsyncJavaScript(
            body,
            arguments: arguments,
            in: nil,
            contentWorld: .page
        )
    }

    private func validateBusinessEnvelope(_ response: [String: Any]) throws {
        if let code = response["code"], !isSuccessCode(code) {
            throw PlatformConsoleError.businessError(String(describing: code))
        }
        if let data = response["data"] as? [String: Any],
           let code = data["biz_code"], !isSuccessCode(code) {
            throw PlatformConsoleError.businessError(String(describing: code))
        }
    }

    private func isSuccessCode(_ value: Any) -> Bool {
        if let number = value as? NSNumber { return number.intValue == 0 }
        if let string = value as? String { return string == "0" }
        return false
    }
}

private enum PlatformDashboardParser {
    private struct DayAccumulator {
        var date: Date
        var cost: Decimal = 0
        var inputTokens = 0
        var cacheHitTokens = 0
        var cacheMissTokens = 0
        var outputTokens = 0
        var requests = 0
    }

    private struct ModelAccumulator {
        var cost: Decimal = 0
        var inputTokens = 0
        var outputTokens = 0
        var requests = 0
    }

    static func parse(
        summary: [String: Any],
        amount: [String: Any]?,
        cost: [String: Any]?,
        now: Date,
        timeZone: TimeZone
    ) -> PlatformDashboardData {
        let biz = businessData(summary)
        let normalWallets = wallets(biz["normal_wallets"])
        let bonusWallets = wallets(biz["bonus_wallets"])
        let currency = normalWallets.first?.currency ?? bonusWallets.first?.currency ?? "CNY"
        let normalBalance = sumWallets(normalWallets, currency: currency)
        let bonusBalance = sumWallets(bonusWallets, currency: currency)
        let totalBalance: Decimal? = {
            guard normalBalance != nil || bonusBalance != nil else { return nil }
            return (normalBalance ?? 0) + (bonusBalance ?? 0)
        }()
        let totalSpend = totalCosts(biz["total_costs"], currency: currency)

        var days: [String: DayAccumulator] = [:]
        var models: [String: ModelAccumulator] = [:]
        if let amount {
            parseAmount(amount, timeZone: timeZone, days: &days, models: &models)
        }
        if let cost {
            parseCost(cost, preferredCurrency: currency, timeZone: timeZone, days: &days, models: &models)
        }

        let calendar = calendarFor(timeZone)
        let todayKey = dateKey(now, calendar: calendar)
        let monthSpend = days.values.reduce(Decimal.zero) { $0 + $1.cost }
        let today = days[todayKey]
        let dailyUsage = days.keys.sorted().compactMap { key -> PlatformDailyUsage? in
            guard let value = days[key] else { return nil }
            return PlatformDailyUsage(
                id: key, date: value.date, cost: value.cost,
                inputTokens: value.inputTokens, cacheHitTokens: value.cacheHitTokens,
                cacheMissTokens: value.cacheMissTokens, outputTokens: value.outputTokens,
                requests: value.requests
            )
        }
        let modelUsage = models.keys.compactMap { model -> PlatformModelUsage? in
            guard let value = models[model] else { return nil }
            return PlatformModelUsage(
                id: model, model: model, cost: value.cost,
                inputTokens: value.inputTokens, outputTokens: value.outputTokens,
                requests: value.requests
            )
        }.sorted { $0.cost > $1.cost }

        return PlatformDashboardData(
            currency: currency,
            totalBalance: totalBalance,
            normalBalance: normalBalance,
            bonusBalance: bonusBalance,
            totalSpend: totalSpend,
            monthSpend: cost == nil ? nil : monthSpend,
            todaySpend: cost == nil ? nil : today?.cost,
            todayRequests: amount == nil ? nil : today?.requests,
            todayTokens: amount == nil ? nil : today.map {
                $0.inputTokens + $0.cacheHitTokens + $0.cacheMissTokens + $0.outputTokens
            },
            dailyUsage: dailyUsage,
            modelUsage: modelUsage,
            synchronizedAt: now,
            usageAvailable: amount != nil || cost != nil
        )
    }

    private static func businessData(_ json: [String: Any]) -> [String: Any] {
        let data = json["data"] as? [String: Any] ?? [:]
        return data["biz_data"] as? [String: Any] ?? data
    }

    private static func wallets(_ value: Any?) -> [(currency: String, balance: Decimal)] {
        guard let rows = value as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let balance = decimal(row["balance"]) else { return nil }
            return (row["currency"] as? String ?? "CNY", balance)
        }
    }

    private static func sumWallets(
        _ values: [(currency: String, balance: Decimal)],
        currency: String
    ) -> Decimal? {
        let selected = values.filter { $0.currency == currency }
        guard !selected.isEmpty else { return nil }
        return selected.reduce(Decimal.zero) { $0 + $1.balance }
    }

    private static func totalCosts(_ value: Any?, currency: String) -> Decimal? {
        guard let rows = value as? [[String: Any]] else { return nil }
        let selected = rows.filter { ($0["currency"] as? String ?? currency) == currency }
        guard !selected.isEmpty else { return nil }
        return selected.reduce(Decimal.zero) { $0 + (decimal($1["amount"]) ?? 0) }
    }

    private static func parseAmount(
        _ response: [String: Any],
        timeZone: TimeZone,
        days: inout [String: DayAccumulator],
        models: inout [String: ModelAccumulator]
    ) {
        let biz = businessData(response)
        guard let series = biz["series"] as? [[String: Any]] else { return }
        for entry in series {
            let model = entry["model"] as? String ?? "unknown"
            guard let buckets = entry["buckets"] as? [[String: Any]] else { continue }
            for bucket in buckets {
                guard let timestamp = double(bucket["time"]),
                      let usage = bucket["usage"] as? [String: Any] else { continue }
                let date = dayDate(timestamp: timestamp, timeZone: timeZone)
                let key = dateKey(date, calendar: calendarFor(timeZone))
                var day = days[key] ?? DayAccumulator(date: date)
                var modelValue = models[model] ?? ModelAccumulator()

                let prompt = integer(usage["PROMPT_TOKEN"])
                let cacheHit = integer(usage["PROMPT_CACHE_HIT_TOKEN"])
                let cacheMiss = integer(usage["PROMPT_CACHE_MISS_TOKEN"])
                let output = integer(usage["RESPONSE_TOKEN"])
                let requests = integer(usage["REQUEST"])

                day.inputTokens += prompt
                day.cacheHitTokens += cacheHit
                day.cacheMissTokens += cacheMiss
                day.outputTokens += output
                day.requests += requests
                modelValue.inputTokens += prompt + cacheHit + cacheMiss
                modelValue.outputTokens += output
                modelValue.requests += requests

                days[key] = day
                models[model] = modelValue
            }
        }
    }

    private static func parseCost(
        _ response: [String: Any],
        preferredCurrency: String,
        timeZone: TimeZone,
        days: inout [String: DayAccumulator],
        models: inout [String: ModelAccumulator]
    ) {
        let biz = businessData(response)
        let groups = biz["data"] as? [[String: Any]] ?? []
        let group = groups.first { ($0["currency"] as? String) == preferredCurrency } ?? groups.first
        guard let series = group?["series"] as? [[String: Any]] else { return }
        for entry in series {
            let model = entry["model"] as? String ?? "unknown"
            guard let buckets = entry["buckets"] as? [[String: Any]] else { continue }
            for bucket in buckets {
                guard let timestamp = double(bucket["time"]),
                      let cost = decimal(bucket["cost"]) else { continue }
                let date = dayDate(timestamp: timestamp, timeZone: timeZone)
                let key = dateKey(date, calendar: calendarFor(timeZone))
                var day = days[key] ?? DayAccumulator(date: date)
                var modelValue = models[model] ?? ModelAccumulator()
                day.cost += cost
                modelValue.cost += cost
                days[key] = day
                models[model] = modelValue
            }
        }
    }

    private static func calendarFor(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private static func dayDate(timestamp: Double, timeZone: TimeZone) -> Date {
        calendarFor(timeZone).startOfDay(for: Date(timeIntervalSince1970: timestamp))
    }

    private static func dateKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d",
                      parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func decimal(_ value: Any?) -> Decimal? {
        if let string = value as? String { return Decimal(string: string) }
        if let number = value as? NSNumber { return Decimal(string: number.stringValue) }
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func integer(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }
}
