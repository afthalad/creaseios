import Foundation
import FirebaseAuth
import FirebaseStorage

struct PhotoStorage {
    /// Uploads the signed-in user's photo, or the logo of one of their teams, and returns its download URL.
    func upload(_ jpeg: Data, teamID: String? = nil) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else { throw URLError(.userAuthenticationRequired) }
        let path = teamID.map { "teams/\(uid)/\($0).jpg" } ?? "players/\(uid).jpg"
        let ref = Storage.storage().reference(withPath: path)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(jpeg, metadata: metadata)
        let url = try await ref.downloadURL()
        return "\(url.absoluteString)&v=\(Int(Date.now.timeIntervalSince1970))"
    }
}
