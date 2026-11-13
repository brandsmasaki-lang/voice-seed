import Foundation

@main struct PublicAppInfoTests {
    static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: "Resources/PublicAppInfo.json"))
        let original = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let valid = try PublicAppInfo.decode(data)
        var count = 0
        func check(_ condition: Bool, _ name: String) {
            guard condition else { fatalError("FAIL: " + name) }; count += 1
        }
        func rejected(_ change: (inout [String: Any]) -> Void, _ name: String) throws {
            var value = original; change(&value)
            let encoded = try JSONSerialization.data(withJSONObject: value)
            check((try? PublicAppInfo.decode(encoded)) == nil, name)
        }
        func changeLink(_ value: inout [String: Any], _ edit: (inout [String: Any]) -> Void) {
            var links = value["links"] as! [[String: Any]]; edit(&links[0]); value["links"] = links
        }
        check(valid.links.count == 5, "all configured links are displayed")
        check(valid.links.allSatisfy { $0.url?.scheme == "https" }, "only HTTPS destinations")
        check(!valid.hasUpdate(installedBuild: valid.latest.build), "same build is not an update")
        check(valid.hasUpdate(installedBuild: valid.latest.build - 1), "newer build is an update")
        check(!valid.hasUpdate(installedBuild: valid.latest.build + 1), "no downgrade notification")
        try rejected({ $0["schemaVersion"] = 2 }, "unknown schema")
        try rejected({ $0["links"] = [] }, "empty links")
        try rejected({ value in var links=value["links"] as! [[String: Any]]; links.append(links[0]); value["links"]=links }, "duplicate link IDs")
        try rejected({ value in changeLink(&value) { $0["url"] = "javascript:alert(1)" } }, "executable URL")
        try rejected({ value in changeLink(&value) { $0["url"] = "file:///tmp/example" } }, "local file URL")
        try rejected({ value in changeLink(&value) { $0["url"] = "http://example.com" } }, "unencrypted URL")
        try rejected({ value in changeLink(&value) { $0["url"] = "https://name:password@example.com" } }, "credentials in URL")
        try rejected({ value in changeLink(&value) { $0["url"] = "https://" } }, "missing host")
        try rejected({ value in changeLink(&value) { $0["title"] = "" } }, "empty label")
        try rejected({ value in changeLink(&value) { $0["title"] = String(repeating: "a", count: 151) } }, "oversized label")
        try rejected({ $0["intro"] = String(repeating: "a", count: 1001) }, "oversized introduction")
        try rejected({ $0["latest"] = ["version":"1.0.0", "build":-1, "notes":""] }, "invalid build")
        try rejected({ $0["latest"] = ["version":"latest", "build":8, "notes":""] }, "invalid version")
        check((try? PublicAppInfo.decode(Data(repeating: 32, count: 65_537))) == nil, "oversized response")
        check((try? PublicAppInfo.decode(Data("invalid JSON".utf8))) == nil, "malformed response")
        print("PASS: \(count) public display configuration and update-version checks")
    }
}
