import Foundation
import PomodoroCore

/// Block history as JSON in Application Support. History grows without bound,
/// so it lives in a file rather than in UserDefaults.
struct HistoryStore {
    let url: URL

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = support.appendingPathComponent("PomodoroBar", isDirectory: true)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("history.json")
    }

    func load() -> [BlockRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? Self.decoder.decode([BlockRecord].self, from: data)) ?? []
    }

    func save(_ records: [BlockRecord]) {
        guard let data = try? Self.encoder.encode(records) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
