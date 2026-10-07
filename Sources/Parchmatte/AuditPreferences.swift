import Foundation

/// Local audit transport for this app's persistent preferences. The runner
/// invokes the signed app executable, so macOS grants access to its sandbox
/// container without granting the test shell access to unrelated containers.
enum AuditPreferences {
    static func export(from defaults: UserDefaults, domain: String) throws -> Data {
        let values = defaults.persistentDomain(forName: domain) ?? [:]
        return try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
    }

    static func restore(_ data: Data, to defaults: UserDefaults, domain: String) throws {
        guard data.count <= 1_000_000,
              let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw CocoaError(.fileReadCorruptFile) }
        defaults.setPersistentDomain(values, forName: domain)
        guard defaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
    }
}
