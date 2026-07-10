import Foundation
import Security

// MARK: - 安全密码箱存储助手 (macOS Keychain)
/// Security.framework 的查询函数本身可跨线程调用；此类型不保存任何可变共享状态。
final class KeychainHelper: @unchecked Sendable {
    static let shared = KeychainHelper()
    private init() {}
    
    private let service = "com.luku.pdfextractor.apikey"
    private let account = "aiApiKey"
    
    /// 保存 API Key 到 Keychain
    @discardableResult
    func save(_ key: String) -> Bool {
        guard !key.isEmpty else { return delete() }
        guard let data = key.data(using: .utf8) else { return false }
        
        // 优先尝试更新已有条目，避免先删后加导致的凭证丢失窗口
        let searchQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let updateStatus = SecItemUpdate(searchQuery as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        
        // 如果条目不存在，执行新增写入
        if updateStatus == errSecItemNotFound {
            var addQuery = searchQuery
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            return addStatus == errSecSuccess
        }
        
        return false
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
    @discardableResult
    func delete() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        // 条目原本不存在也视为清理成功，便于界面保持幂等。
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
