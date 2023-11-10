import Foundation

struct SocketError: LocalizedError, CustomStringConvertible {
    var code: Code
    var errorDescription: String?
    
    var description: String { errorDescription ?? code.description }
    
    init(code rawCode: Code.RawValue, api: String? = nil) {
        self.code = Code(rawValue: rawCode) ?? .UNKNOWN
        self.errorDescription = "\(api.flatMap({ "\($0) " }) ?? "")\(code == .UNKNOWN ? "\(rawCode)" : code.description)"
    }
    
    enum Code: Int32, CustomStringConvertible {
        case EACCES = 13
        case EADDRINUSE = 48
        case EBADF = 9
        case EINVAL = 22
        case ENOTSOCK = 38
        case EADDRNOTAVAIL = 49
        case EFAULT = 14
        case ELOOP = 62
        case ENAMETOOLONG = 63
        case ENOENT = 2
        case ENOMEM = 12
        case ENOTDIR = 20
        case EROFS = 30
        case UNKNOWN = -99
        
        var description: String {
            switch self {
            case .EACCES: return "EACCES"
            case .EADDRINUSE: return "EADDRINUSE"
            case .EBADF: return "EBADF"
            case .EINVAL: return "EINVAL"
            case .ENOTSOCK: return "ENOTSOCK"
            case .EADDRNOTAVAIL: return "EADDRNOTAVAIL"
            case .EFAULT: return "EFAULT"
            case .ELOOP: return "ELOOP"
            case .ENAMETOOLONG: return "ENAMETOOLONG"
            case .ENOENT: return "ENOENT"
            case .ENOMEM: return "ENOMEM"
            case .ENOTDIR: return "ENOTDIR"
            case .EROFS: return "EROFS"
            case .UNKNOWN: return "UNKNOWN"
            }
        }
    }
}
