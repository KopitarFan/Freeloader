import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct FileDragPayload: Codable, Transferable {
    let urls: [URL]

    init(urls: [URL]) {
        self.urls = urls
    }

    init(url: URL) {
        urls = [url]
    }

    var primaryURL: URL {
        urls[0]
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .freeloaderFileSelection)
        ProxyRepresentation(
            exporting: \.primaryURL,
            importing: { FileDragPayload(url: $0) }
        )
    }
}

extension UTType {
    static let freeloaderFileSelection = UTType(
        exportedAs: "net.miguelrodriguez.freeloader.file-selection"
    )
}

struct FavoriteDragPayload: Codable, Transferable {
    let path: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .freeloaderFavorite)
    }
}

extension UTType {
    static let freeloaderFavorite = UTType(
        exportedAs: "net.miguelrodriguez.freeloader.favorite"
    )
}
