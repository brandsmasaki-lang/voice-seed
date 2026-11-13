import Foundation

/// Public display data only. This schema cannot change recording, permissions or execute code.
struct PublicAppInfo: Codable, Equatable {
    let schemaVersion: Int
    let revision: String
    let intro: String
    let supportTitle: String
    let links: [AppLink]
    let latest: PublicRelease

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 65_536 else { throw PublicInfoError.invalid }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.schemaVersion == 1, !value.revision.isEmpty, value.revision.count <= 100,
              !value.intro.isEmpty, value.intro.count <= 1000,
              !value.supportTitle.isEmpty, value.supportTitle.count <= 100,
              (1...12).contains(value.links.count), Set(value.links.map(\.id)).count == value.links.count,
              value.latest.build > 0, value.latest.build <= 1_000_000_000,
              value.latest.version.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil,
              value.latest.notes.count <= 2000 else { throw PublicInfoError.invalid }
        for link in value.links {
            guard !link.id.isEmpty, link.id.count <= 64, !link.title.isEmpty, link.title.count <= 150,
                  link.detail.count <= 300, !link.symbol.isEmpty, link.symbol.count <= 80,
                  link.destination.count <= 2048, link.url != nil else { throw PublicInfoError.invalid }
        }
        return value
    }

    static var bundled: Self {
        // The checked bundle is the fallback on first launch without a network connection.
        guard let url = Bundle.main.url(forResource: "PublicAppInfo", withExtension: "json"),
              let data = try? Data(contentsOf: url), let value = try? decode(data) else {
            return Self(schemaVersion: 1, revision: "fallback", intro: "無料で使える音声入力アプリです。", supportTitle: "開発者・サポート", links: [], latest: PublicRelease(version: "0.0.0", build: 1, notes: ""))
        }
        return value
    }

    func hasUpdate(installedBuild: Int) -> Bool { latest.build > installedBuild }
}

struct PublicRelease: Codable, Equatable {
    let version: String
    let build: Int
    let notes: String
}

struct AppLink: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let destination: String
    enum CodingKeys: String, CodingKey { case id, title, detail, symbol; case destination = "url" }
    var url: URL? {
        guard let value = URLComponents(string: destination), value.scheme == "https",
              let host = value.host, !host.isEmpty, value.user == nil, value.password == nil,
              value.port == nil || value.port == 443 else { return nil }
        return value.url
    }
}

enum PublicInfoError: Error { case invalid }
