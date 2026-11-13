import Foundation
import Combine

@MainActor final class PublicInfoStore: ObservableObject {
    static let endpoint = URL(string: "https://ai-no-tane.com/lp/koenotane/app-info.json")!
    private let cacheKey = "publicAppInfoCache.v1"
    @Published private(set) var info = PublicAppInfo.bundled
    @Published private(set) var refreshing = false
    @Published private(set) var status = ""
    private var lastAttempt = Date.distantPast
    private var timer: Timer?

    init() {
        if let data = UserDefaults.standard.data(forKey: cacheKey), let value = try? PublicAppInfo.decode(data) { info = value }
    }

    var updateAvailable: Bool { info.hasUpdate(installedBuild: Int(AppMetadata.build) ?? 0) }

    func start() {
        guard timer == nil else { return }
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func refresh(force: Bool = false) async {
        guard !refreshing, force || Date().timeIntervalSince(lastAttempt) >= 300 else { return }
        refreshing = true; lastAttempt = Date()
        defer { refreshing = false }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  response.url?.host == Self.endpoint.host, response.url?.scheme == "https",
                  response.expectedContentLength <= 65_536 else { throw PublicInfoError.invalid }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 65_536 else { throw PublicInfoError.invalid }
                data.append(byte)
            }
            let value = try PublicAppInfo.decode(data)
            UserDefaults.standard.set(data, forKey: cacheKey)
            info = value
            status = "最新の案内を読み込みました。"
        } catch {
            status = "案内を取得できないため、保存済みの内容を表示しています。"
        }
    }
}
