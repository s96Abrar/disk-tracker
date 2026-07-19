//
//  ExportService.swift
//  DiskTracker
//
//  Phase 5: JSON + CSV export of scan results.
//

import Foundation

enum ExportService {

    static func exportJSON(root: DiskNode) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let node = SerializableNode.from(root)
        guard let data = try? encoder.encode(node),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    static func exportCSV(root: DiskNode) -> String {
        var lines: [String] = ["Path,Name,PhysicalSize,LogicalSize,Kind,ModDate"]
        appendCSV(from: root, into: &lines)
        return lines.joined(separator: "\n")
    }

    private static func appendCSV(from node: DiskNode, into lines: inout [String]) {
        if node.fileKind != .directory {
            let isoDate = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(node.modTimeSecs)))
            let row = [
                csvEscape(node.path),
                csvEscape(node.name),
                "\(node.physicalSize)",
                "\(node.logicalSize)",
                csvEscape(fileKindLabel(node.fileKind)),
                isoDate,
            ].joined(separator: ",")
            lines.append(row)
        }
        node.children?.forEach { appendCSV(from: $0, into: &lines) }
    }

    private static func fileKindLabel(_ kind: FileKind) -> String {
        switch kind {
        case .image:       return "Image"
        case .video:       return "Video"
        case .audio:       return "Audio"
        case .document:    return "Document"
        case .archive:     return "Archive"
        case .application: return "Application"
        case .directory:   return "Directory"
        case .other:       return "Other"
        }
    }

    private static func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return s
    }

    private struct SerializableNode: Codable {
        let name: String
        let path: String
        let physicalSize: UInt64
        let logicalSize: UInt64
        let kind: String
        let modDate: String
        let children: [SerializableNode]?

        static func from(_ node: DiskNode) -> SerializableNode {
            SerializableNode(
                name: node.name,
                path: node.path,
                physicalSize: node.physicalSize,
                logicalSize: node.logicalSize,
                kind: fileKindLabel(node.fileKind),
                modDate: ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(node.modTimeSecs))),
                children: node.children?.map { from($0) }
            )
        }
    }
}