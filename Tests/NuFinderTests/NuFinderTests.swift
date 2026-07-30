import Foundation
import Testing
@testable import NuFinder

private final class ByteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Int64 = 0
    func add(_ value: Int64) { lock.withLock { storage += value } }
    var value: Int64 { lock.withLock { storage } }
}

struct NuFinderTests {
    @Test @MainActor func doesNotRestoreTransientMountedVolumeTabs() {
        #expect(!BrowserModel.isRestorableSessionPath("/Volumes"))
        #expect(!BrowserModel.isRestorableSessionPath("/Volumes/offline-share"))
        #expect(BrowserModel.isRestorableSessionPath("/Users/example/Documents"))
        #expect(
            BrowserModel.storedDirectoryURL("/Volumes/offline-share").path
                == "/Volumes/offline-share"
        )
    }

    @Test func recognizesFolderSymlinkAsNavigableDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let target = root.appendingPathComponent("target", isDirectory: true)
        let link = root.appendingPathComponent("linked folder")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        defer { try? FileManager.default.removeItem(at: root) }

        let item = try #require(FileItem.load(link))
        #expect(item.isSymbolicLink)
        #expect(item.isDirectory)
    }

    @Test @MainActor func navigationResolvesFolderSymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let target = root.appendingPathComponent("target", isDirectory: true)
        let link = root.appendingPathComponent("linked folder")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        defer { try? FileManager.default.removeItem(at: root) }

        let browser = BrowserModel(initialURL: root, restoresSession: false)
        browser.navigate(to: link)
        #expect(browser.currentURL == target.standardizedFileURL)
        #expect(browser.addressText == target.path)
    }

    @Test func countsNestedFileBytes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data(repeating: 1, count: 17).write(to: root.appendingPathComponent("a"))
        let nested = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 2, count: 25).write(to: nested.appendingPathComponent("b"))

        #expect(FileOperationManager.totalBytes(of: [root]) == 42)
    }

    @Test func keepBothCreatesNumberedName() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let original = root.appendingPathComponent("Report.txt")
        try Data().write(to: original)
        let candidate = FileOperationManager.uniqueDestination(for: original, in: root)
        #expect(candidate.lastPathComponent == "Report 2.txt")
    }

    @Test func transferCanCopyAndMove() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sourceDirectory = root.appendingPathComponent("source")
        let destinationDirectory = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = sourceDirectory.appendingPathComponent("note.txt")
        let copy = destinationDirectory.appendingPathComponent("copy.txt")
        let moved = destinationDirectory.appendingPathComponent("moved.txt")
        try Data("NuFinder".utf8).write(to: source)

        try FileOperationManager.transfer(source: source, target: copy, move: false)
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(try Data(contentsOf: copy) == Data("NuFinder".utf8))

        try FileOperationManager.transfer(source: source, target: moved, move: true)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(try Data(contentsOf: moved) == Data("NuFinder".utf8))
    }

    @Test @MainActor func tabsKeepIndependentNavigationHistory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = root.appendingPathComponent("first")
        let child = first.appendingPathComponent("child")
        let second = root.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let browser = BrowserModel(initialURL: first, restoresSession: false)
        let firstTab = browser.activeTabID
        browser.navigate(to: child)
        browser.newTab(at: second)
        let secondTab = browser.activeTabID

        #expect(browser.currentURL.path == second.path)
        browser.selectTab(firstTab)
        #expect(browser.currentURL.path == child.path)
        browser.goBack()
        #expect(browser.currentURL.path == first.path)
        browser.selectTab(secondTab)
        #expect(browser.currentURL.path == second.path)
    }

    @Test @MainActor func breadcrumbsAreBoundedAtFilesystemRoot() {
        let root = BreadcrumbView.componentURLs(for: URL(fileURLWithPath: "/"))
        #expect(root.count == 1)
        #expect(root[0].path == "/")

        let nested = BreadcrumbView.componentURLs(for: URL(fileURLWithPath: "/Users/example/Documents"))
        #expect(nested.map(\.path) == ["/", "/Users", "/Users/example", "/Users/example/Documents"])
    }

    @Test func searchSupportsContainsGlobAndRegex() {
        #expect(BrowserModel.matches("Annual Report.pdf", query: "report", mode: .contains))
        #expect(BrowserModel.matches("photo-2026.jpg", query: "photo-*.jpg", mode: .glob))
        #expect(!BrowserModel.matches("photo-2026.png", query: "photo-*.jpg", mode: .glob))
        #expect(BrowserModel.matches("IMG_0042.HEIC", query: #"IMG_\d+\.HEIC"#, mode: .regex))
    }

    @Test func rejectsMovingFolderIntoItsDescendant() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let child = root.appendingPathComponent("child")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: (any Error).self) {
            try FileOperationManager.validate(source: root, destination: child, move: true)
        }
    }

    @Test func calculatesKnownSHA256() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("NuFinder".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(try FileActionService.sha256(of: file) ==
                "1ada333967fb366cf692a7c7cb5e6f998e33022782fde2e7a1c85a2cf2dbed02")
    }

    @Test func chunkedCopyReportsBytesAndPreservesPermissions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.bin")
        let target = root.appendingPathComponent("target.bin")
        let payload = Data(repeating: 0x5a, count: ChunkedFileCopier.chunkSize * 2 + 17)
        try payload.write(to: source)
        try FileMetadataService.setPermissions(0o640, at: source)
        let reported = ByteCounter()

        try ChunkedFileCopier.transfer(
            source: source,
            target: target,
            move: false,
            control: TransferControl()
        ) { reported.add($0) }

        #expect(try Data(contentsOf: target) == payload)
        #expect(reported.value == Int64(payload.count))
        #expect(try FileMetadataService.permissions(at: target) & 0o777 == 0o640)
    }

    @Test func cancelledChunkedCopyLeavesNoTarget() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        let target = root.appendingPathComponent("target")
        try Data(repeating: 1, count: 128).write(to: source)
        let control = TransferControl()
        control.cancel()

        #expect(throws: (any Error).self) {
            try ChunkedFileCopier.transfer(
                source: source,
                target: target,
                move: false,
                control: control
            ) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    @Test func canEditExtendedAttributes() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let name = "com.nufinder.test"
        try FileMetadataService.setAttribute(name, value: Data("hello".utf8), at: file)
        let attribute = try #require(
            FileMetadataService.extendedAttributes(at: file).first { $0.name == name }
        )
        #expect(attribute.displayValue == "hello")
        try FileMetadataService.removeAttribute(name, at: file)
        #expect(try FileMetadataService.extendedAttributes(at: file).contains { $0.name == name } == false)
    }
}
