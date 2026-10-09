import FirebaseFunctions

struct Notifier {
    /// Fire and forget: a failed push never blocks the user.
    func notify(_ event: String, _ ids: [String: String]) async {
        var data = ids
        data["event"] = event
        _ = try? await Functions.functions().httpsCallable("notify").call(data)
    }
}
