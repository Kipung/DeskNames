import Carbon

enum ShortcutDefaults {
    static let bindings: [UInt32: ShortcutBinding] = {
        let window = UInt32(controlKey | optionKey)
        let pane = UInt32(controlKey | optionKey | cmdKey)
        let upperQuarter = UInt32(controlKey | cmdKey)
        let column = UInt32(controlKey | optionKey | cmdKey | shiftKey)
        return [
            100: ShortcutBinding(key: 49, modifiers: pane),
            101: ShortcutBinding(key: 1, modifiers: window),
            102: ShortcutBinding(key: 15, modifiers: window),
            103: ShortcutBinding(key: 35, modifiers: window),
            200: ShortcutBinding(key: 123, modifiers: window),
            201: ShortcutBinding(key: 124, modifiers: window),
            202: ShortcutBinding(key: 126, modifiers: window),
            203: ShortcutBinding(key: 125, modifiers: window),
            204: ShortcutBinding(key: 123, modifiers: upperQuarter),
            205: ShortcutBinding(key: 124, modifiers: upperQuarter),
            206: ShortcutBinding(key: 123, modifiers: pane),
            207: ShortcutBinding(key: 124, modifiers: pane),
            208: ShortcutBinding(key: 18, modifiers: window),
            209: ShortcutBinding(key: 19, modifiers: window),
            210: ShortcutBinding(key: 20, modifiers: window),
            211: ShortcutBinding(key: 36, modifiers: window),
            212: ShortcutBinding(key: 44, modifiers: window),
            213: ShortcutBinding(key: 51, modifiers: window),
            214: ShortcutBinding(key: 27, modifiers: window),
            215: ShortcutBinding(key: 24, modifiers: window),
            218: ShortcutBinding(key: 18, modifiers: column),
            219: ShortcutBinding(key: 19, modifiers: column),
            220: ShortcutBinding(key: 20, modifiers: column),
            221: ShortcutBinding(key: 21, modifiers: column),
            320: ShortcutBinding(key: 18, modifiers: pane),
            321: ShortcutBinding(key: 19, modifiers: pane),
            322: ShortcutBinding(key: 20, modifiers: pane),
            323: ShortcutBinding(key: 21, modifiers: pane)
        ]
    }()
}
