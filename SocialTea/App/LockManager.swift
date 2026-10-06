import Foundation
import LocalAuthentication
import Observation

/// Optional app lock. OFF by default.
///
/// - Face ID / Touch ID: the on/off *preference* is remembered (it's a setting, not your data).
/// - Session PIN: kept in memory only and forgotten when the app closes.
@MainActor
@Observable
final class LockManager {
    private static let biometricKey = "lock.biometricEnabled"

    var biometricEnabled: Bool {
        didSet { UserDefaults.standard.set(biometricEnabled, forKey: Self.biometricKey) }
    }
    /// 4-digit PIN for this session only. Never written anywhere.
    private(set) var sessionPIN: String?
    private(set) var isLocked: Bool = false
    var lastError: String?

    init() {
        let enabled = UserDefaults.standard.bool(forKey: Self.biometricKey)
        biometricEnabled = enabled
        isLocked = enabled
    }

    var isEnabled: Bool { biometricEnabled || sessionPIN != nil }

    var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Face ID / Touch ID"
        }
    }

    var biometricsAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    func lockIfEnabled() {
        if isEnabled { isLocked = true }
    }

    func setPIN(_ pin: String?) {
        guard let pin else { sessionPIN = nil; return }
        guard pin.count == 4, pin.allSatisfy(\.isNumber) else { return }
        sessionPIN = pin
    }

    func unlock(withPIN pin: String) -> Bool {
        guard let sessionPIN, pin == sessionPIN else { return false }
        isLocked = false
        return true
    }

    func unlockWithBiometrics() async {
        let context = LAContext()
        context.localizedFallbackTitle = sessionPIN == nil ? "Use Passcode" : ""
        // Falls back to the device passcode so the user can never lock themselves out.
        let policy: LAPolicy = .deviceOwnerAuthentication
        do {
            let ok = try await context.evaluatePolicy(policy, localizedReason: "Unlock SocialTea")
            if ok { isLocked = false; lastError = nil }
        } catch {
            let quiet: [LAError.Code] = [.userCancel, .systemCancel, .appCancel, .notInteractive]
            if let code = (error as? LAError)?.code, quiet.contains(code) {
                lastError = nil
            } else {
                lastError = error.localizedDescription
            }
        }
    }

    /// When the user turns biometrics on, confirm it works first.
    func enableBiometrics() async -> Bool {
        let context = LAContext()
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                      localizedReason: "Turn on app lock for SocialTea")
            biometricEnabled = ok
            return ok
        } catch {
            biometricEnabled = false
            return false
        }
    }
}
