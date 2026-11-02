import SwiftUI
import Carbon

struct ShortcutBinding: Codable, Equatable, Hashable {
    var key: UInt32
    var modifiers: UInt32

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        for (flag, value) in [(NSEvent.ModifierFlags.control, controlKey), (.option, optionKey), (.shift, shiftKey), (.command, cmdKey)] {
            if flags.contains(flag) { result |= UInt32(value) }
        }
        return result
    }

    static func modifierSymbols(_ modifiers: UInt32) -> String {
        [(UInt32(controlKey), "⌃"), (UInt32(optionKey), "⌥"), (UInt32(shiftKey), "⇧"), (UInt32(cmdKey), "⌘")]
            .filter { modifiers & $0.0 != 0 }.map { $0.1 }.joined()
    }

    var displayName: String {
        Self.modifierSymbols(modifiers) + (ShortcutKey.all.first { $0.id == key }?.name ?? "Unknown key")
    }
}

struct ShortcutAction: Identifiable {
    let id: UInt32
    let name: String
    let suggested: ShortcutBinding
    static let all: [ShortcutAction] = [ShortcutAction(id:100,name:"Desktop switcher",suggested:ShortcutBinding(key:49,modifiers:UInt32(cmdKey|optionKey)))] + zip(1...9,[18,19,20,21,23,22,26,28,25]).map { ShortcutAction(id:UInt32($0.0),name:"Go to desktop \($0.0)",suggested:ShortcutBinding(key:UInt32($0.1),modifiers:UInt32(controlKey|optionKey))) } + [ShortcutAction(id:101,name:"Save active layout",suggested:ShortcutBinding(key:1,modifiers:UInt32(controlKey|optionKey))),ShortcutAction(id:102,name:"Restore active layout",suggested:ShortcutBinding(key:15,modifiers:UInt32(controlKey|optionKey)))] + WindowAction.allCases.map { ShortcutAction(id:$0.id,name:$0.name,suggested:$0.suggestion) }
}

struct ShortcutKey: Identifiable {
    let id: UInt32
    let name: String
    static let all: [ShortcutKey] = [(0,"A"),(11,"B"),(8,"C"),(2,"D"),(14,"E"),(3,"F"),(5,"G"),(4,"H"),(34,"I"),(38,"J"),(40,"K"),(37,"L"),(46,"M"),(45,"N"),(31,"O"),(35,"P"),(12,"Q"),(15,"R"),(1,"S"),(17,"T"),(32,"U"),(9,"V"),(13,"W"),(7,"X"),(16,"Y"),(6,"Z"),(29,"0"),(18,"1"),(19,"2"),(20,"3"),(21,"4"),(23,"5"),(22,"6"),(26,"7"),(28,"8"),(25,"9"),(49,"Space"),(123,"Left arrow"),(124,"Right arrow"),(125,"Down arrow"),(126,"Up arrow"),(24,"="),(27,"−"),(30,"]"),(33,"["),(39,"'"),(41,";"),(42,"\\"),(43,","),(44,"/"),(47,"."),(50,"`"),(36,"Return"),(48,"Tab"),(51,"Delete"),(53,"Esc"),(117,"Forward delete"),(115,"Home"),(119,"End"),(116,"Page up"),(121,"Page down"),(122,"F1"),(120,"F2"),(99,"F3"),(118,"F4"),(96,"F5"),(97,"F6"),(98,"F7"),(100,"F8"),(101,"F9"),(109,"F10"),(103,"F11"),(111,"F12"),(105,"F13"),(107,"F14"),(113,"F15"),(106,"F16"),(64,"F17"),(79,"F18"),(80,"F19"),(90,"F20")].map {ShortcutKey(id:UInt32($0.0),name:$0.1)}
}

