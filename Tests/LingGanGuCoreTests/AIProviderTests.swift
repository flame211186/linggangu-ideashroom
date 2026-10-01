import Foundation
import XCTest
@testable import LingGanGuCore

final class AIProviderTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testConnectionUsesNormalizedURLNewTokenParameterAndBearerKey() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://example.com/v1/chat/completions"
            )
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer secret-value"
            )
            let body = try requestBody(request)
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            XCTAssertNotNil(object["max_completion_tokens"])
            XCTAssertNil(object["max_tokens"])
            return Self.response(
                request: request,
                status: 200,
                body: #"{"choices":[{"message":{"content":"OK"}}]}"#
            )
        }

        let provider = try makeProvider(
            baseURL: "https://example.com/v1",
            key: "secret-value"
        )
        try await provider.testConnection()
    }

    func testLocalProviderAllowsEmptyKeyAndOmitsAuthorization() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return Self.response(
                request: request,
                status: 200,
                body: #"{"choices":[{"message":{"content":"OK"}}]}"#
            )
        }
        let provider = try makeProvider(
            baseURL: "http://127.0.0.1:11434",
            key: ""
        )
        try await provider.testConnection()
    }

    func testStructuredOutputFallsBackToPromptJSON() async throws {
        var requestCount = 0
        StubURLProtocol.handler = { request in
            requestCount += 1
            let body = try requestBody(request)
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            if object["response_format"] != nil {
                return Self.response(
                    request: request,
                    status: 400,
                    body: #"{"error":{"message":"response_format unsupported"}}"#
                )
            }
            return Self.response(
                request: request,
                status: 200,
                body: #"{"choices":[{"message":{"content":"{\"title\":\"标题\",\"tags\":[\"建议\"],\"topic\":\"主题\"}"}}]}"#
            )
        }
        let provider = try makeProvider(baseURL: "https://example.com", key: "key")
        let annotation = try await provider.annotate(idea: Idea(rawText: "原始想法"))
        XCTAssertEqual(annotation.title, "标题")
        XCTAssertEqual(annotation.tags, ["建议"])
        XCTAssertEqual(requestCount, 3)
    }

    func testLegacyTokenFallback() async throws {
        var requestCount = 0
        StubURLProtocol.handler = { request in
            requestCount += 1
            let body = try requestBody(request)
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            if object["max_completion_tokens"] != nil {
                return Self.response(
                    request: request,
                    status: 400,
                    body: #"{"error":{"message":"unknown max_completion_tokens"}}"#
                )
            }
            XCTAssertNotNil(object["max_tokens"])
            return Self.response(
                request: request,
                status: 200,
                body: #"{"choices":[{"message":{"content":"OK"}}]}"#
            )
        }
        let provider = try makeProvider(baseURL: "https://example.com", key: "key")
        try await provider.testConnection()
        XCTAssertEqual(requestCount, 2)
    }

    func testStreamingSSEProducesChunks() async throws {
        StubURLProtocol.handler = { request in
            let body = """
            data: {"choices":[{"delta":{"content":"第一"}}]}

            data: {"choices":[{"delta":{"content":"第二"}}]}

            data: [DONE]

            """
            return Self.response(
                request: request,
                status: 200,
                body: body,
                contentType: "text/event-stream"
            )
        }
        let provider = try makeProvider(baseURL: "https://example.com", key: "key")
        var output = ""
        for try await chunk in provider.chatStream(
            turns: [AIChatTurn(role: .user, content: "测试")],
            ideas: [Idea(rawText: "测试灵感")]
        ) {
            output += chunk
        }
        XCTAssertEqual(output, "第一第二")
    }

    private func makeProvider(
        baseURL: String,
        key: String
    ) throws -> OpenAICompatibleProvider {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return try OpenAICompatibleProvider(
            configuration: AIProviderConfiguration(
                baseURL: try XCTUnwrap(URL(string: baseURL)),
                model: "test-model"
            ),
            apiKey: key,
            session: URLSession(configuration: configuration),
            maximumRetries: 0
        )
    }

    private static func response(
        request: URLRequest,
        status: Int,
        body: String,
        contentType: String = "application/json"
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": contentType]
            )!,
            Data(body.utf8)
        )
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler:
        ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw URLError(.badServerResponse)
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func requestBody(_ request: URLRequest) throws -> Data {
    if let data = request.httpBody { return data }
    let stream = try XCTUnwrap(request.httpBodyStream)
    stream.open()
    defer { stream.close() }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count == 0 { return result }
        if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
        result.append(contentsOf: buffer.prefix(count))
    }
}
