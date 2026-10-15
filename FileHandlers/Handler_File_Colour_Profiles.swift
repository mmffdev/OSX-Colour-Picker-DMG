import Foundation

final class Handler_File_Colour_Profiles: Handler_File_JSON {
    init() {
        super.init(FileDescriptor(name: "Colour Profiles", extensions: ["colprf"], format: "colour-profiles", versions: [1])) { data in
            return try Handler_File_JSON.codec(ProfilesDocument.self, data, libraryDates: true)
        }
    }
}
