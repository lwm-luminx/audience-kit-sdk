import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Why talking over the control socket failed.
public enum ControlSocketError: Error, CustomStringConvertible, Equatable {
    /// A socket path must fit `sockaddr_un.sun_path` (104 bytes on macOS, 108 on Linux).
    case pathTooLong(String)
    /// No Arbiter listens there: no socket file, or a stale one.
    case notRunning(String)
    /// Another Arbiter already answers on the path.
    case alreadyRunning(String)
    case system(String, Int32)
    case badMessage(String)

    public var description: String {
        switch self {
        case .pathTooLong(let path): "The socket path is too long for a Unix socket: \(path)"
        case .notRunning(let path): "Arbiter isn't running (nothing answers at \(path))."
        case .alreadyRunning(let path): "Another Arbiter already answers at \(path)."
        case .system(let call, let code): "\(call) failed: \(String(cString: strerror(code)))"
        case .badMessage(let why): "Unreadable message: \(why)"
        }
    }
}

/// The control socket's plumbing: a Unix domain socket that only the same user can use.
///
/// - The socket file is made with mode 0600 inside a folder only the user reaches (the app's sandbox container), and
///   every connection's peer is checked with `getpeereid` (`SO_PEERCRED` on Linux): another user's process is turned
///   away before it can send anything. There's no TCP listener, so nothing off this Mac can reach it.
/// - One request per connection: a JSON line in, a JSON line out, closed.
enum ControlSocket {
    /// The largest message either side accepts.
    static let maxMessage = 4 * 1024 * 1024

    static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard !bytes.isEmpty, bytes.count < capacity else { throw ControlSocketError.pathTooLong(path) }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        #if canImport(Darwin)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif
        return address
    }

    static func makeSocket() throws -> Int32 {
        #if canImport(Darwin)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        #else
        let fd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        #endif
        guard fd >= 0 else { throw ControlSocketError.system("socket", errno) }
        #if canImport(Darwin)
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        #endif
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        return fd
    }

    static func withAddress<T>(_ address: sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        var address = address
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }

    static func setTimeout(_ fd: Int32, seconds: Int) {
        var time = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &time, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &time, socklen_t(MemoryLayout<timeval>.size))
    }

    static func writeAll(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard var pointer = raw.baseAddress else { return }
            var left = raw.count
            while left > 0 {
                #if canImport(Darwin)
                let wrote = write(fd, pointer, left)
                #else
                let wrote = send(fd, pointer, left, Int32(MSG_NOSIGNAL))
                #endif
                if wrote < 0 {
                    if errno == EINTR { continue }
                    throw ControlSocketError.system("write", errno)
                }
                left -= wrote
                pointer += wrote
            }
        }
    }

    /// Reads up to the first newline (not included), or to the end of the stream.
    static func readLine(_ fd: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno == EINTR { continue }
                throw ControlSocketError.system("read", errno)
            }
            if count == 0 { return data }
            if let newline = buffer[0..<count].firstIndex(of: UInt8(ascii: "\n")) {
                data.append(contentsOf: buffer[0..<newline])
                return data
            }
            data.append(contentsOf: buffer[0..<count])
            guard data.count <= maxMessage else { throw ControlSocketError.badMessage("over \(maxMessage) bytes") }
        }
    }

    /// The user id of the process on the other end.
    static func peerUID(_ fd: Int32) -> uid_t? {
        #if canImport(Darwin)
        var uid: uid_t = 0, gid: gid_t = 0
        return getpeereid(fd, &uid, &gid) == 0 ? uid : nil
        #else
        // struct ucred { pid_t pid; uid_t uid; gid_t gid; }, read raw: SO_PEERCRED is 17 on Linux.
        var credentials = [UInt32](repeating: 0, count: 3)
        var length = socklen_t(MemoryLayout<UInt32>.size * 3)
        let result = credentials.withUnsafeMutableBytes { getsockopt(fd, SOL_SOCKET, 17, $0.baseAddress, &length) }
        return result == 0 ? uid_t(credentials[1]) : nil
        #endif
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

/// The app's side: listens on the socket and answers each request with `handler`.
public final class ControlServer: @unchecked Sendable {
    public typealias Handler = @Sendable (ControlRequest) async -> ControlResponse

    public let path: String
    private let handler: Handler
    private let lock = NSLock()
    private var listener: Int32 = -1
    private var stopped = false

    public init(path: String, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    deinit { stop() }

    /// Makes the socket and starts accepting. A stale socket file (nothing answers on it) is replaced; a live one
    /// means another Arbiter of this user's is serving, and this one stays quiet.
    public func start() throws {
        let address = try ControlSocket.address(path)
        let folder = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        if ControlClient.answers(path: path) { throw ControlSocketError.alreadyRunning(path) }
        unlink(path)
        let fd = try ControlSocket.makeSocket()
        // Made with 0600 from the start: no moment where another user could connect.
        let mask = umask(0o177)
        let bound = ControlSocket.withAddress(address) { bind(fd, $0, $1) }
        umask(mask)
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw ControlSocketError.system("bind", code)
        }
        chmod(path, 0o600)
        guard listen(fd, 16) == 0 else {
            let code = errno
            close(fd)
            unlink(path)
            throw ControlSocketError.system("listen", code)
        }
        lock.lock()
        listener = fd
        stopped = false
        lock.unlock()
        let thread = Thread { [weak self] in self?.acceptLoop(fd) }
        thread.name = "arbiterctl.accept"
        thread.start()
    }

    /// Stops accepting and removes the socket file.
    public func stop() {
        lock.lock()
        let fd = listener
        let wasRunning = !stopped && fd >= 0
        stopped = true
        listener = -1
        lock.unlock()
        guard wasRunning else { return }
        shutdown(fd, 2) // SHUT_RDWR on macOS and Linux: wakes the accept loop
        close(fd)
        unlink(path)
    }

    private var isStopped: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }

    private func acceptLoop(_ fd: Int32) {
        while !isStopped {
            let connection = accept(fd, nil, nil)
            if connection < 0 {
                if errno == EINTR || errno == ECONNABORTED { continue }
                return
            }
            serve(connection)
        }
    }

    private func serve(_ connection: Int32) {
        ControlSocket.setTimeout(connection, seconds: 10)
        guard ControlSocket.peerUID(connection) == getuid() else {
            // Another user's process: no answer at all.
            close(connection)
            return
        }
        let handler = self.handler
        DispatchQueue.global(qos: .userInitiated).async {
            let response: ControlResponse
            do {
                let line = try ControlSocket.readLine(connection)
                let request = try JSONDecoder().decode(ControlRequest.self, from: line)
                let box = ResponseBox()
                let done = DispatchSemaphore(value: 0)
                Task {
                    box.value = await handler(request)
                    done.signal()
                }
                done.wait()
                response = box.value ?? .failure("No answer.")
            } catch let error as DecodingError {
                response = .failure("Arbiter didn't understand that request (\(error)). Is arbiterctl newer than the app?")
            } catch {
                response = .failure("\(error)")
            }
            if var data = try? ControlSocket.encoder.encode(response) {
                data.append(UInt8(ascii: "\n"))
                try? ControlSocket.writeAll(connection, data)
            }
            close(connection)
        }
    }
}

