//
//  NetworkVolumeScannerTests.swift
//  DiskTrackerTests
//

import XCTest
import Foundation
@testable import DiskTracker

final class NetworkVolumeScannerTests: XCTestCase {

    func testNetworkVolumeInitialization() {
        let url = URL(fileURLWithPath: "/Volumes/TestShare")
        let volume = NetworkVolume(
            url: url,
            name: "TestShare",
            type: .smb,
            host: "192.168.1.10"
        )

        XCTAssertEqual(volume.name, "TestShare")
        XCTAssertEqual(volume.type, .smb)
        XCTAssertEqual(volume.host, "192.168.1.10")
        XCTAssertEqual(volume.url.path, "/Volumes/TestShare")
    }

    func testNetworkVolumeScanResult() {
        let url = URL(fileURLWithPath: "/Volumes/TestShare")
        let volume = NetworkVolume(
            url: url,
            name: "TestShare",
            type: .smb,
            host: "192.168.1.10"
        )
        let result = NetworkVolumeScanResult(
            volume: volume,
            totalSize: 5000,
            fileCount: 42
        )

        XCTAssertEqual(result.totalSize, 5000)
        XCTAssertEqual(result.fileCount, 42)
        XCTAssertEqual(result.volume.name, "TestShare")
    }

    // MARK: - Pure helper seams

    func testDetectShareTypeSMBByName() {
        let url = URL(fileURLWithPath: "/Volumes/share")
        XCTAssertEqual(NetworkVolumeScanner.testDetectShareType(name: "Files (SMB)", url: url), .smb)
        XCTAssertEqual(NetworkVolumeScanner.testDetectShareType(name: "CIFS Mount", url: url), .smb)
    }

    func testDetectShareTypeAFPByPath() {
        let url = URL(fileURLWithPath: "/Volumes/AFPShare")
        XCTAssertEqual(NetworkVolumeScanner.testDetectShareType(name: "AFPShare", url: url), .afp)
    }

    func testDetectShareTypeNFSByName() {
        let url = URL(fileURLWithPath: "/Volumes/nfsdata")
        XCTAssertEqual(NetworkVolumeScanner.testDetectShareType(name: "nfsdata", url: url), .nfs)
    }

    func testDetectShareTypeUnknownForLocalVolume() {
        let url = URL(fileURLWithPath: "/Volumes/Macintosh HD")
        XCTAssertEqual(NetworkVolumeScanner.testDetectShareType(name: "Macintosh HD", url: url), .unknown)
    }

    func testExtractHostFromStandardVolumePath() {
        XCTAssertEqual(NetworkVolumeScanner.testExtractHost(from: "/Volumes/Server01/Data"), "Server01")
        XCTAssertEqual(NetworkVolumeScanner.testExtractHost(from: "/Volumes/192.168.1.10"), "192.168.1.10")
    }

    func testExtractHostFromUncStylePath() {
        XCTAssertEqual(NetworkVolumeScanner.testExtractHost(from: "//server/share"), "server")
    }

    func testExtractHostUnknownForUnrecognizedPath() {
        XCTAssertEqual(NetworkVolumeScanner.testExtractHost(from: "/etc/hosts"), "Unknown")
    }
}
