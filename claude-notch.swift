// claude-notch: a Dynamic-Island-style panel at the MacBook notch that tells you when Claude Code is
// done, needs you, or is blocked. It only reads the small event files written by claude-notch-hook
// into ~/.claude-notch/ (state + project name). No network, no listener, no transcripts.
// Build: swiftc -O claude-notch.swift -o ~/.local/bin/claude-notch
// Mute sounds: touch ~/.claude-notch/mute
import SwiftUI
import AppKit

enum Kind: String {
    case done, input, blocked
    var emoji: String { switch self { case .done: return "👋"; case .input: return "🙋"; case .blocked: return "🚧" } }
    var title: String { switch self { case .done: return "All done"; case .input: return "Needs your input"; case .blocked: return "Blocked" } }
    var tint: Color { switch self { case .done: return .green; case .input: return .orange; case .blocked: return .red } }
    var sound: String { switch self { case .done: return "Glass"; case .input: return "Ping"; case .blocked: return "Basso" } }
    var hold: Double { self == .done ? 7 : 45 }  // done fades by itself; the others wait for you
    func subtitle(_ p: String) -> String {
        switch self {
        case .done: return "\(p) · come and take a look"
        case .input: return "\(p) is waiting for you"
        case .blocked: return "\(p) hit a limit or an error"
        }
    }
}

/// One Claude Code session: its last state and where its terminal is, so a click can bring that terminal forward.
struct Session: Identifiable {
    let id: String
    var project: String
    var kind: Kind
    var tty: String, bundle: String
    var pid: Int32
    var ts: Double
}

final class Model: ObservableObject {
    @Published var rows: [Session] = []
    @Published var expanded = false
    @Published var wave = false
    var onTap: () -> Void = {}
    var onRow: (Session) -> Void = { _ in }
}

/// Pixel-art robot in the Claude Code mascot's style (orange block body, square eyes, little legs), drawn on a 14x11 grid.
struct Robot: View {
    let kind: Kind
    let orange = Color(red: 0.85, green: 0.47, blue: 0.34)
    let dark = Color(red: 0.10, green: 0.08, blue: 0.08)
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.3)) { tl in
            let t = Int(tl.date.timeIntervalSinceReferenceDate / 0.3)
            Canvas { ctx, size in
                let u = size.width / 14
                func px(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: Color) {
                    ctx.fill(Path(CGRect(x: CGFloat(x) * u, y: CGFloat(y) * u, width: CGFloat(w) * u, height: CGFloat(h) * u)), with: .color(c))
                }
                let ox = kind == .blocked ? (t % 2 == 0 ? -1 : 1) : 0  // blocked: shakes
                let oy = kind == .done && t % 2 == 1 ? 1 : 0            // done: bounces
                px(3 + ox, 3 + oy, 8, 5, orange)                         // body
                for x in [4, 6, 8, 10] { px(x + ox, 8 + oy, 1, 2, orange) }  // legs
                if kind == .blocked {
                    px(4 + ox, 5, 2, 1, dark); px(8 + ox, 5, 2, 1, dark)       // tired flat eyes
                } else {
                    px(5 + ox, 4 + oy, 1, 2, dark); px(8 + ox, 4 + oy, 1, 2, dark)
                }
                func armUp(_ x: Int, _ flip: Bool, _ left: Bool) {  // stem beside the body, hand swinging out and back
                    px(x + ox, 3 + oy, 1, 3, orange)
                    let hx = left ? (flip ? x - 1 : x) : (flip ? x : x - 1)  // the hand always overlaps the stem column
                    px(hx + ox, 1 + oy, 2, 2, orange)
                }
                switch kind {
                case .done:
                    px(1 + ox, 5 + oy, 2, 2, orange); armUp(11, t % 2 == 1, false)
                case .input:
                    armUp(2, t % 2 == 0, true); armUp(11, t % 2 == 1, false)
                case .blocked:
                    px(1 + ox, 6, 2, 2, orange); px(11 + ox, 6, 2, 2, orange)
                }
            }
        }
        .frame(width: 49, height: 38)
    }
}

struct IslandView: View {
    @ObservedObject var m: Model
    let notchW: CGFloat, notchH: CGFloat
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26).fill(Color.black)
                if m.expanded {
                    VStack(spacing: 6) {
                        ForEach(m.rows) { r in
                            HStack(spacing: 12) {
                                Robot(kind: r.kind)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.kind.title).font(.system(size: 15, weight: .semibold)).foregroundColor(r.kind.tint)
                                    Text(r.kind.subtitle(r.project)).font(.system(size: 12)).foregroundColor(.white.opacity(0.75)).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(height: 44).contentShape(Rectangle())
                            .onTapGesture { m.onRow(r) }
                        }
                    }
                    .padding(.horizontal, 24).padding(.bottom, 12)
                    .transition(.opacity)
                }
            }
            .frame(width: m.expanded ? 380 : notchW, height: m.expanded ? notchH + 12 + CGFloat(max(m.rows.count, 1)) * 50 : notchH)
            .animation(.spring(response: 0.45, dampingFraction: 0.72), value: m.expanded)
            .onTapGesture { m.onTap() }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

