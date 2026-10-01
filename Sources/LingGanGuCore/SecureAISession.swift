import Foundation

/// Never forward an authenticated request through an HTTP redirect.
public final class AIRequestBoundary: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    public func urlSession(_ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    public static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        return configuration
    }

    public static func makeSession() -> URLSession {
        URLSession(configuration: configuration(), delegate: AIRequestBoundary(), delegateQueue: nil)
    }
}
