import AVFoundation
import Foundation
import SmartTubeIOSCore
import Testing
@testable import KaraPitchTV

/// Does signing in to YouTube (the TV app's device-code flow, as SmartTube does) get past the bot
/// check, and do the signed-in clients still give direct MP4s that `PitchTap` can key-shift?
///
/// Run with `TEST_RUNNER_KARA_AUTH_PROBE=1 TEST_RUNNER_KARA_CHECK_OUT=<file> xcodebuild test
/// -only-testing:KaraPitchTVTests/AuthProbeLiveTests …`. The sign-in code shows up in the file;
/// enter it at youtube.com/activate. The token stays in memory and is never written out.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["KARA_AUTH_PROBE"] == "1"), .timeLimit(.minutes(15)))
struct AuthProbeLiveTests {
    /// Karaoke uploads and official music videos the app has played.
    static let videos = [
        ("WHayJZ3eMcE", "Dancing Queen, Sing King"), ("7fCMws3U2zE", "Dancing Queen, KaraFun"),
        ("5NPZG8GWJZs", "Crazy For You, Sing King"), ("x8SpSPBeeUE", "Make You Feel My Love, Sing King"),
        ("xFrGuyw1V8s", "Dancing Queen, official video"), ("DHutZXREZ0E", "Crazy For You, official video"),
    ]

    /// Appends lines to the report as they happen, so the sign-in code can be read while it waits.
    private final class Report: @unchecked Sendable {
        let path: String?
        init(path: String?) {
            self.path = path
            if let path { FileManager.default.createFile(atPath: path, contents: nil) }
        }
        func line(_ text: String) {
            guard let path, let handle = FileHandle(forWritingAtPath: path) else { return }
            handle.seekToEndOfFile()
            handle.write(Data((text + "\n").utf8))
            try? handle.close()
        }
    }

    @Test func signedInClientsAgainstTheBotCheck() async throws {
        let report = Report(path: ProcessInfo.processInfo.environment["KARA_CHECK_OUT"])
        let token = try await signIn(report)
        let signedIn = InnerTubeAPI(authToken: token)
        let anonymous = InnerTubeAPI()

        let lookups: [(String, @Sendable (String) async throws -> PlayerInfo)] = [
            ("visionOS (anonymous)", { try await anonymous.fetchPlayerInfoVisionOS(videoId: $0) }),
            ("TV (signed in)", { try await signedIn.fetchPlayerInfoAuthenticated(videoId: $0) }),
            ("iOS (signed in)", { try await signedIn.fetchPlayerInfoiOSAuthenticated(videoId: $0) }),
            ("web (signed in)", { try await signedIn.fetchPlayerInfoWebAuthenticated(videoId: $0) }),
        ]
        for (id, name) in Self.videos {
            report.line("\n== \(id) \(name)")
            for (client, fetch) in lookups {
                report.line("  \(client): \(await Self.probe(id, fetch))")
            }
        }
        report.line("\nDONE")
    }

    // MARK: - Sign-in (RFC 8628 device flow, like AuthService+DeviceFlow)

    private static let scope = "openid http://gdata.youtube.com https://www.googleapis.com/auth/youtube-paid-content https://www.googleapis.com/auth/youtube"

    private func signIn(_ report: Report) async throws -> String {
        let creds = await YouTubeClientCredentialsFetcher().credentials()
        let device = try await Self.post("https://oauth2.googleapis.com/device/code", [
            "client_id": creds.clientId, "client_secret": creds.clientSecret, "scope": Self.scope,
        ])
        guard let deviceCode = device["device_code"] as? String, let userCode = device["user_code"] as? String else {
            report.line("❌ no device code: \(device)")
            throw ProbeError.signIn
        }
        let url = device["verification_url"] as? String ?? "https://www.youtube.com/activate"
        let interval = device["interval"] as? Int ?? 5
        let expires = ContinuousClock.now + .seconds(device["expires_in"] as? Int ?? 600)
        report.line("SIGN-IN CODE: \(userCode) at \(url)")

        while ContinuousClock.now < expires {
            try await Task.sleep(for: .seconds(interval))
            let answer = try await Self.post("https://oauth2.googleapis.com/token", [
                "code": deviceCode, "client_id": creds.clientId, "client_secret": creds.clientSecret,
                "grant_type": "http://oauth.net/grant_type/device/1.0",
            ])
            if let token = answer["access_token"] as? String {
                report.line("✅ signed in")
                return token
            }
            switch answer["error"] as? String {
            case "authorization_pending": continue
            case "slow_down": try await Task.sleep(for: .seconds(5))
            default:
                report.line("❌ sign-in failed: \(answer["error"] ?? "unknown")")
                throw ProbeError.signIn
            }
        }
        report.line("❌ the code expired")
        throw ProbeError.signIn
    }

    private static func post(_ url: String, _ form: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&").utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    enum ProbeError: Error { case signIn }

    // MARK: - One lookup

    /// What one client gives for one video: refused, no usable MP4, or a pick and whether it plays.
    private static func probe(_ id: String, _ fetch: @Sendable (String) async throws -> PlayerInfo) async -> String {
        let info: PlayerInfo
        do {
            info = try await fetch(id)
        } catch {
            return "❌ \(error)"
        }
        var rejections: [String: Int] = [:]
        for format in info.formats {
            if let reason = StreamResolver.rejection(format) { rejections[reason, default: 0] += 1 }
        }
        let summary = "\(info.formats.filter(StreamResolver.isDirect).count)/\(info.formats.count) direct"
            + (rejections.isEmpty ? "" : " (" + rejections.map { "\($0.key) ×\($0.value)" }.sorted().joined(separator: ", ") + ")")
            + (info.hlsURL != nil ? " +HLS" : "")
        guard let pick = StreamResolver.pick(info.formats), let videoURL = pick.video.url else {
            return "➖ \(summary), nothing KaraPitch can pitch-shift"
        }
        let range = await StreamProbe.rangeCheck(videoURL, userAgent: StreamClient.visionOS.userAgent)
        let load = await Self.load(videoURL)
        let ok = range.ok && load == nil
        return "\(ok ? "✅" : "⚠️") \(summary) · \(pick.description) · range \(range.summary) · AVFoundation \(load ?? "opens it")"
    }

    /// Nil when AVFoundation loads the video track within 15 s, else why not.
    private static func load(_ url: URL) async -> String? {
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": StreamClient.visionOS.userAgent]])
        let timeout = Task {
            try await Task.sleep(for: .seconds(15))
            asset.cancelLoading()
        }
        defer { timeout.cancel() }
        do {
            return try await asset.loadTracks(withMediaType: .video).isEmpty ? "no video track" : nil
        } catch {
            return "fails: \(error.localizedDescription)"
        }
    }
}
