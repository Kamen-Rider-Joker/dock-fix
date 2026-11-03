import Foundation

let logURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/DockUnstick.log")

/// Past this size the log moves to DockUnstick.log.1 (replacing the previous one), so
/// the two files together stay around 2 MB.
let logSizeLimit: UInt64 = 1_000_000

private let diagnosticLoggingEnabled = CommandLine.arguments.contains {
    $0 == "--tap" || $0 == "--dump"
}

func log(_ message: String) {
    guard diagnosticLoggingEnabled || Preferences.loggingEnabled else { return }
    let line = "\(ISO8601DateFormatter.withFraction.string(from: Date())) \(message)\n"
    FileHandle.standardError.write(line.data(using: .utf8)!)
    rotateIfNeeded(logURL, limit: logSizeLimit)
    if let handle = try? FileHandle(forWritingTo: logURL) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        try? handle.close()
    } else {
        try? line.write(to: logURL, atomically: true, encoding: .utf8)
    }
}

func rotateIfNeeded(_ url: URL, limit: UInt64) {
    let fileManager = FileManager.default
    guard let size = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? UInt64, size >= limit else { return }
    let previous = url.appendingPathExtension("1")
    try? fileManager.removeItem(at: previous)
    try? fileManager.moveItem(at: url, to: previous)
}

extension ISO8601DateFormatter {
    static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
