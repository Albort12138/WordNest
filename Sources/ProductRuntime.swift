import AppKit
import Carbon
import Darwin

enum ProductLaunchMode: Equatable {
    case normal
    case development(String)
    case invalid
}

/// Distribution builds never dispatch development commands that can write test data.
enum ProductRuntime {
    static var allowsDevelopmentModes: Bool {
        #if WORDNEST_DEVELOPMENT
        return true
        #else
        return false
        #endif
    }

    static let developmentCommands = [
        "--smoke-test", "--ui-self-test", "--setup-preview", "--notes-readback-test",
        "--alphabet-integration-test", "--multilingual-integration-test", "--alphabet-library-preview",
        "--multilingual-preview", "--dictionary-preview", "--notes-integration-preview",
        "--notes-settings-preview", "--source-permission-preview", "--source-readback-test", "--local-dictionary-preview"
    ]

    static func launchMode(arguments: [String], allowsDevelopment: Bool = allowsDevelopmentModes) -> ProductLaunchMode {
        let flags = arguments.dropFirst().filter { $0.hasPrefix("--") }
        if flags.isEmpty { return .normal }
        guard allowsDevelopment else { return .invalid }
        let commands = flags.filter { developmentCommands.contains($0) }
        guard commands.count == 1, flags.allSatisfy({ developmentCommands.contains($0)
            || $0.hasPrefix("--notes-entry-id=") || $0.hasPrefix("--source-test-bundle=") }) else { return .invalid }
        return .development(commands[0])
    }
}

struct RestartParentCandidate {
    let processID: Int32
    let bundleIdentifier: String?
    let bundleURL: URL?
}

/// Restart metadata only postpones ordinary startup; it never bypasses singleton or permission checks.
enum RestartHandoff {
    static let parentPIDKey = "WORDNEST_RESTART_PARENT_PID"

    static func parentProcess(environment: [String: String], ownPID: Int32, bundleIdentifier: String,
                              bundleURL: URL, candidates: [RestartParentCandidate]) -> Int32? {
        guard let raw = environment[parentPIDKey], let pid = Int32(raw), pid > 0, pid != ownPID,
              candidates.contains(where: { candidate in
                  candidate.processID == pid && candidate.bundleIdentifier == bundleIdentifier
                      && candidate.bundleURL?.standardizedFileURL == bundleURL.standardizedFileURL
              }) else { return nil }
        return pid
    }

    /// Observe process exit instead of racing launch completion against the old instance's termination.
    @MainActor static func waitForExit(processID: Int32, timeout: TimeInterval = 10) async -> Bool {
        if kill(processID, 0) != 0 && errno == ESRCH { return true }
        return await withCheckedContinuation { continuation in
            let source = DispatchSource.makeProcessSource(identifier: processID, eventMask: .exit, queue: .main)
            var completed = false
            var timeoutWork: DispatchWorkItem?
            func finish(_ exited: Bool) {
                guard !completed else { return }
                completed = true
                timeoutWork?.cancel()
                source.setEventHandler {}
                source.cancel()
                continuation.resume(returning: exited)
            }
            source.setEventHandler { finish(true) }
            let work = DispatchWorkItem { finish(false) }
            timeoutWork = work
            source.resume()
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
        }
    }
}

/// A preflight never asks for consent; explicit Setup buttons own all permission requests.
enum AutomationConsent {
    static func state(for bundleID: String, prompt: Bool = false) -> SetupPermissionState {
        let descriptor = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let pointer = descriptor.aeDesc else { return .unavailable }
        var target = pointer.pointee
        switch AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, prompt) {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted), OSStatus(errAEEventWouldRequireUserConsent): return .notGranted
        default: return .unavailable
        }
    }
}

/// The public bundle imports valid user choices, but never imports permission or setup claims.
enum LegacyPreferences {
    static func migrate(from legacy: UserDefaults, to current: UserDefaults) {
        let configuration = "vocabulary.appleNotes.configuration.v2"
        let destination = "vocabulary.appleNotes.destination.v1"
        let language = "lookup.sourceLanguage.v1"
        if current.object(forKey: configuration) == nil, current.object(forKey: destination) == nil {
            if let data = legacy.data(forKey: configuration),
               (try? JSONDecoder().decode(NotesConfiguration.self, from: data)) != nil {
                current.set(data, forKey: configuration)
            } else if let data = legacy.data(forKey: destination),
                      (try? JSONDecoder().decode(NotesDestination.self, from: data)) != nil {
                current.set(data, forKey: destination)
            }
        }
        if current.object(forKey: language) == nil, let raw = legacy.string(forKey: language),
           SourceLanguage(rawValue: raw) != nil { current.set(raw, forKey: language) }
    }

    static func migrateIfNeeded() {
        guard Bundle.main.bundleIdentifier != "local.subtitlelookup.prototype",
              let legacy = UserDefaults(suiteName: "local.subtitlelookup.prototype") else { return }
        migrate(from: legacy, to: .standard)
    }
}
