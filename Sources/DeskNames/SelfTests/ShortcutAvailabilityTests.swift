import Foundation

func runShortcutAvailabilityTests() {
    let domain = "local.desknames.availability.test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let settings = ShortcutSettings(defaults: defaults)
    precondition(!settings.updateAvailability(secureInput: true) && settings.availability == .disabled)
    settings.setEnabled(true)
    let request = settings.receive(320)
    precondition(settings.complete(request, result: "Placed fixture in pane 1."))
    let delivered = settings.delivery
    precondition(settings.updateAvailability(secureInput: true) && settings.availability == .secureInput)
    precondition(settings.availability.cause == "secure-input" && settings.availability.message.contains("Secure Input"))
    precondition(!settings.updateAvailability(secureInput: true), "Unchanged status must not repeatedly rewrite normal diagnostics")
    precondition(settings.delivery == delivered, "Secure Input status must not fabricate or erase a shortcut delivery")
    settings.beginRecording(100)
    precondition(settings.updateAvailability(secureInput: true) && settings.availability == .recording)
    settings.cancelRecording(100)
    precondition(settings.updateAvailability(secureInput: true) && settings.availability == .secureInput)
    precondition(settings.updateAvailability(secureInput: false) && settings.availability == .ready)
    precondition(settings.delivery == delivered, "Recovery without a key press must preserve the last real result")
    settings.unavailable = [320]
    precondition(settings.updateAvailability(secureInput: false) && settings.availability == .unavailable(1))
    precondition(settings.updateAvailability(secureInput: true) && settings.availability == .secureInput)
    settings.setEnabled(false)
    precondition(settings.updateAvailability(secureInput: true) && settings.availability == .disabled)
    precondition(settings.delivery == delivered)
    print("PASS: Secure Input availability and recovery without delivery; recording, disabled and registration states; last delivery retained")
}
