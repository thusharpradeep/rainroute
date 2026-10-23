import Foundation

enum HTTP {
    static let userAgent = "RainRoute/1.0 (iOS; +https://github.com/thusharpradeep/rainroute)"

    static func request(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// A request for a browser-facing page such as a Google Maps share link.
    static func htmlRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        return request
    }

    static func data(
        for request: URLRequest,
        session: URLSession = .shared
    ) async throws -> Data {        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.transport("No HTTP response was received.")
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw APIError.http(http.statusCode, String(body.prefix(300)))
            }
            return data
        } catch let error as APIError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }
}
