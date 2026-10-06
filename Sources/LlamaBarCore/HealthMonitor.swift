import Foundation

private final class LocalSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    // Reject redirects so health polling always stays on the configured loopback endpoint.
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) { completionHandler(nil) }
}

public enum HealthMonitor {
    /// Reads at most 16 KiB from loopback. Returns false while loading; throws on invalid responses.
    public static func isReady(port: Int) async throws -> Bool {
        guard (1024...65535).contains(port), let url = URL(string: "http://127.0.0.1:\(port)/health") else {
            throw AppFailure("Invalid health-check port.")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 2
        configuration.connectionProxyDictionary = [:]
        let session = URLSession(
            configuration: configuration, delegate: LocalSessionDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (stream, response) = try await session.bytes(from: url)
        guard let response = response as? HTTPURLResponse else {
            throw AppFailure("Health check returned no HTTP response.")
        }
        var data = Data()
        for try await byte in stream {
            guard data.count < 16_384 else { throw AppFailure("Health response exceeds 16 KiB.") }
            data.append(byte)
        }
        if response.statusCode == 503 { return false }
        guard response.statusCode == 200 else {
            throw AppFailure("Health check returned HTTP \(response.statusCode).")
        }
        let payload = try JSONDecoder().decode(HealthResponse.self, from: data)
        return payload.status == "ok"
    }

    private struct HealthResponse: Decodable { let status: String }
}
