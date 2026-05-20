import Foundation

enum RepoActivityIgnoreRules {
    private static let ignoredDirectoryNames: Set<String> = [
        ".build",
        ".swiftpm",
        "DerivedData",
        "node_modules",
    ]

    static func shouldIgnore(path: String, rootPath: String, isDirectory _: Bool) -> Bool {
        let relativePath = relativePath(path: path, rootPath: rootPath)
        let components = relativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return false }
        if components.contains(where: ignoredDirectoryNames.contains) {
            return true
        }
        return components.first == ".git" && relativePath.hasSuffix(".lock")
    }

    private static func relativePath(path: String, rootPath: String) -> String {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let normalizedRoot = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        guard normalizedPath == normalizedRoot || normalizedPath.hasPrefix(normalizedRoot + "/") else {
            return normalizedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        if normalizedPath == normalizedRoot {
            return ""
        }
        return String(normalizedPath.dropFirst(normalizedRoot.count + 1))
    }
}
