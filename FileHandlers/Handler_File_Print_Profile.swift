import Foundation

final class Handler_File_Print_Profile: Handler_File_JSON {
    init() {
        super.init(FileDescriptor(name: "Print Profile", extensions: ["colpro"], format: "colorgain.print-profile", versions: [1])) { data in
            try JSONDecoder().decode(SavedPrintProfiles.Exchange.self, from: data).profile.validate()

            return try Handler_File_JSON.codec(SavedPrintProfiles.Exchange.self, data, libraryDates: false)
        }
    }
}
