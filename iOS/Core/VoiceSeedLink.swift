import Foundation

enum VoiceSeedLink: Equatable {
    case dictate(UUID)
    case settings

    static func dictationURL(ticket: UUID) -> URL {
        URL(string: "koenotane://dictate?ticket=" + ticket.uuidString)!
    }
    init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "koenotane", parts.user == nil, parts.password == nil,
              parts.port == nil, parts.path.isEmpty, parts.fragment == nil else { return nil }
        if parts.host == "settings", parts.queryItems == nil { self = .settings; return }
        guard parts.host == "dictate", let items = parts.queryItems, items.count == 1,
              items[0].name == "ticket", let value = items[0].value, let id = UUID(uuidString: value) else { return nil }
        self = .dictate(id)
    }
}