final class App: NSObject, NSApplicationDelegate {
    let dir: URL = {
        if let r = ProcessInfo.processInfo.environment["CLAUDE_NOTCH_DIR"] { return URL(fileURLWithPath: r) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude-notch")
    }()
    let model = Model()
    var panel: NSPanel?
    var generation = 0
    var sessions: [String: Session] = [:]
    let terminals: Set<String> = ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
                                  "net.kovidgoyal.kitty", "org.alacritty", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92"]

    func applicationDidFinishLaunching(_ n: Notification) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        model.onTap = { [weak self] in self?.hide() }
        model.onRow = { [weak self] r in self?.tap(r) }
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in self.poll() }
    }

    func screen() -> NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    func notchSize(_ s: NSScreen) -> (CGFloat, CGFloat) {
        let h = s.safeAreaInsets.top
        if h > 0, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea { return (s.frame.width - l.width - r.width, h) }
        return (130, 28)  // no notch: a small pill at the top centre
    }

    func poll() {
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix(".") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var latest: [String: Any]?
        for f in files {
            if let d = try? Data(contentsOf: f), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let ts = o["ts"] as? Double, Date().timeIntervalSince1970 - ts < 90 { latest = o }
            try? FileManager.default.removeItem(at: f)
        }
        // a session whose claude process is gone (closed terminal, crash) no longer waits for anyone
        sessions = sessions.filter { $0.value.pid <= 0 || kill($0.value.pid, 0) == 0 || errno != ESRCH }
        guard let e = latest, let sid = e["sid"] as? String, !sid.isEmpty else { return }
        if e["state"] as? String == "end" { sessions[sid] = nil; return }
        guard let kind = Kind(rawValue: e["state"] as? String ?? "") else { return }
        let s = Session(id: sid, project: e["project"] as? String ?? "session", kind: kind, tty: e["tty"] as? String ?? "",
                        bundle: e["bundle"] as? String ?? "", pid: Int32(e["pid"] as? Int ?? 0), ts: e["ts"] as? Double ?? 0)
        sessions[sid] = s
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        // "done" while you are already looking at the terminal needs no banner; needs-input and blocked always show
        if kind == .done, terminals.contains(front), (e["force"] as? Bool) != true { return }
        // this event first, then the other sessions that are still waiting on you
        let waiting = sessions.values.filter { $0.id != sid && $0.kind != .done }.sorted { $0.ts > $1.ts }
        show(Array(([s] + waiting).prefix(3)), sound: kind)
    }

    /// Bring the session's terminal forward: the exact tab in Terminal and iTerm2 (matched by tty), the app for the rest.
    func focus(_ s: Session) {
        let ok = s.tty.range(of: #"^ttys\d+$"#, options: .regularExpression) != nil  // tty goes into a script: only a plain tty name
        var script: String?
        if ok && s.bundle == "com.apple.Terminal" {
            script = """
            tell application "Terminal"
              repeat with w in windows
                repeat with t in tabs of w
                  if tty of t is "/dev/\(s.tty)" then
                    if miniaturized of w then set miniaturized of w to false
                    set selected tab of w to t
                    set index of w to 1
                    activate
                    return
                  end if
                end repeat
              end repeat
            end tell
            """
        } else if ok && s.bundle == "com.googlecode.iterm2" {
            script = """
            tell application "iTerm2"
              repeat with w in windows
                repeat with t in tabs of w
                  repeat with x in sessions of t
                    if tty of x is "/dev/\(s.tty)" then
                      select w
                      tell w to select t
                      tell t to select x
                      activate
                      return
                    end if
                  end repeat
                end repeat
              end repeat
            end tell
            """
        }
        var err: NSDictionary?
        if let script = script, NSAppleScript(source: script)?.executeAndReturnError(&err) != nil { return }
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == s.bundle }?.activate()
    }

    func tap(_ s: Session) {
        focus(s)
        if s.kind != .done { sessions[s.id] = nil }  // you went to it; the next event puts it back if it still needs you
        let rest = model.rows.filter { $0.id != s.id }
        if rest.isEmpty { hide() } else { model.rows = rest; layout() }
    }

    func layout() {
        let s = screen(), (_, nh) = notchSize(s)
        let w: CGFloat = 420, h: CGFloat = nh + 24 + CGFloat(max(model.rows.count, 1)) * 50
        panel?.setFrame(NSRect(x: s.frame.midX - w / 2, y: s.frame.maxY - h, width: w, height: h), display: true)
    }

    func show(_ rows: [Session], sound kind: Kind) {
        generation += 1
        let gen = generation
        let s = screen(), (nw, nh) = notchSize(s)
        if panel == nil {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .statusBar
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel = p
        }
        panel!.contentView = NSHostingView(rootView: IslandView(m: model, notchW: nw, notchH: nh))
        model.rows = rows
        layout()
        model.wave = false
        panel!.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.model.expanded = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.model.wave = true }
        if !FileManager.default.fileExists(atPath: dir.appendingPathComponent("mute").path) { NSSound(named: kind.sound)?.play() }
        DispatchQueue.main.asyncAfter(deadline: .now() + kind.hold) { if gen == self.generation { self.hide() } }
    }

    func hide() {
        generation += 1
        model.expanded = false
        model.wave = false
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { if gen == self.generation { self.panel?.orderOut(nil) } }
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
