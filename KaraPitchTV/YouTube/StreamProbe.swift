import Foundation
import SmartTubeIOSCore
import os

/// One ranged GET against a stream URL.
struct RangeCheck: Sendable {
    static let byteCount = 128 * 1024

    let status: Int
    let bytes: Int
    let millis: Int
    let error: String?

    /// The CDN can answer the first bytes and then stall, so the whole range has to arrive.
    var ok: Bool { status == 206 && bytes == Self.byteCount }

    var summary: String { error ?? "\(status) \(bytes / 1024)KB \(millis)ms" }
}

/// What one client returned for one video, and whether its URLs actually serve bytes.
struct ProbeRow: Identifiable, Sendable {
    let id = UUID()
    let videoID: String
    let client: StreamClient
    var formatCount = 0
    var directCount = 0
    var hasHLS = false
    /// Rejection reason → count, for formats that weren't direct.
    var rejections: [String: Int] = [:]
    var pick: String?
    var video: RangeCheck?
    var audio: RangeCheck?
    var error: String?

    var usable: Bool { pick != nil && video?.ok == true && (audio?.ok ?? true) }

    var summary: String {
        let result = error ?? pick ?? "no direct avc1/mp4a"
        let ranges = [video.map { "video \($0.summary)" }, audio.map { "audio \($0.summary)" }].compactMap { $0 }
        return "\(usable ? "✅" : "❌") \(videoID) \(client.rawValue): formats \(directCount)/\(formatCount) direct"
            + "\(hasHLS ? " +HLS" : "")"
            + (rejections.isEmpty ? "" : " (" + rejections.sorted { $0.key < $1.key }.map { "\($0.key) ×\($0.value)" }.joined(separator: ", ") + ")")
            + " · \(result)" + (ranges.isEmpty ? "" : " · " + ranges.joined(separator: ", "))
    }
}

/// Phase 1a: which PoToken-free clients give direct MP4 URLs that AVFoundation can range-read.
enum StreamProbe {
    /// Karaoke videos to probe, taken from a live search so the IDs never go stale.
    static func karaokeVideoIDs(api: InnerTubeAPI, query: String = "karaoke songs", count: Int = 10) async throws -> [String] {
        let group = try await api.search(query: query)
        return group.videos
            .filter { !$0.isLive && !$0.isUpcoming && !$0.isShort && ($0.duration ?? 0) > 0 }
            .prefix(count)
            .map(\.id)
    }

    static func run(videoIDs: [String], clients: [StreamClient] = StreamClient.allCases, api: InnerTubeAPI) async -> [ProbeRow] {
        var rows: [ProbeRow] = []
        for videoID in videoIDs {
            for client in clients {
                let row = await probe(videoID: videoID, client: client, api: api)
                Logger.probe.notice("\(row.summary, privacy: .public)")
                rows.append(row)
            }
        }
        return rows
    }

    /// Per client: how many of the probed videos were usable.
    static func summary(_ rows: [ProbeRow]) -> [(client: StreamClient, usable: Int, total: Int)] {
        StreamClient.allCases.compactMap { client in
            let mine = rows.filter { $0.client == client }
            return mine.isEmpty ? nil : (client, mine.filter(\.usable).count, mine.count)
        }
    }

    static func probe(videoID: String, client: StreamClient, api: InnerTubeAPI) async -> ProbeRow {
        var row = ProbeRow(videoID: videoID, client: client)
        do {
            let info = try await client.fetch(api, videoID: videoID)
            row.formatCount = info.formats.count
            row.directCount = info.formats.filter(StreamResolver.isDirect).count
            row.hasHLS = info.hlsURL != nil
            for format in info.formats {
                if let reason = StreamResolver.rejection(format) { row.rejections[reason, default: 0] += 1 }
            }
            guard let pick = StreamResolver.pick(info.formats), let videoURL = pick.video.url else { return row }
            row.pick = pick.description
            row.video = await rangeCheck(videoURL, userAgent: client.userAgent)
            if let audioURL = pick.audio?.url {
                row.audio = await rangeCheck(audioURL, userAgent: client.userAgent)
            }
        } catch {
            row.error = String(describing: error)
        }
        return row
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 3
        return URLSession(configuration: config)
    }()

    static func rangeCheck(_ url: URL, userAgent: String) async -> RangeCheck {
        var request = URLRequest(url: url)
        request.setValue("bytes=0-\(RangeCheck.byteCount - 1)", forHTTPHeaderField: "Range")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let start = ContinuousClock.now
        func elapsed() -> Int {
            let d = ContinuousClock.now - start
            return Int(d.components.seconds * 1000 + d.components.attoseconds / 1_000_000_000_000_000)
        }
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return RangeCheck(status: status, bytes: data.count, millis: elapsed(), error: nil)
        } catch {
            return RangeCheck(status: 0, bytes: 0, millis: elapsed(), error: "\(error.localizedDescription) after \(elapsed())ms")
        }
    }
}
