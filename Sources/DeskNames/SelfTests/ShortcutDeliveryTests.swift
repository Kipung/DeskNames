import Foundation

func runShortcutDeliveryTests() {
    var delivery = ShortcutDelivery()
    let first = delivery.receive(101)
    precondition(delivery.action == "Save active layout" && delivery.result == "Received.")
    let second = delivery.receive(102)
    precondition(delivery.complete(second, result: ShortcutRefusal.noLayout.message))
    precondition(!delivery.complete(first, result: "Saved an earlier layout."))
    precondition(delivery.action == "Restore active layout" && delivery.result == ShortcutRefusal.noLayout.message,
                 "An older operation must not replace the latest shortcut's refusal")
    precondition(delivery.complete(second, result: "Operation cancelled."))
    let replacement = delivery.receive(320)
    precondition(!delivery.complete(second, result: "An old cancelled operation finished."))
    precondition(delivery.complete(replacement, result: "Moved the focused window."))
    precondition(delivery.actionID == 320 && delivery.result == "Moved the focused window.",
                 "Replacement completion must belong to the replacement shortcut")

    let actions = Dictionary(uniqueKeysWithValues: ShortcutAction.all.map { ($0.id, $0) })
    for action in ShortcutAction.all where action.requiresAccessibility {
        precondition(action.refusal(trusted: false, busy: false) == .accessibility,
                     "Revoked Accessibility must be reported before looking for an external window")
    }
    for id in [UInt32(100), PaneShortcut.next, PaneShortcut.previous, PaneShortcut.toggleLinked] {
        precondition(actions[id]!.refusal(trusted: false, busy: false) == nil,
                     "The control panel and pane preferences must remain available without Accessibility")
    }
    precondition(actions[103]!.refusal(trusted: true, busy: false, hasWindow: false) == .noWindow,
                 "Pinning without a focused window must report a quiet refusal")
    for id in [UInt32(101), 102] {
        precondition(actions[id]!.refusal(trusted: true, busy: true) == .busy)
        precondition(actions[id]!.refusal(trusted: true, busy: false, hasDesktop: false) == .noDesktop,
                     "Saving and restoring without an ordinary desktop must not silently return")
    }
    precondition(actions[102]!.refusal(trusted: true, busy: false, hasDesktop: true, hasLayout: false) == .noLayout,
                 "Restoring an unsaved desktop must explain the missing layout")
    precondition(actions[102]!.refusal(trusted: true, busy: false, hasDesktop: true, hasLayout: true) == nil)
    precondition(actions[1]!.refusal(trusted: true, busy: true) == nil,
                 "Desktop requests keep the existing queueing behavior while a writer finishes")

    let domain = "local.desknames.delivery.test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let settings = ShortcutSettings(defaults: defaults)
    let request = settings.receive(103)
    precondition(settings.complete(request, result: ShortcutRefusal.noWindow.message))
    precondition(settings.lastAction == ShortcutAction.pin.name && settings.delivery.result == ShortcutRefusal.noWindow.message)
    settings.apply()
    precondition(settings.delivery.result == ShortcutRefusal.noWindow.message,
                 "Registration changes must not erase the last delivered shortcut result")
    print("PASS: shortcut trust, busy, missing-window/desktop/layout refusals; latest delivery owns asynchronous results; diagnostic survives registration changes")
}
