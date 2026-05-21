import Foundation
import SwiftUI
import SwiftData

@Model
final class EvidenceAsset: Identifiable {
    @Attribute(.unique) var id: UUID
    var fileHash: String
    var fileSize: String
    var deviceModel: String
    var dateTaken: String
    var dateSaved: String
    var isVideo: Bool
    var relativeFilePath: String
    var relativeThumbPath: String
    
    @Transient var thumbnail: UIImage {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fullPath = docs.appendingPathComponent(relativeThumbPath)
        return UIImage(contentsOfFile: fullPath.path) ?? UIImage(systemName: "photo")!
    }
    
    var localURL: URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fullPath = docs.appendingPathComponent(relativeFilePath)
        return FileManager.default.fileExists(atPath: fullPath.path) ? fullPath : nil
    }

    init(id: UUID = UUID(), fileHash: String, fileSize: String, deviceModel: String, dateTaken: String, dateSaved: String, isVideo: Bool, relativeFilePath: String, relativeThumbPath: String) {
        self.id = id
        self.fileHash = fileHash
        self.fileSize = fileSize
        self.deviceModel = deviceModel
        self.dateTaken = dateTaken
        self.dateSaved = dateSaved
        self.isVideo = isVideo
        self.relativeFilePath = relativeFilePath
        self.relativeThumbPath = relativeThumbPath
    }
}

@Model
final class GeneratedReport: Identifiable {
    @Attribute(.unique) var id: UUID
    var timestamp: String
    var itemsCount: Int
    var locationContext: String
    var relativePayloadPaths: [String]
    
    var payloadPackageURLs: [URL] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return relativePayloadPaths.map { docs.appendingPathComponent($0) }
    }

    init(id: UUID = UUID(), timestamp: String, itemsCount: Int, locationContext: String, relativePayloadPaths: [String]) {
        self.id = id
        self.timestamp = timestamp
        self.itemsCount = itemsCount
        self.locationContext = locationContext
        self.relativePayloadPaths = relativePayloadPaths
    }
}
