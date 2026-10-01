import Foundation
import FirebaseAuth

struct EdgeFunctions {
    let baseURL: URL

    func uploadPhoto(_ jpeg: Data, teamID: String? = nil) async throws -> String {
        var url = baseURL.appending(path: "upload-photo")
        if let teamID { url.append(queryItems: [URLQueryItem(name: "team", value: teamID)]) }
        let data = try await post(url, contentType: "image/jpeg", body: jpeg)
        struct Response: Decodable { let url: String }
        return try JSONDecoder().decode(Response.self, from: data).url
    }

    /// Fire and forget: a failed push never blocks the user.
    func notify(_ event: String, _ ids: [String: String]) async {
        var body = ids
        body["event"] = event
        guard let json = try? JSONEncoder().encode(body) else { return }
        _ = try? await post(baseURL.appending(path: "notify"), contentType: "application/json", body: json)
    }

    private func post(_ url: URL, contentType: String, body: Data) async throws -> Data {
        guard let token = try await Auth.auth().currentUser?.getIDToken() else {
            throw URLError(.userAuthenticationRequired)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}
