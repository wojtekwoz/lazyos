import Foundation

public enum AppKeyGen {
    /// Laravel-style APP_KEY: "base64:" + base64 of 32 random bytes.
    public static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return "base64:" + Data(bytes).base64EncodedString()
    }
}
