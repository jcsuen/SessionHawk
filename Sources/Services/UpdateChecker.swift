import Foundation
import Observation

/// Checks paulobuilds.com daily for a newer release. The request carries the
/// app version only — it doubles as an anonymous usage ping (country is
/// aggregated at the edge; no identifiers are sent or stored).
@Observable
@MainActor
public final class UpdateChecker {
    public private(set) var updateAvailable: String? = nil
    public let releaseURL = URL(string: "https://github.com/jcsuen/SessionHawk/releases/latest")!

    public static let currentVersion =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

    public init() {
        // Debug/preview: SESSIONHAWK_FAKE_UPDATE=0.9.9 forces the banner
        if let fake = ProcessInfo.processInfo.environment["SESSIONHAWK_FAKE_UPDATE"] {
            updateAvailable = fake
        }
    }

    public func start() {
        check()
        Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.check()
            }
        }
    }

    public func check() {
        guard let url = URL(string: "https://paulobuilds.com/sessionhawk/version?v=\(Self.currentVersion)") else { return }
        Task { @MainActor [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let info = try? JSONDecoder().decode(VersionInfo.self, from: data) else { return }
            if Self.isNewer(info.latest, than: Self.currentVersion) {
                self?.updateAvailable = info.latest
            }
        }
    }

    private struct VersionInfo: Codable {
        let latest: String
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").compactMap { Int($0) }
        let b = current.split(separator: ".").compactMap { Int($0) }
        guard !a.isEmpty else { return false }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