final class ShortcutSettings: ObservableObject {
    private struct Saved: Codable { var enabled: Bool; var bindings: [UInt32:ShortcutBinding] }
    private let defaults: UserDefaults
    private static let storageKey="keyboardShortcuts.v1"
    @Published private(set) var enabled=false
    @Published private(set) var bindings: [UInt32:ShortcutBinding]
    @Published private(set) var message=""
    @Published private(set) var recordingAction: UInt32?
    @Published var unavailable = Set<UInt32>()
    @Published var lastAction = ""
    var onChange: ((Bool,[UInt32:ShortcutBinding])->String)?
    init(defaults: UserDefaults = .standard) {
        self.defaults=defaults
        bindings=Dictionary(uniqueKeysWithValues:ShortcutAction.all.map{($0.id,$0.suggested)})
        if let data=defaults.data(forKey:Self.storageKey),let saved=try? JSONDecoder().decode(Saved.self,from:data),Self.validation(saved.bindings)==nil {
            bindings=saved.bindings
            enabled=saved.enabled
        }
    }
    static func validation(_ bindings:[UInt32:ShortcutBinding])->String? {
        var seen=Set<ShortcutBinding>()
        for (id,binding) in bindings.sorted(by:{$0.key<$1.key}) {
            guard ShortcutAction.all.contains(where:{$0.id==id}),ShortcutKey.all.contains(where:{$0.id==binding.key}),binding.modifiers & ~UInt32(cmdKey|optionKey|controlKey|shiftKey)==0,binding.modifiers & UInt32(cmdKey|optionKey|controlKey) != 0 else {return "Choose a key with Command, Option, or Control."}
            guard seen.insert(binding).inserted else {return "Each action needs a different shortcut."}
        }
        return nil
    }
    func addWindowSuggestions() {
        var next=bindings
        for action in WindowAction.allCases where next[action.id]==nil {
            if !next.values.contains(action.suggestion) { next[action.id]=action.suggestion }
        }
        if let error=Self.validation(next) { message=error;return }
        bindings=next;saveAndApply()
    }
    func setEnabled(_ value:Bool) {
        if value,let error=Self.validation(bindings) {message=error;return}
        enabled=value
        saveAndApply()
    }
    @discardableResult func set(_ binding:ShortcutBinding?,for id:UInt32) -> Bool {
        var next=bindings
        next[id]=binding
        if let error=Self.validation(next) {message=error;return false}
        bindings=next
        saveAndApply()
        return true
    }
    private func saveAndApply() {
        if let data=try? JSONEncoder().encode(Saved(enabled:enabled,bindings:bindings)) {defaults.set(data,forKey:Self.storageKey)}
        apply()
    }
    func apply() {message=onChange?(enabled && recordingAction == nil,bindings) ?? ""}

    func beginRecording(_ id: UInt32) {
        guard ShortcutAction.all.contains(where: { $0.id == id }) else { return }
        recordingAction = id
        apply()
    }

    func cancelRecording(_ id: UInt32) {
        guard recordingAction == id else { return }
        recordingAction = nil
        apply()
    }

    @discardableResult
    func record(key: UInt16, flags: NSEvent.ModifierFlags, isRepeat: Bool = false) -> Bool {
        guard let id = recordingAction else { return false }
        if isRepeat { return true }
        let modifiers = ShortcutBinding.carbonModifiers(flags)
        if key == 53 && modifiers == 0 {
            cancelRecording(id)
        } else if key == 48 && modifiers & ~UInt32(shiftKey) == 0 {
            cancelRecording(id)
            return false
        } else if (key == 51 || key == 117) && modifiers == 0 {
            set(nil, for: id)
            cancelRecording(id)
        } else if set(ShortcutBinding(key: UInt32(key), modifiers: modifiers), for: id) {
            cancelRecording(id)
        }
        return true
    }
}

final class HotKeys {
    private var refs:[UInt32:EventHotKeyRef]=[:]
    private var handler:EventHandlerRef?
    private var active=Set<UInt32>()
    private(set) var unavailable = Set<UInt32>()
    private let action:(UInt32)->Void
    private let registerKey:(UInt32,ShortcutBinding)->Bool
    private let unregisterKeys:()->Void
    init(action:@escaping(UInt32)->Void,register:((UInt32,ShortcutBinding)->Bool)?=nil,unregister:(()->Void)?=nil) {
        self.action=action
        self.registerKey=register ?? {_,_ in false}
        self.unregisterKeys=unregister ?? {}
        usesCarbon=register==nil
    }
    private let usesCarbon:Bool
    func apply(enabled:Bool,bindings:[UInt32:ShortcutBinding])->String {
        clear()
        unavailable.removeAll()
        guard enabled else {return ""}
        if let error=ShortcutSettings.validation(bindings) {return error}
        if usesCarbon && handler==nil {
            var type=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
            let status=InstallEventHandler(GetApplicationEventTarget(),{_,event,data in
                guard let event,let data else{return OSStatus(eventNotHandledErr)}
                var id=EventHotKeyID()
                guard GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&id)==noErr,id.signature==0x444E414D else{return OSStatus(eventNotHandledErr)}
                let owner=Unmanaged<HotKeys>.fromOpaque(data).takeUnretainedValue()
                guard owner.active.contains(id.id) else{return OSStatus(eventNotHandledErr)}
                owner.action(id.id)
                return noErr
            },1,&type,Unmanaged.passUnretained(self).toOpaque(),&handler)
            guard status==noErr else{return "Could not start keyboard shortcuts. Turn them off and try again."}
        }
        var failed:[String]=[]
        for entry in ShortcutAction.all {
            guard let binding=bindings[entry.id] else {continue}
            let success:Bool
            if usesCarbon {
                var ref:EventHotKeyRef?
                let status=RegisterEventHotKey(binding.key,binding.modifiers,EventHotKeyID(signature:0x444E414D,id:entry.id),GetApplicationEventTarget(),UInt32(kEventHotKeyExclusive),&ref)
                success=status==noErr && ref != nil
                if success {refs[entry.id]=ref}
            } else {success=registerKey(entry.id,binding)}
            if success {active.insert(entry.id)} else {unavailable.insert(entry.id);failed.append(entry.name)}
        }
        return failed.isEmpty ? "" : "Unavailable shortcuts: "+failed.joined(separator:", ")+". Choose another combination."
    }
    private func clear() {
        active.removeAll()
        for ref in refs.values {UnregisterEventHotKey(ref)}
        refs.removeAll()
        if !usesCarbon {unregisterKeys()}
    }
    deinit {clear();if let handler {RemoveEventHandler(handler)}}
}

