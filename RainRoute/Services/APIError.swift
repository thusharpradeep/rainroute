import Foundation

enum APIError: LocalizedError, Equatable {
    case invalidURL
    case transport(String)
    case http(Int, String)
    case decoding(String)
    case service(String)
    case incompleteForecast

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The app could not build a valid request. Try again."
        case .transport(let message):
            return "Network request failed: \(message)"
        case .http(let status, let body):
            let detail = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if status == 429 {
                return "The free service is busy. Wait a few seconds and try again."
            }
            return detail.isEmpty
                ? "The service returned HTTP \(status). Try again."
                : "The service returned HTTP \(status): \(detail)"
        case .decoding(let context):
            return "RainRoute could not read the \(context). The service may have changed."
        case .service(let message):
            return message
        case .incompleteForecast:
            return "The weather service returned an incomplete forecast. Try refreshing."
        }
    }
}
