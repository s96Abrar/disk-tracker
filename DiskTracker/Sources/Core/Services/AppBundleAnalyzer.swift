//
//  AppBundleAnalyzer.swift
//  DiskTracker
//
//  Phase 5: .app bundle content breakdown — executable, frameworks, resources.
//

import Foundation

// MARK: - Bundle Breakdown

struct AppBundleBreakdown: Identifiable, Sendable {
    let id = UUID()
    let path: String
    let totalSize: UInt64
    let executableSize: UInt64
    let frameworkSizes: [(name: String, size: UInt64)]
    let resourceSize: UInt64
    let pluginSize: UInt64
    let otherSize: UInt64

    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

// MARK: - App Bundle Analyzer

enum AppBundleAnalyzer {

    /// Find .app bundles >= 100 MB and break them down.
    /// Returns results as SmartFilterResult so they render in the Phase 4/5 results view.
    static func findLargeBundles(
        in root: DiskNode,
        config: SmartFilterConfig
    ) -> [SmartFilterResult] {
        let threshold: UInt64 = 100_000_000  // 100 MB
        var results: [SmartFilterResult] = []
        findBundles(node: root, config: config, threshold: threshold, into: &results)
        return results.sorted { $0.node.physicalSize > $1.node.physicalSize }
    }

    /// Full structured breakdown for a single .app path.
    static func analyzeBundle(_ bundle: DiskNode) -> AppBundleBreakdown {
        let path = bundle.path
        var execSize: UInt64 = 0
        var frameworks: [(name: String, size: UInt64)] = []
        var resourceSize: UInt64 = 0
        var pluginSize: UInt64 = 0
        var otherSize: UInt64 = 0

        let fm = FileManager.default
        let base = URL(fileURLWithPath: path)

        // Executable — look inside Contents/MacOS
        let macosDir = base.appendingPathComponent("Contents/MacOS")
        if let macosChildren = try? fm.contentsOfDirectory(at: macosDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for child in macosChildren {
                let attrs = try? child.resourceValues(forKeys: [.fileSizeKey])
                execSize += UInt64(attrs?.fileSize ?? 0)
            }
        }

        // Frameworks
        let fwDir = base.appendingPathComponent("Contents/Frameworks")
        if let fwChildren = try? fm.contentsOfDirectory(at: fwDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for child in fwChildren {
                let attrs = try? child.resourceValues(forKeys: [.fileSizeKey])
                let size = UInt64(attrs?.fileSize ?? 0)
                frameworks.append((child.lastPathComponent, size))
            }
        }

        // PlugIns
        let plugDir = base.appendingPathComponent("Contents/PlugIns")
        if let plugChildren = try? fm.contentsOfDirectory(at: plugDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for child in plugChildren {
                let attrs = try? child.resourceValues(forKeys: [.fileSizeKey])
                pluginSize += UInt64(attrs?.fileSize ?? 0)
            }
        }

        // Resources (Contents/Resources) — iterate recursively via DiskNode children
        let resDir = base.appendingPathComponent("Contents/Resources")
        bundle.children?.forEach { child in
            if child.path.hasPrefix(resDir.path) {
                resourceSize += child.physicalSize
            }
        }

        otherSize = bundle.physicalSize - execSize - frameworks.reduce(0, { $0 + $1.size }) - resourceSize - pluginSize

        return AppBundleBreakdown(
            path: path,
            totalSize: bundle.physicalSize,
            executableSize: execSize,
            frameworkSizes: frameworks,
            resourceSize: resourceSize,
            pluginSize: pluginSize,
            otherSize: otherSize
        )
    }

    // MARK: - Tree Walk

    private static func findBundles(
        node: DiskNode,
        config: SmartFilterConfig,
        threshold: UInt64,
        into results: inout [SmartFilterResult]
    ) {
        if !config.includeHiddenFiles && node.name.hasPrefix(".") { return }
        if !config.includeSystemPaths && node.isSystemProtected { return }

        if node.name.hasSuffix(".app"),
           node.fileKind == .directory,
           node.physicalSize >= threshold {
            results.append(SmartFilterResult(
                node: node,
                matchedAt: Date(),
                matchReason: .duplicate // ponytail: reuse MatchReason; may add .appBundle later
            ))
        }

        node.children?.forEach { findBundles(node: $0, config: config, threshold: threshold, into: &results) }
    }
}