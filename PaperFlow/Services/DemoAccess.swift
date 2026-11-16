import Foundation

@MainActor enum DemoAccess {
    static let credentials = AIConfiguration(baseURL:"https://paperflow.local/device-demo",model:IterationConfig.demoModel)
    private static let ledgerAccount = AIConfiguration(baseURL:"https://paperflow.local/device-budget",model:"ledger")
    static func key() throws -> String { try APIKeyStore.read(credentials) }
    static func saveKey(_ value:String) throws { try APIKeyStore.save(value,configuration:credentials) }
    static func load() throws -> DemoLedger {
        let raw = try APIKeyStore.read(ledgerAccount)
        if raw.isEmpty { return DemoLedger() }
        guard let data = raw.data(using:.utf8), let ledger = try? JSONDecoder().decode(DemoLedger.self,from:data) else { throw ServiceError.message("演示额度记录无法读取，请联系演示维护人。") }
        return ledger
    }
    static func save(_ ledger:DemoLedger) throws {
        let data = try JSONEncoder().encode(ledger)
        try APIKeyStore.save(String(decoding:data,as:UTF8.self),configuration:ledgerAccount)
    }
}
