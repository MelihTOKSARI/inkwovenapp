import Foundation
import InkCore
import InkNet
import InkMoney
import InkAnalytics

/// Composition root. All cross-package boundaries are protocols; the live
/// implementations are bound here and nowhere else.
@Observable
final class AppDI {
    let proxy: ProxyClient
    let analytics: Analytics

    init(proxy: ProxyClient, analytics: Analytics) {
        self.proxy = proxy
        self.analytics = analytics
    }

    static func live() -> AppDI {
        // Local proxy in echo mode during core development; the deployed URL
        // lands here via build configuration before TestFlight.
        let endpoints = ProxyEndpoints(baseURL: URL(string: "http://localhost:8787")!)
        let proxy = ProxyClient(endpoints: endpoints, auth: AnonymousTokenProvider())
        // TODO(A3): swap ConsoleAnalyticsSink for the real SDK adapter.
        let analytics = Analytics(sink: ConsoleAnalyticsSink())
        return AppDI(proxy: proxy, analytics: analytics)
    }
}

/// Anonymous install token; App Attest assertion + Sign in with Apple upgrade
/// happen behind this same protocol (task F4).
struct AnonymousTokenProvider: AuthTokenProviding {
    func token() async throws -> String {
        let key = "ink.anonymous.user"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }
}

struct ConsoleAnalyticsSink: AnalyticsSink {
    func track(name: String, parameters: [String: AnalyticsValue]) {
        print("[analytics] \(name) \(parameters)")
    }
}