struct ShortcutSettingsView: View {
    @ObservedObject var settings: ShortcutSettings
    @ObservedObject var workspace: LayoutController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Enable global keyboard shortcuts", isOn: Binding(get: { settings.enabled }, set: { settings.setEnabled($0) }))
            Text(settings.enabled ? "Shortcuts work while you use other apps. Changes save automatically." : "Shortcuts are off. You can edit them below before turning them on.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Add suggested window shortcuts") { settings.addWindowSuggestions() }
            Text("Click a shortcut, then press the keys you want to use.")
                .font(.system(size: 13))
            if !settings.message.isEmpty {
                Text(settings.message).font(.caption).foregroundStyle(.orange)
            }
            if !settings.lastAction.isEmpty {
                Text("Last shortcut: " + settings.lastAction).font(.caption).foregroundStyle(.secondary)
                if !workspace.message.isEmpty { Text(workspace.message).font(.caption).foregroundStyle(.secondary) }
            }
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(ShortcutAction.all) { action in
                        HStack {
                            VStack(alignment:.leading,spacing:3) {
                                Text(action.name).font(.system(size:12,weight:.medium))
                                if action.id < 100 && !workspace.store.desktops.contains(where:{$0.number == Int(action.id)}) {
                                    Text("Create this desktop in Mission Control first").font(.caption2).foregroundStyle(.secondary)
                                }
                                if settings.unavailable.contains(action.id) {
                                    Text("Unavailable · choose different keys or quit the conflicting app").font(.caption2).foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            ShortcutRecorder(settings: settings, action: action)
                                .frame(width: 210, height: 30)
                            Button("Clear") { settings.set(nil, for: action.id) }
                                .disabled(settings.bindings[action.id] == nil)
                                .accessibilityLabel("Clear " + action.name + " shortcut")
                        }
                        .controlSize(.small).padding(12)
                        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                    }
                }
            }
            Text("Include Command, Option, or Control. Escape cancels; Delete clears. DeskNames shortcuts pause while you record.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onDisappear {
            if let id = settings.recordingAction { settings.cancelRecording(id) }
        }
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    @ObservedObject var settings: ShortcutSettings
    let action: ShortcutAction

    func makeNSView(context: Context) -> ShortcutRecordButton {
        ShortcutRecordButton(settings: settings, shortcutAction: action)
    }

    func updateNSView(_ view: ShortcutRecordButton, context: Context) {
        view.refresh()
    }

    static func dismantleNSView(_ view: ShortcutRecordButton, coordinator: ()) {
        view.cancel()
    }
}

private final class ShortcutRecordButton: NSButton {
    private let settings: ShortcutSettings
    private let shortcutAction: ShortcutAction
    private var eventMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    init(settings: ShortcutSettings, shortcutAction: ShortcutAction) {
        self.settings = settings
        self.shortcutAction = shortcutAction
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        target = self
        action = #selector(startRecording)
        setAccessibilityLabel(shortcutAction.name + " shortcut")
        setAccessibilityHelp("Press to record a key combination. Escape cancels; Delete clears.")
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }

    private var isRecording: Bool { settings.recordingAction == shortcutAction.id }

    @objc private func startRecording() {
        guard let window, window.makeFirstResponder(self) else { return }
        settings.beginRecording(shortcutAction.id)
        refresh()
    }

    func refresh() {
        title = isRecording ? "Press shortcut…" : (settings.bindings[shortcutAction.id]?.displayName ?? "Click to record")
        toolTip = isRecording ? "Press your shortcut. Escape cancels; Delete clears." : "Click, then press a new key combination."
        contentTintColor = isRecording ? .controlAccentColor : .labelColor
        setAccessibilityValue(title)
        if isRecording && eventMonitor == nil {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
            resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                self?.cancel()
            }
        } else if !isRecording {
            removeObservers()
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard isRecording else { return event }
        guard event.window === window, window?.isKeyWindow == true, window?.firstResponder === self else {
            cancel()
            return event
        }
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            cancel()
            return event
        case .flagsChanged:
            let symbols = ShortcutBinding.modifierSymbols(ShortcutBinding.carbonModifiers(event.modifierFlags))
            title = symbols.isEmpty ? "Press shortcut…" : symbols + "…"
            setAccessibilityValue(title)
            return nil
        case .keyDown:
            let consumed = settings.record(key: event.keyCode, flags: event.modifierFlags, isRepeat: event.isARepeat)
            refresh()
            return consumed ? nil : event
        default:
            return event
        }
    }

    func cancel() {
        settings.cancelRecording(shortcutAction.id)
        removeObservers()
        refresh()
    }

    override func resignFirstResponder() -> Bool {
        cancel()
        return super.resignFirstResponder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { cancel() }
        super.viewWillMove(toWindow: newWindow)
    }

    private func removeObservers() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor); self.eventMonitor = nil }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver); self.resignObserver = nil }
    }

    deinit { removeObservers() }
}
