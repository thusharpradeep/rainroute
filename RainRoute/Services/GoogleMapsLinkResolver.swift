import Foundation

protocol GoogleMapsLinkResolving {
    /// Expands a shortened Google Maps share link into a full directions URL.
    /// Non-short links are returned unchanged.
    func resolve(_ url: URL) async throws -> URL
}

/// Resolves `maps.app.goo.gl` links without an API key.
///
/// Google normally answers with a redirect to the full `google.com/maps` URL.
/// When it serves an interstitial instead, the canonical or Open Graph URL in
/// the page body is used as a fallback. A consent page with neither produces a
/// typed error that tells the rider how to paste the full URL.
struct GoogleMapsLinkResolver: GoogleMapsLinkResolving {
    var session: URLSession = .shared

    func resolve(_ url: URL) async throws -> URL {
        guard url.scheme == "http" || url.scheme == "https" else {
            throw GoogleMapsLinkError.unsupportedScheme
        }
        guard GoogleMapsLinkParser.isShortLink(url) else {
            return url
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: HTTP.htmlRequest(url: url))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GoogleMapsLinkError.resolutionFailed(
                "Check your connection and try again, or open the link in Safari and paste the full google.com/maps URL."
            )
        }

        guard let http = response as? HTTPURLResponse else {
            throw GoogleMapsLinkError.resolutionFailed(
                "Open the link in Safari, copy the full google.com/maps URL, and paste that instead."
            )
        }
        guard (200..<400).contains(http.statusCode) else {
            throw GoogleMapsLinkError.resolutionFailed(
                "The link returned HTTP \(http.statusCode). Open it in Safari and paste the full google.com/maps URL."
            )
        }

        let finalURL = http.url ?? url
        if let candidate = acceptableURL(from: finalURL) {
            return candidate
        }

        let body = String(data: data, encoding: .utf8) ?? ""
        if let candidate = canonicalURL(in: body, relativeTo: finalURL) {
            return candidate
        }

        throw GoogleMapsLinkError.resolutionFailed(
            "Open the link in Safari, copy the full google.com/maps URL, and paste that instead."
        )
    }

    private func acceptableURL(from url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        guard GoogleMapsLinkParser.isGoogleMapsURL(url),
              !GoogleMapsLinkParser.isShortLink(url) else {
            return nil
        }
        guard url.path.contains("/maps") else {
            return nil
        }
        return url
    }

    private func canonicalURL(in html: String, relativeTo baseURL: URL) -> URL? {
        let patterns = [
            #"<link[^>]+rel=["']canonical["'][^>]*>"#,
            #"<meta[^>]+property=["']og:url["'][^>]*>"#
        ]
        let range = NSRange(html.startIndex..<html.endIndex, in: html)

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ) else {
                continue
            }

            for match in regex.matches(in: html, range: range) {
                guard let matchRange = Range(match.range, in: html) else { continue }
                let tag = String(html[matchRange])
                guard let raw = attributeValue(
                    in: tag,
                    names: ["href", "content"]
                ) else {
                    continue
                }
                let decoded = decodeHTMLEntities(raw)
                guard let candidate = URL(string: decoded, relativeTo: baseURL)?.absoluteURL,
                      let acceptable = acceptableURL(from: candidate) else {
                    continue
                }
                return acceptable
            }
        }
        return nil
    }

    private func attributeValue(in tag: String, names: [String]) -> String? {
        for name in names {
            let pattern = #"\b"# + name + #"\s*=\s*["']([^"']+)["']"#
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ) else {
                continue
            }
            let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
            guard let match = regex.firstMatch(in: tag, range: range),
                  match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: tag) else {
                continue
            }
            return String(tag[valueRange])
        }
        return nil
    }

    private func decodeHTMLEntities(_ value: String) -> String {
        let replacements = [
            ("&quot;", "\""),
            ("&#34;", "\""),
            ("&#x27;", "'"),
            ("&#39;", "'"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&#38;", "&"),
            ("&#x26;", "&"),
            ("&amp;", "&")
        ]
        var result = value
        for (entity, replacement) in replacements {
            result = result.replacingOccurrences(
                of: entity,
                with: replacement,
                options: [.caseInsensitive]
            )
        }
        return result
    }
}
