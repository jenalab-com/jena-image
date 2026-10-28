import AppKit

final class AIConnectionViewController: NSViewController {
    let pathField = NSTextField()
    let statusLabel = NSTextField(wrappingLabelWithString: "CLI 연결을 확인해 주세요.")
    let accountLabel = NSTextField(wrappingLabelWithString: "")
    private(set) var installButton: NSButton!
    private(set) var loginButton: NSButton!
    private(set) var checkButton: NSButton!
    private var probe: AIConnectionService?
    private var generation = UUID()
    private let settings: AppSettings
    var checkConnection: ((String) async -> AIConnectionStatus)?
    var openTerminal: (Bool, URL?, @escaping (Error?) -> Void) -> Void = AICLITerminal.open
    private(set) var connection: AIConnectionStatus?

    init(settings: AppSettings = .shared) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView()
        let title = NSTextField(labelWithString: "Codex CLI 연결")
        title.font = .boldSystemFont(ofSize: 14)
        pathField.stringValue = settings.aiExecutable
        pathField.placeholderString = "codex 또는 실행 파일의 절대 경로"
        pathField.setAccessibilityLabel("CLI 실행 파일")
        pathField.target = self
        pathField.action = #selector(recheck)
        pathField.delegate = self
        installButton = NSButton(title: "설치", target: self, action: #selector(install))
        loginButton = NSButton(title: "로그인", target: self, action: #selector(login))
        checkButton = NSButton(title: "재확인", target: self, action: #selector(recheck))
        let actions = NSStackView(views: [installButton, loginButton, checkButton])
        actions.spacing = 8
        accountLabel.isSelectable = true
        accountLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        let help = NSTextField(wrappingLabelWithString: "설치·로그인은 터미널에서 진행합니다. 완료 후 재확인을 눌러 주세요. 계정 확인은 이미지 생성을 실행하지 않습니다.")
        help.font = .systemFont(ofSize: 11)
        help.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, NSTextField(labelWithString: "CLI 실행 파일"), pathField,
                                       actions, accountLabel, statusLabel, help])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
        for row in [pathField, accountLabel, statusLabel, help] {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        installButton.isHidden = true
        loginButton.isHidden = true
    }

    override func viewDidDisappear() { super.viewDidDisappear(); stopChecking() }
    func stopChecking() { probe?.cancel(); generation = UUID() }
    deinit { probe?.cancel() }

    @objc func recheck() {
        _ = view
        probe?.cancel()
        let token = UUID()
        generation = token
        let path = pathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.aiExecutable = path.isEmpty ? "codex" : path
        pathField.stringValue = settings.aiExecutable
        connection = nil
        accountLabel.stringValue = ""
        statusLabel.stringValue = "CLI와 로그인 상태 확인 중…"
        installButton.isHidden = true
        loginButton.isHidden = true
        checkButton.isEnabled = false
        let service = AIConnectionService()
        probe = service
        // A replaceable check keeps fixture accounts and real credentials separate in UI tests.
        let check = checkConnection
        Task { @MainActor [weak self] in
            let executablePath = path.isEmpty ? "codex" : path
            let result: AIConnectionStatus
            if let check { result = await check(executablePath) }
            else { result = await service.check(path: executablePath) }
            guard let self, self.generation == token else { return }
            self.apply(result)
            self.probe = nil
        }
    }

    func apply(_ result: AIConnectionStatus) {
        connection = result
        checkButton.isEnabled = true
        installButton.isHidden = result.state != .missing
        loginButton.isHidden = result.state != .signedOut && result.state != .failed
        loginButton.isEnabled = result.executable != nil
        accountLabel.stringValue = result.account ?? ""
        statusLabel.stringValue = result.detail
        statusLabel.toolTip = result.executable?.path
    }

    @objc private func install() { openTerminal(true, nil, terminalFinished) }
    @objc private func login() {
        guard let executable = connection?.executable else { return }
        openTerminal(false, executable, terminalFinished)
    }
    private func terminalFinished(_ error: Error?) {
        statusLabel.stringValue = error?.localizedDescription ?? "터미널에서 완료한 뒤 재확인을 눌러 주세요."
    }
}

extension AIConnectionViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        probe?.cancel()
        generation = UUID()
        connection = nil
        settings.aiExecutable = pathField.stringValue
        accountLabel.stringValue = ""
        statusLabel.stringValue = "변경한 경로로 재확인해 주세요."
        installButton.isHidden = true
        loginButton.isHidden = true
        checkButton.isEnabled = true
    }
}

enum AICLITerminal {
    static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    static func script(install: Bool, executable: URL?) throws -> String {
        let command: String
        if install { command = "curl -fsSL https://chatgpt.com/codex/install.sh | sh" }
        else {
            guard let executable else { throw AIImageGenerationError(message: "CLI를 찾을 수 없습니다. 재확인해 주세요.") }
            command = quote(executable.path) + " login"
        }
        return """
        #!/bin/zsh -l
        set -o pipefail
        export PATH=\(quote(AIExecutableLocator.searchDirectories.joined(separator: ":"))):"$PATH"
        \(command)
        jena_cli_status=$?
        if [ "$jena_cli_status" -eq 0 ]; then
            echo '완료되었습니다. JenaImage 설정에서 재확인을 눌러 주세요.'
        else
            echo '완료하지 못했습니다. 위 오류를 확인한 뒤 다시 시도해 주세요.'
        fi
        exit "$jena_cli_status"
        """
    }

    static func open(install: Bool, executable: URL?, completion: @escaping (Error?) -> Void) {
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("JenaImage-Setup-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let url = directory.appendingPathComponent(install ? "Install-Codex.command" : "Login-Codex.command")
            try script(install: install, executable: executable).write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                                    configuration: .init()) { _, error in
                DispatchQueue.main.async { completion(error) }
            }
        } catch { completion(error) }
    }
}
