import Foundation
import Testing

@testable import Muxy

@Suite("RepoActivityIgnoreRules")
struct RepoActivityIgnoreRulesTests {
    @Test("ignores generated directories and git lock files")
    func ignoresGeneratedDirectoriesAndGitLockFiles() {
        let root = "/tmp/repo"

        #expect(RepoActivityIgnoreRules.shouldIgnore(
            path: "\(root)/.git/index.lock",
            rootPath: root,
            isDirectory: false
        ))
        #expect(RepoActivityIgnoreRules.shouldIgnore(
            path: "\(root)/.git/refs/heads/main.lock",
            rootPath: root,
            isDirectory: false
        ))
        #expect(RepoActivityIgnoreRules.shouldIgnore(
            path: "\(root)/.build/debug/Muxy",
            rootPath: root,
            isDirectory: false
        ))
        #expect(RepoActivityIgnoreRules.shouldIgnore(
            path: "\(root)/node_modules/package/index.js",
            rootPath: root,
            isDirectory: false
        ))
        #expect(RepoActivityIgnoreRules.shouldIgnore(
            path: "\(root)/.swiftpm/xcode/package.xcworkspace",
            rootPath: root,
            isDirectory: true
        ))
        #expect(RepoActivityIgnoreRules.shouldIgnore(
            path: "\(root)/DerivedData/Build/Products",
            rootPath: root,
            isDirectory: true
        ))
    }

    @Test("keeps git state and source paths that should refresh consumers")
    func keepsGitStateAndSourcePaths() {
        let root = "/tmp/repo"

        #expect(!RepoActivityIgnoreRules.shouldIgnore(
            path: "\(root)/.git/index",
            rootPath: root,
            isDirectory: false
        ))
        #expect(!RepoActivityIgnoreRules.shouldIgnore(
            path: "\(root)/.git/HEAD",
            rootPath: root,
            isDirectory: false
        ))
        #expect(!RepoActivityIgnoreRules.shouldIgnore(
            path: "\(root)/.git/refs/heads/main",
            rootPath: root,
            isDirectory: false
        ))
        #expect(!RepoActivityIgnoreRules.shouldIgnore(
            path: "\(root)/Muxy/Models/AppState.swift",
            rootPath: root,
            isDirectory: false
        ))
        #expect(!RepoActivityIgnoreRules.shouldIgnore(
            path: "\(root)/Package.swift",
            rootPath: root,
            isDirectory: false
        ))
    }
}
