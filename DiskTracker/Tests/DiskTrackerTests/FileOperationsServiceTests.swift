//
//  FileOperationsServiceTests.swift
//  DiskTrackerTests
//
//  Phase 3 TDD: FileOperationsService tests.
//  RED first — these define the expected batch operations contract.
//

import XCTest
import Foundation
@testable import DiskTracker

final class FileOperationsServiceTests: XCTestCase {

    // MARK: - System Path Protection

    func testIsSystemProtectedRootPath() {
        let service = FileOperationsService.shared
        XCTAssertTrue(service.isSystemProtected(url: URL(fileURLWithPath: "/")))
    }

    func testIsSystemProtectedSystemPath() {
        let service = FileOperationsService.shared
        XCTAssertTrue(service.isSystemProtected(url: URL(fileURLWithPath: "/System")))
        XCTAssertTrue(service.isSystemProtected(url: URL(fileURLWithPath: "/System/Library")))
    }

    func testIsSystemProtectedUserLibraryPath() {
        let service = FileOperationsService.shared
        let userLibrary = URL(fileURLWithPath: NSHomeDirectory() + "/Library")
        XCTAssertTrue(service.isSystemProtected(url: userLibrary))
    }

    func testIsNotSystemProtectedHomeSubfolder() {
        let service = FileOperationsService.shared
        let homeSubfolder = URL(fileURLWithPath: NSHomeDirectory() + "/Documents/test.txt")
        XCTAssertFalse(service.isSystemProtected(url: homeSubfolder))
    }

    func testIsNotSystemProtectedTmpFile() {
        let service = FileOperationsService.shared
        // /tmp is not in protectedPaths (only /private is)
        XCTAssertFalse(service.isSystemProtected(url: URL(fileURLWithPath: "/tmp/test")))
    }

    // MARK: - Single Trash

    func testMoveToTrashInvalidURLReturnsFailure() {
        let service = FileOperationsService.shared
        // Non-file URLs should be rejected
        let result = service.moveToTrash(url: URL(string: "http://example.com")!)
        if case .failure(.invalidURL) = result { } else {
            XCTFail("Expected .invalidURL for non-file URL")
        }
    }

    func testMoveToTrashSystemProtectedPathReturnsFailure() {
        let service = FileOperationsService.shared
        let result = service.moveToTrash(url: URL(fileURLWithPath: "/System"))
        if case .failure(.systemPathProtected) = result { } else {
            XCTFail("Expected .systemPathProtected for /System path")
        }
    }

    // MARK: - Batch Trash (Phase 3 gap — service doesn't have this yet)

    func testMoveMultipleToTrashReturnsPartialResults() {
        let service = FileOperationsService.shared

        let urls = [
            URL(fileURLWithPath: "/System"),           // protected
            URL(fileURLWithPath: NSHomeDirectory() + "/Documents/test.txt"), // home dir — valid URL
        ]

        // Returns array of (url, result) so caller knows per-item outcome
        let results = service.moveMultipleToTrash(urls: urls)

        XCTAssertEqual(results.count, 2)

        let systemResult = results.first { $0.url.path == "/System" }?.result
        if case .failure(.systemPathProtected) = systemResult { } else {
            XCTFail("Expected /System to be .systemPathProtected, got \(String(describing: systemResult))")
        }
    }

    func testMoveMultipleToTrashEmptyArrayReturnsEmpty() {
        let service = FileOperationsService.shared
        let results = service.moveMultipleToTrash(urls: [])
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Finder / QuickLook (smoke tests — UI calls, verify no crash)

    func testShowInFinderWithValidURLDoesNotThrow() {
        let service = FileOperationsService.shared
        let url = URL(fileURLWithPath: NSHomeDirectory())
        service.showInFinder(url: url)
    }

    func testOpenInDefaultAppDoesNotThrow() {
        let service = FileOperationsService.shared
        let url = URL(fileURLWithPath: NSHomeDirectory())
        service.openInDefaultApp(url: url)
    }
}