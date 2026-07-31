import Foundation
import AppKit

private struct GitHubRelease: Decodable {
    struct Asset: Decodable { let name: String }
    let tag_name: String
    let html_url: String
    let assets: [Asset]
}

@MainActor
final class UpdateManager: ObservableObject {
    @Published private(set) var isChecking = false
    @Published private(set) var isInstalling = false
    @Published private(set) var availableVersion: String?
    @Published private(set) var statusMessage = ""

    private let repository = "proxsyi/mcp-controller"
    private let assetName = "MCP-Controller-macOS.zip"
    private var startedAutomaticChecks = false
    private var timer: Timer?
    private var latestRelease: GitHubRelease?

    var updateAvailable: Bool { availableVersion != nil }

    deinit {
        timer?.invalidate()
    }

    func beginAutomaticChecks() {
        guard !startedAutomaticChecks else { return }
        startedAutomaticChecks = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            checkForUpdates(silent: true)
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 21_600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkForUpdates(silent: true) }
        }
    }

    func checkForUpdates(silent: Bool = false) {
        guard !isChecking else { return }
        isChecking = true
        if !silent { statusMessage = "Checking GitHub…" }

        defer { isChecking = false }
        do {
            let release = try loadLatestRelease()
            latestRelease = release
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
            let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            if isVersion(latest, newerThan: current) {
                availableVersion = latest
                statusMessage = "Version \(latest) is available."
            } else {
                availableVersion = nil
                statusMessage = "MCP Controller is up to date."
            }
        } catch {
            if !silent { statusMessage = error.localizedDescription }
        }
    }

    func installAvailableUpdate() {
        guard let release = latestRelease, updateAvailable, !isInstalling else { return }
        isInstalling = true
        statusMessage = "Downloading version \(availableVersion ?? release.tag_name)…"

        let fileManager = FileManager.default
        var staging: URL?

        do {
            let gh = try githubCLIPath()
            guard release.assets.contains(where: { $0.name == assetName }) else {
                throw UpdateError.message("The release does not include \(assetName).")
            }

            let workingDirectory = fileManager.temporaryDirectory
                .appendingPathComponent("MCPControllerUpdate-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            staging = workingDirectory

            let download = try CommandRunner.run(
                executable: gh,
                arguments: ["release", "download", release.tag_name, "--repo", repository, "--pattern", assetName, "--dir", workingDirectory.path, "--clobber"]
            )
            guard download.exitCode == 0 else { throw UpdateError.message(download.error.isEmpty ? download.output : download.error) }

            let archive = workingDirectory.appendingPathComponent(assetName)
            let unpacked = workingDirectory.appendingPathComponent("unpacked", isDirectory: true)
            try fileManager.createDirectory(at: unpacked, withIntermediateDirectories: true)
            let expand = try CommandRunner.run(executable: "/usr/bin/ditto", arguments: ["-x", "-k", archive.path, unpacked.path])
            guard expand.exitCode == 0 else { throw UpdateError.message(expand.error.isEmpty ? expand.output : expand.error) }

            let newApp = unpacked.appendingPathComponent("MCP Controller.app", isDirectory: true)
            guard fileManager.fileExists(atPath: newApp.path),
                  Bundle(url: newApp)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
                throw UpdateError.message("The downloaded app has an unexpected bundle identifier.")
            }
            let verification = try CommandRunner.run(executable: "/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", newApp.path])
            guard verification.exitCode == 0 else { throw UpdateError.message("The downloaded app failed code-signature verification.") }

            try launchInstaller(newApp: newApp, currentApp: Bundle.main.bundleURL, staging: workingDirectory)
            statusMessage = "Installing update…"
            NSApplication.shared.terminate(nil)
        } catch {
            if let staging {
                try? fileManager.removeItem(at: staging)
            }
            isInstalling = false
            statusMessage = error.localizedDescription
        }
    }

    private func loadLatestRelease() throws -> GitHubRelease {
        let gh = try githubCLIPath()
        let result = try CommandRunner.run(executable: gh, arguments: ["api", "repos/\(repository)/releases/latest"])
        guard result.exitCode == 0 else {
            throw UpdateError.message("Could not read the private GitHub release. Make sure GitHub CLI is signed in and a release exists.")
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: Data(result.output.utf8))
    }

    private func githubCLIPath() throws -> String {
        for path in ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"] where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        throw UpdateError.message("GitHub CLI is required for private-repository updates. Install it with brew install gh, then run gh auth login.")
    }

    private func launchInstaller(newApp: URL, currentApp: URL, staging: URL) throws {
        let script = staging.appendingPathComponent("install-update.sh")
        let contents = """
        #!/bin/zsh
        set -e
        pid="$1"
        current="$2"
        replacement="$3"
        staging="$4"
        while /bin/kill -0 "$pid" 2>/dev/null; do /bin/sleep 0.25; done
        backup="${current}.previous-${pid}-$(/bin/date +%s)"
        /bin/mv "$current" "$backup"
        if /usr/bin/ditto "$replacement" "$current"; then
          /usr/bin/open "$current"
          /bin/rm -rf "$backup" "$staging"
        else
          /bin/rm -rf "$current"
          /bin/mv "$backup" "$current"
          /usr/bin/open "$current"
          exit 1
        fi
        """
        try contents.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), currentApp.path, newApp.path, staging.path]
        try process.run()
    }

    private func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let lhs = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(lhs.count, rhs.count) {
            let a = index < lhs.count ? lhs[index] : 0
            let b = index < rhs.count ? rhs[index] : 0
            if a != b { return a > b }
        }
        return false
    }
}

private enum UpdateError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}
