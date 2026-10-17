import Testing
@testable import KaraPitchTV

/// Ported from the Android app's `YouTubeUrlsTest.kt`.
struct YouTubeURLTests {
    private static let canonical = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"

    @Test(arguments: [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://youtube.com/watch?feature=share&v=dQw4w9WgXcQ&t=42",
        "https://m.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://music.youtube.com/watch?v=dQw4w9WgXcQ&list=RD",
        "https://youtu.be/dQw4w9WgXcQ?si=abc",
        "youtu.be/dQw4w9WgXcQ",
        "https://www.youtube.com/shorts/dQw4w9WgXcQ",
        "https://www.youtube.com/live/dQw4w9WgXcQ",
        "https://www.youtube.com/embed/dQw4w9WgXcQ",
        "  https://youtu.be/dQw4w9WgXcQ  ",
    ])
    func acceptsCommonForms(_ input: String) {
        #expect(YouTubeURL.normalize(input) == Self.canonical)
    }

    @Test(arguments: [
        "",
        "hello",
        "https://vimeo.com/123456",
        "https://www.youtube.com/watch?v=short",
        "https://www.youtube.com/channel/UCabcdefghijk",
        "https://evil.com/watch?v=dQw4w9WgXcQ",
        "https://www.youtube.com/playlist?list=PL123",
    ])
    func rejectsOthers(_ input: String) {
        #expect(YouTubeURL.normalize(input) == nil)
    }

    @Test func videoIDOfCanonical() {
        #expect(YouTubeURL.videoID(of: Self.canonical) == "dQw4w9WgXcQ")
    }
}
