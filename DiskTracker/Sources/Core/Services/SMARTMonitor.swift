//
//  SMARTMonitor.swift
//  DiskTracker
//
//  Phase 7: S.M.A.R.T. monitoring via smartctl.
//
//  NOT BUILT IN v0.1 — gated behind `DISKTRACKER_V05`.
//
//  No build configuration defines that condition, so this file compiles to
//  nothing today. It is kept rather than deleted because it works and is
//  tested; it is the starting point for the phase named above, tracked in
//  `documents/5_FUTURE_TARGETS.md` §3.
//
//  To build it, add to the DiskTracker target's build settings:
//      SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) DISKTRACKER_V05
//
//  `./build-disk-tracker --v05` does exactly that, and is run in CI so this
//  code cannot rot into something that no longer compiles.
//

#if DISKTRACKER_V05

import Foundation

/// S.M.A.R.T. status for a disk.
struct SMARTStatus: Identifiable, Sendable {
    let id = UUID()
    let devicePath: String
    let model: String
    let serial: String?
    let isHealthy: Bool
    let temperature: Int?
    let powerOnHours: Int?
    let reallocatedSectors: Int?
    let currentPendingSectors: Int?
    let unisksReadErrors: Int?
    let unisksWriteErrors: Int?
    let rawOutput: String

    var healthDescription: String {
        isHealthy ? "Healthy" : "Warning/Failing"
    }
}

/// Monitors disk S.M.A.R.T. data via smartctl.
enum SMARTMonitor {

    /// List available disks with S.M.A.R.T. support.
    static func listDisks() async -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/smartctl")
        process.arguments = ["--scan", "--json"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return []
            }

            if let json = try? JSONDecoder().decode(ScanOutput.self, from: Data(output.utf8)) {
                return json.devices.map { $0.name }
            }

            return output
                .split(separator: "\n")
                .compactMap { line -> String? in
                    let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ")
                    return parts.first.map(String.init)
                }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        } catch {
            return []
        }
    }

    /// Get S.M.A.R.T. status for a disk.
    static func getStatus(for devicePath: String) async -> SMARTStatus? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/smartctl")
        process.arguments = ["-a", "-j", devicePath]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8),
                  let json = try? JSONDecoder().decode(SMARTJSON.self, from: Data(output.utf8)) else {
                return nil
            }

            let isHealthy = json.smart_status.passed
            let model = json.device.model ?? "Unknown"
            let serial = json.device.serial?.isEmpty == false ? json.device.serial : nil

            let temperature = json.attribute?.first(where: { $0.id == 194 })?.value
            let powerOnHours = json.attribute?.first(where: { $0.id == 9 })?.value
            let reallocated = json.attribute?.first(where: { $0.id == 5 })?.raw
            let pending = json.attribute?.first(where: { $0.id == 197 })?.raw
            let readErrors = json.attribute?.first(where: { $0.id == 187 })?.raw
            let writeErrors = json.attribute?.first(where: { $0.id == 200 })?.raw

            return SMARTStatus(
                devicePath: devicePath,
                model: model,
                serial: serial,
                isHealthy: isHealthy,
                temperature: temperature,
                powerOnHours: powerOnHours,
                reallocatedSectors: reallocated,
                currentPendingSectors: pending,
                unisksReadErrors: readErrors,
                unisksWriteErrors: writeErrors,
                rawOutput: output
            )
        } catch {
            return nil
        }
    }

    /// Enable S.M.A.R.T. for a disk.
    static func enableSMART(for devicePath: String) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/smartctl")
        process.arguments = ["-s", "on", devicePath]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

// MARK: - JSON Parsing

private struct ScanOutput: Decodable {
    let devices: [DeviceInfo]
    struct DeviceInfo: Decodable { let name: String }
}

private struct SMARTJSON: Decodable {
    let smart_status: SmartStatus
    let device: DeviceInfo
    let attribute: [SMARTAttribute]?

    struct SmartStatus: Decodable { let passed: Bool }
    struct DeviceInfo: Decodable { let model: String?; let serial: String? }
    struct SMARTAttribute: Decodable { let id: Int; let value: Int?; let raw: Int? }
}

#endif  // DISKTRACKER_V05
