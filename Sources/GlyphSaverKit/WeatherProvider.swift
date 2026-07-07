import Foundation

/// Fetches a one-line weather summary ("⛅️ +23°C") from wttr.in — keyless,
/// IP-located. Cached 15 minutes; failures leave the last value (or nothing) so
/// the saver never blocks or shows errors.
public final class WeatherProvider {
    public static let shared = WeatherProvider()

    public private(set) var summary: String?
    private var lastAttempt: Date?
    private var inFlight = false
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        session = URLSession(configuration: config)
    }

    public func refreshIfStale() {
        if let last = lastAttempt, Date().timeIntervalSince(last) < 15 * 60 { return }
        guard !inFlight, let url = URL(string: "https://wttr.in/?format=%c%t") else { return }
        inFlight = true
        lastAttempt = Date()
        session.dataTask(with: url) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                guard let data,
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      let raw = String(data: data, encoding: .utf8) else { return }
                let text = raw
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "+", with: "")
                // Sanity: short, no HTML/error blurbs.
                if !text.isEmpty, text.count < 24, !text.contains("<"),
                   !text.lowercased().contains("unknown") {
                    self.summary = text
                }
            }
        }.resume()
    }
}
