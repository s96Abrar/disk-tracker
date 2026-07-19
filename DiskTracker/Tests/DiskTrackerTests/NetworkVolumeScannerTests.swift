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
}
