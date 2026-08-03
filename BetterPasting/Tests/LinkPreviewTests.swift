import Testing
import Foundation
@testable import BetterPasting

// MARK: - Link Detection

@Test func testDetectsPlainURLs() {
    #expect(LinkDetector.url(in: "https://example.com/page")?.host == "example.com")
    #expect(LinkDetector.url(in: "  http://example.com  ")?.host == "example.com")
    #expect(LinkDetector.url(in: "www.example.com/x")?.absoluteString == "https://www.example.com/x")
}

@Test func testIgnoresNonURLText() {
    #expect(LinkDetector.url(in: "check out https://example.com today") == nil)
    #expect(LinkDetector.url(in: "just some copied text") == nil)
    #expect(LinkDetector.url(in: "notes.txt") == nil)
    #expect(LinkDetector.url(in: "ftp://example.com/file") == nil)
    #expect(LinkDetector.url(in: "https://\nexample.com") == nil)
    #expect(LinkDetector.url(in: nil) == nil)
}

@Test func testDetectedURLOnlyForTextItems() {
    let link = ClipboardItem(
        id: UUID(), contentHash: "a", contentType: .text,
        textContent: "https://example.com", sourceBundleID: nil, sourceAppName: nil,
        createdAt: Date(), isPinned: false
    )
    #expect(link.detectedURL != nil)

    let html = ClipboardItem(
        id: UUID(), contentHash: "b", contentType: .html,
        htmlContent: "https://example.com", sourceBundleID: nil, sourceAppName: nil,
        createdAt: Date(), isPinned: false
    )
    #expect(html.detectedURL == nil)
}

// MARK: - Fetch Safety

@Test func testBlocksLocalAndPrivateHosts() {
    #expect(LinkPreviewService.isFetchable(URL(string: "https://example.com")!))
    #expect(!LinkPreviewService.isFetchable(URL(string: "http://localhost:3000/admin")!))
    #expect(!LinkPreviewService.isFetchable(URL(string: "http://192.168.1.10/router")!))
    #expect(!LinkPreviewService.isFetchable(URL(string: "http://10.0.0.4")!))
    #expect(!LinkPreviewService.isFetchable(URL(string: "http://172.20.1.1")!))
    #expect(!LinkPreviewService.isFetchable(URL(string: "http://127.0.0.1:8080")!))
    #expect(!LinkPreviewService.isFetchable(URL(string: "http://mac-mini.local/status")!))
    #expect(LinkPreviewService.isFetchable(URL(string: "http://172.32.1.1")!))  // outside 172.16/12
}

@Test func testNormalizedKeyDropsFragment() {
    let key = LinkPreviewService.normalizedKey(URL(string: "https://example.com/a?b=1#frag")!)
    #expect(key == "https://example.com/a?b=1")
    #expect(LinkPreviewService.normalizedKey(URL(string: "mailto:someone@example.com")!) == nil)
}

// MARK: - HTML Parsing

@Test func testParsesOpenGraphTags() {
    let html = """
        <html><head>
        <title>Fallback title</title>
        <meta property="og:title" content="A great article">
        <meta property="og:description" content="Everything you need to know &amp; more.">
        <meta property="og:site_name" content="Example News">
        <meta property="og:image" content="/img/hero.png">
        <link rel="icon" href="https://cdn.example.com/favicon.ico">
        </head><body>ignored</body></html>
        """

    let meta = HTMLMetadataParser.parse(html: html, baseURL: URL(string: "https://example.com/posts/1")!)
    #expect(meta.title == "A great article")
    #expect(meta.summary == "Everything you need to know & more.")
    #expect(meta.siteName == "Example News")
    #expect(meta.imageURL?.absoluteString == "https://example.com/img/hero.png")
    #expect(meta.faviconURL?.absoluteString == "https://cdn.example.com/favicon.ico")
}

@Test func testFallsBackToTitleTagAndDefaultFavicon() {
    let html = "<html><head><title>  Plain \n page  </title></head><body></body></html>"
    let meta = HTMLMetadataParser.parse(html: html, baseURL: URL(string: "https://example.com/deep/path")!)

    #expect(meta.title == "Plain page")
    #expect(meta.summary == nil)
    #expect(meta.imageURL == nil)
    #expect(meta.faviconURL?.absoluteString == "https://example.com/favicon.ico")
}

@Test func testPrefersTwitterCardWhenNoOpenGraph() {
    let html = """
        <head>
        <meta name="twitter:title" content='Tweet title'>
        <meta name="description" content="Standard description">
        <meta name="twitter:image" content="//cdn.example.com/a.jpg">
        </head>
        """
    let meta = HTMLMetadataParser.parse(html: html, baseURL: URL(string: "https://example.com")!)

    #expect(meta.title == "Tweet title")
    #expect(meta.summary == "Standard description")
    #expect(meta.imageURL?.absoluteString == "https://cdn.example.com/a.jpg")
}

@Test func testSkipsDataURIImages() {
    let html = #"<head><meta property="og:image" content="data:image/png;base64,AAAA"></head>"#
    let meta = HTMLMetadataParser.parse(html: html, baseURL: URL(string: "https://example.com")!)
    #expect(meta.imageURL == nil)
}

@Test func testDecodesEntities() {
    #expect(HTMLMetadataParser.decodeEntities("Tom &amp; Jerry") == "Tom & Jerry")
    #expect(HTMLMetadataParser.decodeEntities("caf&#233;") == "café")
    #expect(HTMLMetadataParser.decodeEntities("&#x2014;dash") == "\u{2014}dash")
    #expect(HTMLMetadataParser.decodeEntities("&#38;amp;") == "&amp;")
    #expect(HTMLMetadataParser.decodeEntities("no entities") == "no entities")
}

// MARK: - Model

@Test func testPreviewFreshnessAndContent() {
    var preview = LinkPreview(url: "https://example.com", title: "Hi")
    #expect(preview.hasContent)
    #expect(!preview.isStale)
    #expect(preview.displayHost == "example.com")

    preview.fetchedAt = Date(timeIntervalSinceNow: -LinkPreview.successTTL - 60)
    #expect(preview.isStale)

    let failed = LinkPreview(url: "https://example.com", fetchedAt: Date(), didFail: true)
    #expect(!failed.hasContent)
    #expect(!failed.isStale)

    let staleFailure = LinkPreview(
        url: "https://example.com",
        fetchedAt: Date(timeIntervalSinceNow: -LinkPreview.failureTTL - 60),
        didFail: true
    )
    #expect(staleFailure.isStale)
    #expect(LinkPreview(url: "https://www.example.com/x").displayHost == "example.com")
}
