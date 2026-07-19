import Foundation
import os.log
import Security

// MARK: - Protocol

/// NSXPC protocol exposed by the privileged helper tool.
/// The main app (com.disktracker.app) calls these methods; the helper runs as root.
@objc protocol DiskTrackerHelperProtocol {
    /// List APFS Time Machine local snapshots for a volume path.
    func listAPFSSnapshots(forPath: String, withReply: @escaping ([[String: Any]]?, Error?) -> Void)

    /// Delete a snapshot by its display name / date token.
    func deleteAPFSSnapshot(named: String, forPath: String, withReply: @escaping (Bool, Error?) -> Void)

    /// Delete a file that the sandboxed app cannot remove (SIP-protected dirs, TCC, etc.).
    func deleteProtectedFile(at path: String, withReply: @escaping (Bool, Error?) -> Void)

    /// Recursively scan a directory the sandboxed app cannot read (e.g. /System/Volumes/Data/private).
    /// Returns a bounded array of file metadata dictionaries.
    func scanDirectory(at path: String, withReply: @escaping ([[String: Any]]?, Error?) -> Void)
}

// MARK: - Helper Implementation

@objc final class DiskTrackerHelper: NSObject, DiskTrackerHelperProtocol {
    private let log = OSLog(subsystem: "com.disktracker.helper", category: "helper")
    private let snapshotManager = APFSSnapshotManager()

    // MARK: - DiskTrackerHelperProtocol

    func listAPFSSnapshots(forPath: String, withReply: @escaping ([[String: Any]]?, Error?) -> Void) {
        os_log("Listing APFS snapshots for %{public}@", log: log, type: .info, forPath)

        do {
            let snapshots = try snapshotManager.listSnapshots(forPath: forPath)
            os_log("Found %{public}d snapshots", log: log, type: .info, snapshots.count)
            withReply(snapshots, nil)
        } catch {
            os_log("List snapshots failed: %{public}@", log: log, type: .error, error.localizedDescription)
            withReply(nil, error)
        }
    }

    func deleteAPFSSnapshot(named: String, forPath: String, withReply: @escaping (Bool, Error?) -> Void) {
        os_log("Deleting snapshot %{public}@ on %{public}@", log: log, type: .info, named, forPath)

        do {
            try snapshotManager.deleteSnapshot(named: named, forPath: forPath)
            os_log("Snapshot deleted", log: log, type: .info)
            withReply(true, nil)
        } catch {
            os_log("Delete snapshot failed: %{public}@", log: log, type: .error, error.localizedDescription)
            withReply(false, error)
        }
    }

    func deleteProtectedFile(at path: String, withReply: @escaping (Bool, Error?) -> Void) {
        os_log("Deleting protected file at %{public}@", log: log, type: .info, path)

        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            withReply(false, NSError(domain: "com.disktracker.helper", code: 404,
                userInfo: [NSLocalizedDescriptionKey: "File does not exist"]))
            return
        }

        do {
            try fm.removeItem(atPath: path)
            os_log("Deleted %{public}@", log: log, type: .info, path)
            withReply(true, nil)
        } catch {
            os_log("Delete failed: %{public}@", log: log, type: .error, error.localizedDescription)
            withReply(false, error)
        }
    }

    func scanDirectory(at path: String, withReply: @escaping ([[String: Any]]?, Error?) -> Void) {
        os_log("Deep scanning %{public}@", log: log, type: .info, path)

        let fm = FileManager.default
        var results: [[String: Any]] = []
        let maxResults = 50_000  // Guard against XPC message-size limits

        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [
                .fileSizeKey,
                .isDirectoryKey,
                .contentModificationDateKey,
                .isPackageKey,
            ],
            options: [.producesRelativePathURLs],
            errorHandler: { url, err -> Bool in
                os_log("Enumerator error at %{public}@: %{public}@",
                       log: self.log, type: .debug, url.path, err.localizedDescription)
                return true  // Continue enumeration
            }
        ) else {
            withReply(nil, NSError(domain: "com.disktracker.helper", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot access directory: \(path)"]))
            return
        }

        for case let fileURL as URL in enumerator {
            do {
                let values = try fileURL.resourceValues(forKeys: [
                    .fileSizeKey, .isDirectoryKey, .contentModificationDateKey, .isPackageKey,
                ])

                results.append([
                    "path": fileURL.path,
                    "size": values.fileSize ?? 0,
                    "isDirectory": values.isDirectory ?? false,
                    "isPackage": values.isPackage ?? false,
                    "modificationDate": (values.contentModificationDate ?? Date.distantPast).timeIntervalSince1970,
                ])

                if results.count >= maxResults {
                    os_log("Reached result limit; truncating", log: log, type: .info)
                    break
                }
            } catch {
                os_log("Skipping %{public}@: %{public}@",
                       log: self.log, type: .debug, fileURL.path, error.localizedDescription)
            }
        }

        os_log("Scanned %{public}d items", log: log, type: .info, results.count)
        withReply(results, nil)
    }
}

// MARK: - XPC Listener Delegate

extension DiskTrackerHelper: NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let pid = newConnection.processIdentifier
        os_log("Connection attempt from pid %{public}d", log: log, type: .info, pid)

        // Verify the connecting client's code signature matches our authorized client requirement.
        guard verifyClient(pid: pid) else {
            os_log("Code-signature verification failed for pid %{public}d", log: log, type: .error, pid)
            return false
        }

        let interface = NSXPCInterface(with: DiskTrackerHelperProtocol.self)
        newConnection.exportedInterface = interface
        newConnection.exportedObject = self

        newConnection.invalidationHandler = { [weak self] in
            guard let self = self else { return }
            os_log("Connection invalidated (pid %{public}d)", log: self.log, type: .info, pid)
        }
        newConnection.interruptionHandler = { [weak self] in
            guard let self = self else { return }
            os_log("Connection interrupted (pid %{public}d)", log: self.log, type: .info, pid)
        }

        newConnection.resume()
        os_log("Accepted connection from pid %{public}d", log: log, type: .info, pid)
        return true
    }

    // MARK: - Code-signature verification

    /// Validates the connecting process against the SMAuthorizedClients requirement.
    private func verifyClient(pid: pid_t) -> Bool {
        let requirementString = "identifier \"com.disktracker.app\" and anchor apple generic"

        var code: SecCode?
        let attrs: [String: Any] = [kSecGuestAttributePid as String: Int32(pid)]
        var status = SecCodeCopyGuestWithAttributes(nil, attrs as CFDictionary, [], &code)
        guard status == errSecSuccess, let code = code else {
            os_log("SecCodeCopyGuestWithAttributes failed: %{public}d", log: log, type: .error, Int32(status))
            return false
        }

        var requirement: SecRequirement?
        status = SecRequirementCreateWithString(requirementString as CFString, [], &requirement)
        guard status == errSecSuccess, let requirement = requirement else {
            os_log("SecRequirementCreateWithString failed", log: log, type: .error)
            return false
        }

        status = SecCodeCheckValidity(code, [], requirement)
        guard status == errSecSuccess else {
            os_log("SecCodeCheckValidity failed: %{public}d", log: log, type: .error, Int32(status))
            return false
        }

        return true
    }
}

// MARK: - Entry Point

let helper = DiskTrackerHelper()
let listener = NSXPCListener(machServiceName: "com.disktracker.helper")
listener.delegate = helper
listener.resume()

os_log("DiskTracker helper started – listening on com.disktracker.helper", log: helper.log, type: .info)

// Keep the daemon alive. RunLoop cannot exit.
RunLoop.current.run()
