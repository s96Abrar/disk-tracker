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

    /// Default size threshold (100 MB) above which `.app` bundles are surfaced in smart filters.
    static let defaultThreshold: UInt64 = 100_000_000

    /// Find .app bundles at or above the threshold. Pass a custom threshold to test lower bounds.
    static func findLargeBundles(
        in root: DiskNode,
        config: SmartFilterConfig,
        threshold: UInt64 = defaultThreshold
    ) -> [SmartFilterResult] {
        var results: [SmartFilterResult] = []
        findBundles(node: root, config: config, threshold: threshold, into: &results)
        return results.sorted { $0.node.physicalSize > $1.node.physicalSize }
    }

    /// Full structured breakdown for a single .app path.
    static func analyzeBundle(_ bundle: DiskNode) -> AppBundleBreakdown {
        let base = URL(fileURLWithPath: bundle.path)
        let fm = FileManager.default

        // ponytail: 3 sibling directories share the same size-summing shape; the
        // helper keeps sizes summing separate from per-item capture (Frameworks).
        let execSize       = sumChildren(of: base.appendingPathComponent("Contents/MacOS"),     fm: fm)
        let frameworkPairs: [(String, UInt64)] = sizedChildren(
            of: base.appendingPathComponent("Contents/Frameworks"), fm: fm,
            name: { $0.lastPathComponent })
        let pluginSize     = sumChildren(of: base.appendingPathComponent("Contents/PlugIns"),    fm: fm)

        // Resources (Contents/Resources) — iterate recursively via DiskNode children
        let resDir = base.appendingPathComponent("Contents/Resources").path
        let resourceSize: UInt64 = (bundle.children ?? [])
            .filter { $0.path.hasPrefix(resDir) }
            .reduce(0) { $0 + $1.physicalSize }

        let frameworkTotal = frameworkPairs.reduce(UInt64(0)) { $0 + $1.1 }
        let otherSize = bundle.physicalSize - execSize - frameworkTotal - resourceSize - pluginSize

        return AppBundleBreakdown(
            path: bundle.path,
            totalSize: bundle.physicalSize,
            executableSize: execSize,
            frameworkSizes: frameworkPairs.map { (name: $0.0, size: $0.1) },
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

    // MARK: - Bundle I/O Helpers

    /// Total byte size of every regular child under `dir`. Returns 0 if missing/unreadable.
    private static func sumChildren(of dir: URL, fm: FileManager) -> UInt64 {
        sizedChildren(of: dir, fm: fm, name: { _ in "" }).reduce(0) { $0 + $1.1 }
    }

    /// `(name, size)` pairs for every regular child of `dir`. Empty on missing dir.
    private static func sizedChildren(
        of dir: URL,
        fm: FileManager,
        name: (URL) -> String
    ) -> [(String, UInt64)] {
        guard let urls = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return [] }
        return urls.map { url in
            let attrs = try? url.resourceValues(forKeys: [.fileSizeKey])
            return (name(url), UInt64(attrs?.fileSize ?? 0))
        }
    }
}