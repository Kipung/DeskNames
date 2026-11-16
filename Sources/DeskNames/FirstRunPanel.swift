import SwiftUI

struct FirstRunPanel<Content: View>: View {
    @ObservedObject var onboarding: FirstRunPreferences
    @ObservedObject var store: Store
    @ObservedObject var workspace: LayoutController
    @ObservedObject var shortcuts: ShortcutSettings
    let loginItem: LoginItemController
    let desktop: Desktop?
    let close: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var selectedPreset = PanePreset.halves
    @State private var error = ""

    var body: some View {
        if onboarding.isPresented { welcome }
        else { content() }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Welcome to DeskNames", systemImage: "rectangle.3.group.fill")
                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(palette[0])
                Spacer()
                Button(action: close) { Image(systemName: "xmark").padding(6) }
                    .buttonStyle(.plain).accessibilityLabel("Close setup")
            }
            Text("Your desktops, with room to work.").foregroundStyle(.secondary)
            HStack(spacing: 8) {
                stepLabel("1  Accessibility", step: .accessibility)
                stepLabel("2  Shortcuts", step: .shortcuts)
                stepLabel("3  Pane layout", step: .layout)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch onboarding.step {
                    case .accessibility:
                        Text("Allow window controls").font(.title2).fontWeight(.semibold)
                        Text("Accessibility lets DeskNames read window titles, move and resize windows, and switch desktops.")
                            .foregroundStyle(.secondary)
                        Label(store.accessibilityGranted ? "Accessibility is allowed" : "Waiting for your approval",
                              systemImage: store.accessibilityGranted ? "checkmark.circle.fill" : "hand.raised.fill")
                            .foregroundStyle(store.accessibilityGranted ? palette[0] : .orange)
                        Text("Open Accessibility settings and turn on DeskNames. Return here when you're ready. Approval is detected automatically; no relaunch is needed.")
                        Button("Open Accessibility settings") { workspace.native.requestPermission() }
                            .buttonStyle(.borderedProminent)
                        Text("Already enabled but still waiting? Remove the old DeskNames entry with the − button, then add this copy from Applications and enable it again.")
                            .font(.caption).foregroundStyle(.secondary)
                    case .shortcuts:
                        Text("Arrange windows from the keyboard").font(.title2).fontWeight(.semibold)
                        Text("Shortcuts start off. Enable the suggested window, pane and desktop bindings together, then customize them in Settings → Keyboard shortcuts.")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 12) {
                            shortcutExample("Open this panel", keys: "⌃⌥⌘ Space")
                            shortcutExample("Left / right half", keys: "⌃⌥ ← / →")
                            shortcutExample("Maximize", keys: "⌃⌥ Return")
                            shortcutExample("Move into pane 1–4", keys: "⌃⌥ F1–F4")
                        }.padding(16).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                        if shortcuts.enabled {
                            Label("Shortcuts enabled", systemImage: "checkmark.circle.fill").foregroundStyle(palette[0])
                            Button("Turn shortcuts off") { shortcuts.setEnabled(false) }
                        } else {
                            Button("Enable suggested shortcuts") { shortcuts.enableSuggestions() }
                                .buttonStyle(.borderedProminent)
                        }
                        if !shortcuts.message.isEmpty { Text(shortcuts.message).font(.caption).foregroundStyle(.orange) }
                        Text("If a shortcut is unavailable or does nothing, check Accessibility and change conflicting bindings in Keyboard shortcuts.")
                            .font(.caption).foregroundStyle(.secondary)
                    case .layout:
                        Text("Choose your first pane layout").font(.title2).fontWeight(.semibold)
                        Text(desktop.map { "Guides for " + store.name($0) } ?? "Open the panel on an ordinary desktop to choose guides.")
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                            ForEach(PanePreset.allCases) { preset in
                                Button { selectedPreset = preset } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        PaneDiagram(configuration: PaneConfiguration(preset: preset), compact: true, hovered: nil, onHover: nil)
                                            .frame(height: 36).accessibilityHidden(true)
                                        Text(preset.name).font(.system(size: 11, weight: .medium))
                                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(selectedPreset == preset ? palette[0].opacity(0.15) : .white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selectedPreset == preset ? palette[0] : .clear))
                                }.buttonStyle(.plain).accessibilityLabel(preset.name)
                                    .accessibilityValue(selectedPreset == preset ? "Selected" : "")
                            }
                        }
                        Text("Hold Command while dragging a window, then release the mouse before Command to fit it. Panes start edge-to-edge. Choosing guides leaves existing windows in place.")
                            .font(.caption).foregroundStyle(.secondary)
                        LoginItemControls(controller: loginItem)
                    case .complete:
                        EmptyView()
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(2)
            }
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.orange) }
            Divider()
            HStack {
                Button("Set up later") { onboarding.finish() }
                Spacer()
                if onboarding.step == .layout {
                    Button("Use this layout") {
                        guard let desktop, workspace.choosePanePreset(selectedPreset, for: desktop) else {
                            error = desktop == nil ? "Open this panel on an ordinary desktop." : workspace.message
                            return
                        }
                        onboarding.finish()
                    }.buttonStyle(.borderedProminent).disabled(desktop == nil || workspace.busy)
                } else {
                    Button(onboarding.step == .accessibility && !store.accessibilityGranted ? "Continue without permission" : "Continue") {
                        onboarding.advance()
                    }.buttonStyle(.borderedProminent)
                }
            }
            Text("Change these choices in Settings or the control panel. Find DeskNames in the menu bar whenever you need it.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 560, height: 690)
            .background(Color(red: 0.09, green: 0.11, blue: 0.135)).preferredColorScheme(.dark)
            .onExitCommand(perform: close)
    }

    private func stepLabel(_ title: String, step: FirstRunPreferences.Step) -> some View {
        Text(title).font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 9)
            .background(onboarding.step == step ? palette[0].opacity(0.16) : .white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(onboarding.step == step ? palette[0] : .secondary)
    }
    private func shortcutExample(_ title: String, keys: String) -> some View {
        HStack { Text(title); Spacer(); Text(keys).monospaced() }.font(.system(size: 13))
    }
}
