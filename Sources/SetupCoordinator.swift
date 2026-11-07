import Foundation

/// Setup progress describes capability, not whether a system setting merely looks enabled.
enum SetupPermissionState: Equatable {
    case notGranted
    case granted
    case unavailable
}

enum SetupStep: Int, CaseIterable {
    case welcome, screenCapture, sources, notes, practice
}

enum SetupCompletion: String {
    case ready
    case deferred
}

struct SetupProgress: Equatable {
    var step: SetupStep = .welcome
    var screenCapture: SetupPermissionState = .notGranted
    var accessibility: SetupPermissionState = .notGranted
    var safariAutomation: SetupPermissionState = .notGranted
    var notesAutomation: SetupPermissionState = .notGranted

    var canLookUp: Bool { screenCapture == .granted }
    var completion: SetupCompletion { canLookUp ? .ready : .deferred }
    var isLastStep: Bool { step == .practice }

    mutating func advance() {
        step = SetupStep(rawValue: step.rawValue + 1) ?? .practice
    }

    mutating func back() {
        step = SetupStep(rawValue: step.rawValue - 1) ?? .welcome
    }
}

enum SetupPreferences {
    static let completedKey = "wordnest.setup.v1"
    static let resultKey = "wordnest.setup.v1.result"
    static let stepKey = "wordnest.setup.v1.step"

    /// Completion means the introduction was explicitly dismissed; permissions remain live state.
    static var hasCompleted: Bool {
        get { hasCompleted(in: .standard) }
        set { UserDefaults.standard.set(newValue, forKey: completedKey) }
    }

    static func hasCompleted(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: completedKey)
    }

    static func shouldPresentOnLaunch(in defaults: UserDefaults = .standard) -> Bool {
        // Completing an earlier introduction must not hide a later interrupted settings session.
        !hasCompleted(in: defaults) || defaults.object(forKey: stepKey) != nil
    }

    static func finish(_ completion: SetupCompletion, in defaults: UserDefaults = .standard) {
        defaults.set(completion.rawValue, forKey: resultKey)
        defaults.set(true, forKey: completedKey)
        defaults.removeObject(forKey: stepKey)
    }

    static func currentStep(in defaults: UserDefaults = .standard) -> SetupStep {
        guard defaults.object(forKey: stepKey) != nil else { return .welcome }
        return SetupStep(rawValue: defaults.integer(forKey: stepKey)) ?? .welcome
    }

    static func saveStep(_ step: SetupStep, in defaults: UserDefaults = .standard) {
        defaults.set(step.rawValue, forKey: stepKey)
    }

    /// Flush the small checkpoint before macOS can terminate this process for permission changes.
    static func checkpoint(_ step: SetupStep, in defaults: UserDefaults = .standard) {
        saveStep(step, in: defaults)
        defaults.synchronize()
    }
}
