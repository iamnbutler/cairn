import CairnFrame
import CairnRender
import Foundation

/// `loadImage` (^1006): reads a file or fetches an http(s) URL, decodes it with ImageIO, keeps it
/// in an `ImageStore` for `image` draws naming the same source, and answers its pixel size.
///
/// A source starting `http://` or `https://` is fetched; anything else is a path (`~/` is home,
/// a relative path is from the working directory). Without `reload` a source already in the store
/// is answered from it without reading. A reload that fails removes the source, so the app's
/// failed state and the host's pixels agree. A cancelled load (`cancelRequest`, ^1009) stops its
/// download, leaves the store alone and answers `failed`.
public enum ImageLoad {
    /// The most bytes read or downloaded for one image.
    public static let maxBytes = 64 << 20
    public static let timeoutSeconds: Double = 30

    public static func isURL(_ source: String) -> Bool {
        let s = source.lowercased()
        return s.hasPrefix("http://") || s.hasPrefix("https://")
    }

    public static func run(source: String, reload: Bool, store: ImageStore, session: URLSession,
                           _ reply: @escaping @Sendable (Reply) -> Void) {
        if source.isEmpty { reply(.failed(.invalid, "empty source")); return }
        if source.utf8.contains(0) { reply(.failed(.invalid, "NUL in source")); return }
        if !reload, let e = store.entry(source) { reply(size(e.width, e.height)); return }
        let token = Cancellation.current
        let finish: @Sendable (Data?, Reply?) -> Void = { data, failure in
            if token?.isCancelled == true { reply(.failed(.other, "cancelled")); return }
            if let failure {
                if reload { store.remove(source) }
                reply(failure)
                return
            }
            guard let data, let d = ImageStore.decode(data) else {
                if reload { store.remove(source) }
                reply(.failed(.invalid, "not an image: \(source)"))
                return
            }
            store.put(source, d)
            reply(size(d.width, d.height))
        }
        if isURL(source) {
            fetch(source, session: session, finish)
        } else {
            let url = URL(fileURLWithPath: Files.expand(source))
            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                if (attrs[.type] as? FileAttributeType) == .typeDirectory {
                    finish(nil, .failed(.invalid, "a directory: \(source)")); return
                }
                if let n = attrs[.size] as? Int, n > maxBytes {
                    finish(nil, .failed(.invalid, "image too large: \(source)")); return
                }
                finish(try Data(contentsOf: url, options: .mappedIfSafe), nil)
            } catch {
                finish(nil, Files.fault(error))
            }
        }
    }

    static func size(_ w: Int, _ h: Int) -> Reply {
        .image(width: UInt32(clamping: w), height: UInt32(clamping: h))
    }

    /// HTTP 404 and 410 are not found, 401 and 403 denied, any other status outside 2xx other.
    static func fetch(_ source: String, session: URLSession,
                      _ finish: @escaping @Sendable (Data?, Reply?) -> Void) {
        guard let u = URL(string: source), u.host != nil else {
            finish(nil, .failed(.invalid, "not an http(s) URL: \(source)")); return
        }
        var req = URLRequest(url: u)
        req.timeoutInterval = timeoutSeconds
        let task = session.dataTask(with: req) { data, response, error in
            if let error {
                let e = error as NSError
                let f: Fault = switch (e.domain, e.code) {
                case (NSURLErrorDomain, NSURLErrorTimedOut): .timeout
                case (NSURLErrorDomain, NSURLErrorBadURL), (NSURLErrorDomain, NSURLErrorUnsupportedURL): .invalid
                case (NSURLErrorDomain, _): .network
                default: .other
                }
                finish(nil, .failed(f, e.localizedDescription)); return
            }
            guard let http = response as? HTTPURLResponse else {
                finish(nil, .failed(.other, "not an HTTP response")); return
            }
            switch http.statusCode {
            case 200..<300: break
            case 404, 410: finish(nil, .failed(.notFound, "HTTP \(http.statusCode)")); return
            case 401, 403: finish(nil, .failed(.denied, "HTTP \(http.statusCode)")); return
            default: finish(nil, .failed(.other, "HTTP \(http.statusCode)")); return
            }
            guard let data, data.count <= maxBytes else {
                finish(nil, .failed(.invalid, "image too large: \(source)")); return
            }
            finish(data, nil)
        }
        Cancellation.current?.onCancel { task.cancel() }
        task.resume()
    }
}
