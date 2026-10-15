import Foundation

final class Handler_File_Proof: Handler_File_JSON {
    init() {
        super.init(FileDescriptor(name: "Proof Configuration", extensions: ["colcal"], format: nil, versions: [1])) { data in
            try JSONDecoder().decode(ProofConfiguration.self, from: data).validate()

            return try Handler_File_JSON.codec(ProofConfiguration.self, data, libraryDates: false)
        }
    }
}
