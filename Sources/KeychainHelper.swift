import Foundation
import Security

// MARK: - 安全密码箱存储助手 (macOS Keychain)
class KeychainHelper {
    static let shared = KeychainHelper()
    private init() {}
    
    private let service = "com.luku.pdfextractor.apikey"
    private let account = "aiApiKey"
    
    /// 保存 API Key 到 Keychain
    @discardableResult
    func save(_ key: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }
        
        // 写入前先清理旧凭证，保证唯一性
        delete()
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// 从 Keychain 读取 API Key
    func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    /// 从 Keychain 删除 API Key
    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
