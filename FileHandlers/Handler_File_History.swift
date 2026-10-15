import Foundation

final class Handler_File_History: Handler_File_JSON {
    init() {
        super.init(FileDescriptor(name: "History", extensions: ["colhis", "colhistory"], format: "colour-history", versions: [2])) { data in
            let document = try ColourFiles.decoder().decode(HistoryStore.File.self, from: data)
            guard document.current >= -1, document.current < document.steps.count || document.steps.isEmpty && document.current == -1 else { throw failure("Invalid history position.") }
            return try Handler_File_JSON.codec(HistoryStore.File.self, data, libraryDates: true)
        }
    }
}
