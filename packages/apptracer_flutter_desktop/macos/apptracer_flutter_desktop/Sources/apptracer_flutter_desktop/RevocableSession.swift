import Foundation

/// The SDK still builds its own envelopes/HTTP requests. This session-local
/// protocol only gates network admission and forwards those requests unchanged.
/// Its front session stays valid: a delayed SDK operation after close must get
/// cancellation, not Foundation's "task created in an invalidated session" crash.
final class RevocableSession: NSObject, URLSessionDelegate {
    static let shared = RevocableSession()
    private let lock = NSLock()
    private var network: URLSession?
    private var allowed = false
    private var invalidated: ((Error?) -> Void)?
    private(set) var sdkSession: URLSession?

    func open() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        lock.lock()
        network = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        allowed = true
        lock.unlock()
        configuration.protocolClasses = [RevocableProtocol.self]
        sdkSession = URLSession(configuration: configuration)
    }

    func request(_ request: URLRequest,
                 completion: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask? {
        lock.lock(); defer { lock.unlock() }
        guard allowed, let network = network else { return nil }
        let task = network.dataTask(with: request, completionHandler: completion)
        task.resume()
        return task
    }

    func revoke(completion: @escaping (Error?) -> Void) {
        lock.lock()
        allowed = false
        invalidated = completion
        let session = network
        lock.unlock()
        if let session = session { session.invalidateAndCancel() }
        else { DispatchQueue.main.async { completion(nil) } }
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        lock.lock()
        network = nil
        let completion = invalidated
        invalidated = nil
        lock.unlock()
        DispatchQueue.main.async { completion?(error) }
    }
}

private final class RevocableProtocol: URLProtocol {
    private let lock = NSLock()
    private var forwardingTask: URLSessionDataTask?
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        forwardingTask = RevocableSession.shared.request(request) { [weak self] data, response, error in
            guard let self = self else { return }
            self.lock.lock()
            let stopped = self.stopped
            self.lock.unlock()
            guard !stopped else { return }
            if let error = error { self.client?.urlProtocol(self, didFailWithError: error); return }
            if let response = response {
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            if let data = data { self.client?.urlProtocol(self, didLoad: data) }
            self.client?.urlProtocolDidFinishLoading(self)
        }
        let rejected = forwardingTask == nil
        lock.unlock()
        if rejected { client?.urlProtocol(self, didFailWithError: URLError(.cancelled)) }
    }

    override func stopLoading() {
        lock.lock()
        stopped = true
        forwardingTask?.cancel()
        forwardingTask = nil
        lock.unlock()
    }
}
