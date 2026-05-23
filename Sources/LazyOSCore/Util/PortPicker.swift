import Foundation
import Darwin

public enum PortPicker {
    /// Returns true if the TCP port is free on localhost.
    public static func isFree(_ port: Int) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        if sock < 0 { return false }
        defer { close(sock) }

        var yes: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = UInt16(port).bigEndian
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    /// Returns a free port, preferring the requested one.
    public static func pick(preferred: Int, range: ClosedRange<Int> = 30000...39999) -> Int {
        if isFree(preferred) { return preferred }
        for p in range where isFree(p) { return p }
        return preferred // fallback; will error at compose time
    }
}
