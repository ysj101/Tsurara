import AppKit
import SwiftUI
import TsuraraCore

/// A complete Settings tab that can be inserted directly into the app's Settings TabView.
struct HotkeySettingsTab: View {
    var body: some View {
        HotkeyRecorderView()
            .tabItem {
                Label("ホットキー", systemImage: "keyboard")
            }
    }
}

struct HotkeyRecorderView: View {
    @StateObject private var recorder = HotkeyRecorderModel()

    var body: some View {
        Form {
            LabeledContent("非表示セクションのトグル") {
                Text(recorder.assignmentDisplay)
                    .monospaced()
            }

            HStack {
                Button(recorder.isRecording ? "ショートカットを入力…" : "記録開始") {
                    recorder.startRecording()
                }
                .disabled(recorder.isRecording)

                if recorder.isRecording {
                    Button("キャンセル") {
                        recorder.cancelRecording()
                    }
                }

                Button("解除") {
                    recorder.clear()
                }
                .disabled(recorder.isRecording || recorder.currentConfiguration == nil)
            }

            if recorder.isRecording {
                Text("⌘ ⌥ ⇧ ⌃ を含むキーを押してください。Esc でキャンセルします。")
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = recorder.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460)
        .onAppear { recorder.refresh() }
        .onDisappear { recorder.cancelRecording() }
    }
}

@MainActor
private final class HotkeyRecorderModel: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var currentConfiguration: HotkeyConfiguration?
    @Published private(set) var errorMessage: String?

    private var eventMonitor: Any?
    private var windowCloseObserver: (any NSObjectProtocol)?

    var assignmentDisplay: String {
        guard let currentConfiguration else { return "未割り当て" }
        return hotkeyDisplayString(
            modifierFlags: currentConfiguration.modifierFlags,
            keyCode: currentConfiguration.keyCode
        )
    }

    func refresh() {
        guard let manager = HotkeyManager.shared else {
            errorMessage = "ホットキー管理を利用できません。"
            return
        }
        currentConfiguration = manager.currentConfiguration
    }

    func startRecording() {
        stopMonitoring()
        errorMessage = nil
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }

        if eventMonitor == nil {
            isRecording = false
            errorMessage = "ショートカットの記録を開始できませんでした。"
            return
        }

        // Settings ウィンドウは閉じても onDisappear が呼ばれないことがあるため、
        // ウィンドウクローズで確実にモニタを解除する（キー入力の握り潰しを残さない）。
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelRecording() }
        }
    }

    func cancelRecording() {
        stopMonitoring()
    }

    func clear() {
        stopMonitoring()
        guard let manager = HotkeyManager.shared else {
            errorMessage = "ホットキー管理を利用できません。"
            return
        }
        _ = manager.assign(nil)
        currentConfiguration = nil
        errorMessage = nil
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 53 {
            stopMonitoring()
            return nil
        }

        let supportedFlags = Int(event.modifierFlags.rawValue) & (
            HotkeyModifiers.nsCommand
                | HotkeyModifiers.nsOption
                | HotkeyModifiers.nsShift
                | HotkeyModifiers.nsControl
        )
        guard supportedFlags != 0 else {
            errorMessage = "⌘ ⌥ ⇧ ⌃ のいずれかの修飾キーを含めてください。"
            return nil
        }

        let configuration = HotkeyConfiguration(
            keyCode: Int(event.keyCode),
            modifierFlags: supportedFlags
        )
        guard let manager = HotkeyManager.shared else {
            stopMonitoring()
            errorMessage = "ホットキー管理を利用できません。"
            return nil
        }

        guard manager.assign(configuration) else {
            stopMonitoring()
            errorMessage = "このショートカットは登録できませんでした。他のアプリが使用している可能性があります。"
            return nil
        }

        currentConfiguration = configuration
        errorMessage = nil
        stopMonitoring()
        return nil
    }

    private func stopMonitoring() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        if let windowCloseObserver {
            NotificationCenter.default.removeObserver(windowCloseObserver)
            self.windowCloseObserver = nil
        }
        isRecording = false
    }

    isolated deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }
}