private final class ResponseBox: @unchecked Sendable {
    var value: ControlResponse?
}

/// `arbiterctl`'s side: sends one request and waits for the answer.
public enum ControlClient {
    /// Sends `request` to the Arbiter at `path`. `timeout` covers the whole exchange; quitting and starting Glam can
    /// take a while.
    public static func send(_ request: ControlRequest, path: String, timeout: Int = 60) throws -> ControlResponse {
        let fd = try connect(path: path)
        defer { close(fd) }
        ControlSocket.setTimeout(fd, seconds: timeout)
        var data = try ControlSocket.encoder.encode(request)
        data.append(UInt8(ascii: "\n"))
        try ControlSocket.writeAll(fd, data)
        let line = try ControlSocket.readLine(fd)
        guard !line.isEmpty else { throw ControlSocketError.badMessage("Arbiter closed the connection without answering") }
        do {
            return try JSONDecoder().decode(ControlResponse.self, from: line)
        } catch {
            throw ControlSocketError.badMessage("\(error)")
        }
    }

    /// Whether an Arbiter answers at `path` now.
    public static func answers(path: String) -> Bool {
        guard let fd = try? connect(path: path) else { return false }
        close(fd)
        return true
    }

    static func connect(path: String) throws -> Int32 {
        let address = try ControlSocket.address(path)
        let fd = try ControlSocket.makeSocket()
        #if canImport(Darwin)
        let result = ControlSocket.withAddress(address) { Darwin.connect(fd, $0, $1) }
        #else
        let result = ControlSocket.withAddress(address) { Glibc.connect(fd, $0, $1) }
        #endif
        if result != 0 {
            let code = errno
            close(fd)
            if code == ENOENT || code == ECONNREFUSED || code == ENOTDIR { throw ControlSocketError.notRunning(path) }
            throw ControlSocketError.system("connect", code)
        }
        return fd
    }
}
