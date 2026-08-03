import Darwin
import Foundation

public struct PublicNetworkHostValidator: Sendable {
    public init() {}

    public func allows(_ url: URL) async -> Bool {
        guard let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = url.host,
            !host.isEmpty
        else {
            return false
        }

        return await Task.detached(priority: .utility) {
            Self.resolve(host: host).map { !$0.isEmpty && $0.allSatisfy(Self.isPublicAddress) } ?? false
        }.value
    }

    static func isPublicAddress(_ bytes: [UInt8]) -> Bool {
        switch bytes.count {
        case 4:
            return isPublicIPv4(bytes)
        case 16:
            if bytes.prefix(10).allSatisfy({ $0 == 0 }), bytes[10] == 0xff, bytes[11] == 0xff {
                return isPublicIPv4(Array(bytes.suffix(4)))
            }
            return isPublicIPv6(bytes)
        default:
            return false
        }
    }

    private static func resolve(host: String) -> [[UInt8]]? {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG | AI_NUMERICSERV,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, "443", &hints, &result) == 0, let first = result else {
            return nil
        }
        defer { freeaddrinfo(first) }

        var addresses: [[UInt8]] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let entry = cursor?.pointee {
            if entry.ai_family == AF_INET, let address = entry.ai_addr {
                let ipv4 = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                addresses.append(withUnsafeBytes(of: ipv4) { Array($0) })
            } else if entry.ai_family == AF_INET6, let address = entry.ai_addr {
                let ipv6 = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
                addresses.append(withUnsafeBytes(of: ipv6) { Array($0) })
            }
            cursor = entry.ai_next
        }
        return addresses
    }

    private static func isPublicIPv4(_ address: [UInt8]) -> Bool {
        let first = address[0]
        let second = address[1]

        switch first {
        case 0, 10, 127:
            return false
        case 100 where (64...127).contains(second):
            return false
        case 169 where second == 254:
            return false
        case 172 where (16...31).contains(second):
            return false
        case 192 where second == 0 || second == 168:
            return false
        case 198 where second == 18 || second == 19 || second == 51:
            return false
        case 203 where second == 0:
            return false
        case 224...255:
            return false
        default:
            return true
        }
    }

    private static func isPublicIPv6(_ address: [UInt8]) -> Bool {
        if address.allSatisfy({ $0 == 0 }) { return false }  // Unspecified.
        if address.dropLast().allSatisfy({ $0 == 0 }), address.last == 1 { return false }  // Loopback.
        if address[0] & 0xfe == 0xfc { return false }  // Unique local fc00::/7.
        if address[0] == 0xfe, address[1] & 0xc0 == 0x80 { return false }  // Link local fe80::/10.
        if address[0] == 0xff { return false }  // Multicast ff00::/8.
        if address[0] == 0x20, address[1] == 0x01, address[2] == 0x0d, address[3] == 0xb8 {
            return false  // Documentation 2001:db8::/32.
        }
        if address.prefix(8) == [0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00] {
            return false  // Discard-only 100::/64.
        }
        return true
    }
}
