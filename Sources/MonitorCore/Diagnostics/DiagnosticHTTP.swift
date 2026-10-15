import Foundation

private final class HTTPSRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme?.lowercased() == "https" ? request : nil)
    }
}

public enum DiagnosticHTTP {
    /// Read incrementally: an arbitrary custom endpoint cannot allocate an unbounded body.
    public static func fetch(_ url: URL, maximumBytes: Int, method: String = "GET", headers: [String: String] = [:]) async throws -> Data {
        guard url.scheme?.lowercased() == "https" else { throw DiagnosticError.failed("HTTPS is required") }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration, delegate: HTTPSRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = method
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode),
              response.expectedContentLength <= maximumBytes || method == "HEAD" else {
            throw DiagnosticError.failed("Unexpected diagnostic HTTP response")
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else { throw DiagnosticError.failed("Diagnostic HTTP response exceeded limit") }
            data.append(byte)
        }
        return data
    }
    public static func latency(_ url: URL) async throws -> Double {
        let start = ProcessInfo.processInfo.systemUptime
        _ = try await fetch(url, maximumBytes: 1024, method: "HEAD")
        return (ProcessInfo.processInfo.systemUptime - start) * 1000
    }
}

public enum NetworkTestConfiguration {
    public static func endpoints(_ data: Data) throws -> [String] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let urls = json["urls"] as? [String: String] else { throw DiagnosticError.failed("Invalid network test configuration") }
        return try ["small_https_download_url", "large_https_download_url", "https_upload_url"].map { key in
            guard let raw = urls[key], let url = URL(string: raw), url.scheme == "https", url.host != nil,
                  url.user == nil, url.password == nil else { throw DiagnosticError.failed("Invalid network test endpoint") }
            return raw
        }
    }
}
