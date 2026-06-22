import Foundation

public struct EventFields: Equatable, Sendable {
    public var url: URL?
    public var location: String?
    public var notes: String?
    public var title: String?

    public init(url: URL? = nil, location: String? = nil, notes: String? = nil, title: String? = nil) {
        self.url = url
        self.location = location
        self.notes = notes
        self.title = title
    }
}

public struct ExtractedLink: Equatable, Sendable {
    public let url: URL
    public let providerName: String?
}

public enum LinkExtractor {
    /// Scans the event's fields in priority order (url, location, notes, title) and
    /// returns the first URL whose string contains an enabled provider's pattern.
    public static func extract(from fields: EventFields,
                               providers: [VideoProvider]) -> ExtractedLink? {
        let enabled = providers.filter { $0.enabled }
        let blobs = candidateBlobs(fields)

        for blob in blobs {
            for url in urls(in: blob) {
                let s = url.absoluteString
                if let provider = enabled.first(where: {
                    s.range(of: $0.pattern, options: .caseInsensitive) != nil
                }) {
                    return ExtractedLink(url: url, providerName: provider.name)
                }
            }
        }
        return nil
    }

    private static func candidateBlobs(_ fields: EventFields) -> [String] {
        var blobs: [String] = []
        if let u = fields.url?.absoluteString { blobs.append(u) }
        if let l = fields.location { blobs.append(l) }
        if let n = fields.notes { blobs.append(n) }
        if let t = fields.title { blobs.append(t) }
        return blobs
    }

    static func urls(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range)
            .compactMap { $0.url }
            .filter {
                let scheme = $0.scheme?.lowercased()
                return scheme == "http" || scheme == "https"
            }
    }
}
