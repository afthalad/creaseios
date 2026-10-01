import SwiftUI
import FirebaseFirestore

func searchTokens(_ text: String) -> [String] {
    let full = text.trimmingCharacters(in: .whitespaces).lowercased()
    let words = full.split(whereSeparator: \.isWhitespace).map(String.init)
    var set = Set<String>()
    for word in [full] + words where !word.isEmpty {
        for i in 1...word.count { set.insert(String(word.prefix(i))) }
    }
    return Array(set)
}

/// "Kandy Kings Cricket Club" -> "KKC"
func shortName(_ name: String) -> String {
    name.split(whereSeparator: \.isWhitespace).prefix(3).compactMap(\.first).map(String.init).joined().uppercased()
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension Double {
    var twoDecimals: String { String(format: "%.2f", self) }
    var oneDecimal: String { String(format: "%.1f", self) }
}

extension UIImage {
    /// Keeps uploads well under the 2 MB edge function limit.
    func jpegForUpload(maxSide: CGFloat = 600, quality: CGFloat = 0.8) -> Data? {
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let img = UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        return img.jpegData(compressionQuality: quality)
    }
}

extension Query {
    func stream<T>(_ map: @escaping (QuerySnapshot) throws -> T) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            let reg = addSnapshotListener { snap, error in
                if let error { continuation.finish(throwing: error); return }
                guard let snap else { return }
                do { continuation.yield(try map(snap)) } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in reg.remove() }
        }
    }
}

extension DocumentReference {
    func stream<T>(_ map: @escaping (DocumentSnapshot) throws -> T?) -> AsyncThrowingStream<T?, Error> {
        AsyncThrowingStream { continuation in
            let reg = addSnapshotListener { snap, error in
                if let error { continuation.finish(throwing: error); return }
                guard let snap, snap.exists else { continuation.yield(nil); return }
                do { continuation.yield(try map(snap)) } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in reg.remove() }
        }
    }

    func stream<T: Decodable>(_ type: T.Type) -> AsyncThrowingStream<T?, Error> {
        stream { try $0.data(as: T.self) }
    }
}
