import Foundation

struct Usage: Decodable {
    let used: Int
    let limit: Int
    let plan: String
}

struct RewriteRequest {
    let mode: Mode
    let language: String
    let transaction: String?
}

struct RewriteError: Error {
    let message: String
    var usage: Usage?
}

enum API {
    static let website = URL(string: "https://textfix.puteanihollakos.com")!

    static var baseURL: URL {
        UserDefaults.standard.string(forKey: "apiURL").flatMap(URL.init(string:)) ?? website
    }

    static var installId: String {
        if let id = UserDefaults.standard.string(forKey: "installId") { return id }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: "installId")
        return id
    }

    private struct Response: Decodable {
        let text: String?
        let error: String?
        let used: Int?
        let limit: Int?
        let plan: String?

        var usage: Usage? {
            guard let used, let limit, let plan else { return nil }
            return Usage(used: used, limit: limit, plan: plan)
        }
    }

    static func rewrite(_ text: String, _ request: RewriteRequest) -> Result<(String, Usage?), RewriteError> {
        var urlRequest = makeRequest("api/rewrite", transaction: request.transaction)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try? JSONEncoder().encode([
            "mode": request.mode.argument,
            "text": text,
            "targetLanguage": request.language,
        ])

        guard let (data, status) = send(urlRequest) else {
            return .failure(RewriteError(message: "Could not reach TextFix. Please check your internet connection."))
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            return .failure(RewriteError(message: "TextFix returned an invalid response (\(status))."))
        }
        guard status == 200, let output = response.text else {
            return .failure(RewriteError(message: response.error ?? "TextFix failed.", usage: response.usage))
        }
        return .success((output, response.usage))
    }

    static func usage(transaction: String?) async -> Usage? {
        let request = makeRequest("api/usage", transaction: transaction)
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return try? JSONDecoder().decode(Usage.self, from: data)
    }

    private static func makeRequest(_ path: String, transaction: String?) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: 30)
        request.setValue(installId, forHTTPHeaderField: "X-Install-Id")
        if let transaction { request.setValue(transaction, forHTTPHeaderField: "X-Transaction") }
        return request
    }

    private static func send(_ request: URLRequest) -> (Data, Int)? {
        var result: (Data, Int)?
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let data, let http = response as? HTTPURLResponse { result = (data, http.statusCode) }
            done.signal()
        }.resume()
        done.wait()
        return result
    }
}
