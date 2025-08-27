import SwiftUI
import AVFoundation
import WebKit

#if os(macOS)
import AppKit
#endif
enum Janken: String, CaseIterable, Identifiable {
    public var id: String { rawValue }
    case gu = "グー"
    case choki = "チョキ"
    case pa = "パー"
}

enum Direction: String, CaseIterable {
    case left = "左"
    case right = "右"
    case up = "上"
    case down = "下"
}

final class GameLogic: ObservableObject {
    @Published var statusText: String = "じゃんけんをしてください"
    @Published var playerHand: Janken? = nil
    @Published var cpuHand: Janken? = nil
    @Published var playerDirection: Direction? = nil
    @Published var cpuDirection: Direction? = nil
    // Preselected CPU direction decided after janken but not revealed until the player points
    private var preselectedCpuDirection: Direction? = nil
    @Published var phase: Phase = .janken
    // Prevent double-choices / button mashing
    @Published var isLocked: Bool = false
    // Cumulative scores
    @Published var playerScore: Int = 0
    @Published var cpuScore: Int = 0

    enum Phase { case janken, pointing, deciding }

    enum JankenWinner { case player, cpu }
    // Remember who won the last janken to decide who is pointing
    private var lastJankenWinner: JankenWinner? = nil

    func playJanken(player: Janken) {
        guard !isLocked else { return }
        isLocked = true

        // Determine both choices together to avoid any ordering/after-the-fact change
        let cpu = Janken.allCases.randomElement()!
        playerHand = player
        cpuHand = cpu

        if playerHand == cpuHand {
            statusText = "あいこ！もう一度"
            isLocked = false
            phase = .janken
            return
        }

        let playerWins = (playerHand == .gu && cpuHand == .choki) || (playerHand == .choki && cpuHand == .pa) || (playerHand == .pa && cpuHand == .gu)
        // Decide who will be the pointer in the upcoming あっちむいてほい round.
        statusText = playerWins ? "あなたが指差す番です。指して！" : "CPUが指差す番です。首を向けて！"
        lastJankenWinner = playerWins ? .player : .cpu

        // Preselect CPU pointing direction now, but do not publish it yet.
        preselectedCpuDirection = Direction.allCases.randomElement()!
        cpuDirection = nil

        // Wait a moment after the janken result before showing the pointing phase
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self = self else { return }
            self.phase = .pointing
            // speak will be triggered by the view's onChange(of: phase)
            self.isLocked = false
        }
    }

    func chooseDirection(_ dir: Direction) {
        guard !isLocked else { return }
        isLocked = true

        // Reveal CPU direction using the preselection if present
        let cpu = preselectedCpuDirection ?? Direction.allCases.randomElement()!
        playerDirection = dir
        self.cpuDirection = cpu
        self.preselectedCpuDirection = nil

        // Delay the scoring so animations and chant can complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self = self else { return }

            if let winner = self.lastJankenWinner {
                switch winner {
                case .player:
                    if self.playerDirection == self.cpuDirection {
                        self.playerScore += 1
                        self.statusText = "あなたの勝ち！"
                    } else {
                        self.statusText = "勝負はつかなかった..."
                    }
                case .cpu:
                    if self.playerDirection == self.cpuDirection {
                        self.cpuScore += 1
                        self.statusText = "あなたの負け..."
                    } else {
                        self.statusText = "勝負はつかなかった..."
                    }
                }
            } else {
                if self.playerDirection == self.cpuDirection {
                    self.playerScore += 1
                    self.statusText = "あなたの勝ち！"
                } else {
                    self.statusText = "勝負はつかなかった..."
                }
            }

            self.lastJankenWinner = nil
            self.phase = .deciding
            self.isLocked = false
        }
    }

    func resetForNextRound() {
        playerHand = nil; cpuHand = nil; playerDirection = nil; cpuDirection = nil; preselectedCpuDirection = nil; phase = .janken; statusText = "じゃんけんをしてください"
    }

    func resetScores() {
        playerScore = 0
        cpuScore = 0
    }
}

struct ContentView: View {
    @StateObject private var game = GameLogic()
    @State private var headRotation: Double = 0
    @State private var headYOffset: CGFloat = 0
    @State private var fingerOffsetX: CGFloat = 0
    @State private var fingerOffsetY: CGFloat = 0
    @State private var showConfetti: Bool = false
    // Subtle breathing/idle animation state for raster character
    @State private var breathe: Bool = false

    // TTSQueue ensures a minimum pause between successive utterances.
    @MainActor
    private class TTSQueue: NSObject, AVSpeechSynthesizerDelegate {
        let synthesizer = AVSpeechSynthesizer()
        private var queue: [AVSpeechUtterance] = []
        /// gap between utterances in seconds
        var gap: TimeInterval = 1.0

        override init() {
            super.init()
            synthesizer.delegate = self
        }

        func enqueue(text: String, voiceIdentifier: String?, rate: Float, pitch: Float) {
            let utterance = AVSpeechUtterance(string: text)
            if let id = voiceIdentifier, !id.isEmpty {
                if id == "pretty_girl" {
                    // keep default voice selection but ensure Japanese if available
                    utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP") ?? AVSpeechSynthesisVoice.speechVoices().first
                } else if let v = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.identifier == id }) {
                    utterance.voice = v
                } else {
                    utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP") ?? AVSpeechSynthesisVoice.speechVoices().first
                }
            } else {
                utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP") ?? AVSpeechSynthesisVoice.speechVoices().first
            }
            utterance.rate = rate
            utterance.pitchMultiplier = pitch

            queue.append(utterance)
            if !synthesizer.isSpeaking && !synthesizer.isPaused {
                speakNext()
            }
        }

        func clearAndInterrupt() {
            queue.removeAll()
            synthesizer.stopSpeaking(at: .immediate)
        }

        private func speakNext() {
            guard !queue.isEmpty else { return }
            let u = queue.removeFirst()
            synthesizer.speak(u)
        }

        nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            Task { @MainActor in
                // Safely read the main-isolated gap value and await before proceeding
                let g = gap
                let ns = UInt64((g) * 1_000_000_000)
                if ns > 0 { await Task.sleep(ns) }
                self.speakNext()
            }
        }
    }

    private let tts = TTSQueue()
    @State private var showTTSSettings: Bool = false
    @State private var availableVoiceOptions: [String] = []
    @AppStorage("tts.selectedVoiceIdentifier") private var selectedVoiceIdentifier: String = ""
    @AppStorage("tts.rate") private var ttsRate: Double = 0.40
    @AppStorage("tts.pitch") private var ttsPitch: Double = 1.0
    @AppStorage("tts.previewText") private var previewText: String = "こんにちは。テストです。"

#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    var body: some View {
        Group { contentLayout() }
            .onAppear {
                populateVoicesIfNeeded()
                // kick off idle breathing animation for raster images
                DispatchQueue.main.async { breathe = true }
            }
            .onChange(of: game.cpuDirection) { newDir in
                guard let d = newDir else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    switch d {
                    case .left:
                        headRotation = -30; headYOffset = 0
                    case .right:
                        headRotation = 30; headYOffset = 0
                    case .up:
                        headRotation = 0; headYOffset = -18
                    case .down:
                        headRotation = 0; headYOffset = 18
                    }
                }
            }
            .onChange(of: game.phase) { p in
                if p == .pointing {
                    // Entering pointing phase: ensure the CPU's visible direction is cleared
                    // and head is neutral until the player actually points.
                    withAnimation { headRotation = 0; headYOffset = 0 }
                    game.cpuDirection = nil
                    // Speak the chant after a short pause so the user has time to register the result
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if game.phase == .pointing { speak("あっちむいてほい") }
                    }
                }
                else if p == .deciding {
                    if game.statusText.contains("勝ち") {
                        // Slightly longer delay before the celebratory message so animation and pointing settle
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            // Temporarily stop subtle breathing and pulse on win
                            breathe = false
                            speak("おめでとう、あなたの勝ちです")
                            withAnimation {
                                showConfetti = true
                            }
                            // After confetti, hide and resume breathing
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                withAnimation { showConfetti = false }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { breathe = true }
                            }
                        }
                    } else if game.statusText.contains("負け") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { speak("残念、あなたの負けです") }
                    }
                }
            }
    }

    /// Return the preferred CPU character SVG name. If a `cpu_female.svg` exists in Resources,
    /// prefer that; otherwise fall back to `cpu.svg`.
    private func cpuCharacterName() -> String {
        // Try both the 'Resources' subdirectory (if project kept that) and the bundle root
        if Bundle.main.path(forResource: "cpu_female", ofType: "svg", inDirectory: "Resources") != nil {
            return "cpu_female"
        }
        if Bundle.main.path(forResource: "cpu_female", ofType: "svg") != nil {
            return "cpu_female"
        }
        return "cpu"
    }
    @ViewBuilder
    private func contentLayout() -> some View {
#if os(iOS)
        let isiPhone = UIDevice.current.userInterfaceIdiom == .phone
        if isiPhone || horizontalSizeClass == .compact {
            ScrollView { VStack(spacing: 20) { gameMainView(); ttsPanelCompact() }.padding() }
        } else {
            HStack(alignment: .top, spacing: 20) { gameMainView(); ttsPanelWide() }.padding()
        }
#else
        HStack(alignment: .top, spacing: 20) { gameMainView(); ttsPanelWide(isMac: true) }.padding()
#endif
    }

    private func ttsPanelWide(isMac: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer()
            // Score is placed lower in the panel, directly above the settings header
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("あなた").font(.caption)
                    Text("\(game.playerScore)").font(.title2).bold()
                }
                Divider().frame(height: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text("CPU").font(.caption2)
                    Text("\(game.cpuScore)").font(.headline).bold()
                }
            }
            Text("設定").font(.headline)
            ttsSettingsView()
            Spacer()
        }
        .frame(width: 320)
        .padding()
#if os(macOS)
        .background(Color(NSColor.windowBackgroundColor))
#else
        .background(Color(.secondarySystemBackground))
#endif
        .cornerRadius(12)
    }

    @ViewBuilder
    func ttsPanelCompact() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer()
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("あなた").font(.caption)
                    HStack(spacing: 6) {
                        Button(action: {
                            game.resetForNextRound(); game.resetScores(); withAnimation { headRotation = 0; fingerOffsetX = 0; fingerOffsetY = 0; showConfetti = false }
                            speak("スコアをリセットしました。じゃんけんをしてください")
                        }) {
                            Image(systemName: "arrow.counterclockwise.circle")
                        }
                        .buttonStyle(.plain)
                        .imageScale(.large)
                        .accessibilityLabel("スコアをリセット")

                        Text("\(game.playerScore)").font(.title2).bold()
                    }
                }
                Divider().frame(height: 28)
                VStack(alignment: .leading, spacing: 6) {
                    Text("CPU").font(.caption)
                    Text("\(game.cpuScore)").font(.title2).bold()
                }
                Spacer()
                Button(action: {
                    game.resetForNextRound(); game.resetScores(); withAnimation { headRotation = 0; fingerOffsetX = 0; fingerOffsetY = 0; showConfetti = false }
                    speak("スコアをリセットしました。じゃんけんをしてください")
                }) {
                    Image(systemName: "arrow.counterclockwise.circle")
                }
                .buttonStyle(.plain)
                .imageScale(.medium)
                .accessibilityLabel("スコアをリセット")
            }
            Spacer().frame(height: 8)
            Text("設定").font(.headline)
            ttsSettingsView()
            Spacer()
        }
        .padding()
        #if os(macOS)
        .background(Color(NSColor.windowBackgroundColor))
        #else
        .background(Color(.secondarySystemBackground))
        #endif
        .cornerRadius(12)
    }

    func populateVoicesIfNeeded() {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let jaVoices = voices.filter { $0.language == "ja-JP" }
        availableVoiceOptions = jaVoices.isEmpty ? voices.map { "\($0.identifier)|\($0.name) (\($0.language))" } : jaVoices.map { "\($0.identifier)|\($0.name)" }
        // Insert synthetic "Pretty Girl" option at the top of the picker list
        availableVoiceOptions.insert("pretty_girl|Pretty Girl", at: 0)
        if selectedVoiceIdentifier.isEmpty {
            if let female = jaVoices.first(where: { v in
                let id = v.identifier.lowercased(); let name = v.name.lowercased()
                return id.contains("female") || name.contains("female") || id.contains("siri") || name.contains("yuka") || name.contains("yui") || name.contains("haru") || name.contains("kyoko") || name.contains("sakura") || name.contains("ai")
            }) { selectedVoiceIdentifier = female.identifier }
            else if let first = jaVoices.first { selectedVoiceIdentifier = first.identifier }
            else if let any = AVSpeechSynthesisVoice(language: "ja-JP") { selectedVoiceIdentifier = any.identifier }
        }
    }

    /// Apply a preset that aims to sound like a "cute girl" voice.
    func applyCuteVoice() {
        // Keep for compatibility; selecting "Pretty Girl" from the picker will apply the same logic
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let keywords = ["female","yui","yuka","kyoko","sakura","ai","haru","saki","yuri","mai","miku","nanami","akari","hina","yuna","mio","sora"]
        func matches(_ v: AVSpeechSynthesisVoice) -> Bool {
            guard v.language == "ja-JP" else { return false }
            let id = v.identifier.lowercased()
            let name = v.name.lowercased()
            for k in keywords { if id.contains(k) || name.contains(k) { return true } }
            return false
        }
        let candidates = voices.filter { matches($0) }
        let pick = candidates.first ?? voices.first(where: { $0.language == "ja-JP" }) ?? voices.first
        if let pick = pick {
            // Set presets and use the picked voice for preview. Do not overwrite the logical selection if user chose "Pretty Girl".
            selectedVoiceIdentifier = pick.identifier
            // Use a slightly slower rate to avoid sounding too fast
            ttsRate = 0.42
            ttsPitch = 1.35
            speak("こんにちは、ゆいです。可愛い声のテストをします。よろしくね。")
        }
    }

    @ViewBuilder
    func ttsSettingsView() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("TTS 設定を表示", isOn: $showTTSSettings)
            if showTTSSettings {
                GroupBox(label: Text("音声設定")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("声を選択:")
                        Picker(selection: $selectedVoiceIdentifier, label: Text("Voice")) {
                            ForEach(availableVoiceOptions, id: \.self) { entry in
                                let parts = entry.split(separator: "|")
                                let id = String(parts.first ?? "")
                                let label = parts.count > 1 ? String(parts[1]) : id
                                Text(label).tag(id)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .onChange(of: selectedVoiceIdentifier) { newValue in
                            if newValue == "pretty_girl" {
                                // Apply cute voice preset programmatically
                                // This will choose a good candidate and set rate/pitch
                                applyCuteVoice()
                            }
                        }

                        HStack { Text("速度"); Slider(value: $ttsRate, in: 0.3...0.7, step: 0.01); Text(String(format: "%.2f", ttsRate)).frame(width: 48, alignment: .trailing) }
                        HStack { Text("ピッチ"); Slider(value: $ttsPitch, in: 0.5...2.0, step: 0.01); Text(String(format: "%.2f", ttsPitch)).frame(width: 48, alignment: .trailing) }

                        VStack(alignment: .leading, spacing: 6) { Text("プレビューテキスト"); TextField("プレビュー文を入力", text: $previewText).textFieldStyle(.roundedBorder) }

                        HStack(spacing: 10) {
                            // The "Pretty Girl" option is now available in the picker; the separate button was removed to avoid duplication.
                            Button(action: {
                                // Debug: print available voices to console for inspection
                                let vs = AVSpeechSynthesisVoice.speechVoices()
                                for v in vs {
                                    print("VOICE: id=\(v.identifier) name=\(v.name) lang=\(v.language)")
                                }
                            }) { Text("ボイス一覧を出力") }.buttonStyle(.bordered)
                            Spacer()
                            Button(action: { speak(previewText) }) { Label("プレビュー再生", systemImage: "play.fill") }.buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(.top, 8)
    }

    func performAfterPointing() {
        // Allow a short moment for the pointing animation/chant to play, then reset head/finger if no decision reached
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if game.phase != .deciding {
                withAnimation { headRotation = 0; headYOffset = 0; fingerOffsetX = 0; fingerOffsetY = 0 }
            }
        }
    }

    func speak(_ text: String) {
        // Route all speak requests through the TTS queue so there's a consistent gap between narrations.
        tts.enqueue(text: text, voiceIdentifier: selectedVoiceIdentifier, rate: Float(ttsRate), pitch: Float(ttsPitch))
    }

    func symbolForHand(_ hand: Janken?) -> String {
        func symbolName(for h: Janken) -> String {
            switch h { case .gu: return "hand.rock.fill"; case .choki: return "hand.scissors.fill"; case .pa: return "hand.paper.fill" }
        }
        if let h = hand {
            #if os(macOS)
            let name = symbolName(for: h)
            if #available(macOS 11.0, *) {
                if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil { return name }
                switch h { case .gu: return "✊"; case .choki: return "✌️"; case .pa: return "🖐️" }
            } else {
                switch h { case .gu: return "✊"; case .choki: return "✌️"; case .pa: return "🖐️" }
            }
            #else
            return symbolName(for: h)
            #endif
        }
        return "hand.raised.fill"
    }

    @ViewBuilder
    func gameMainView() -> some View {
        VStack(spacing: 20) {
            // Top bar left intentionally empty; reset button moved next to scores in the settings panel
            Text(game.statusText).font(.title2).bold().multilineTextAlignment(.center)

            let playerView = VStack(spacing: 12) {
                Text("あなた").font(.headline)
                if game.phase != .pointing {
                    Image(systemName: symbolForHand(game.playerHand)).resizable().scaledToFit().frame(width: 80, height: 80)
#if os(iOS)
                    .foregroundStyle(.blue)
#else
                    .foregroundColor(.blue)
#endif
                    Text(game.playerHand?.rawValue ?? "-")
                } else {
                    // Keep layout stable while hiding the hand during pointing phase
                    Rectangle().fill(Color.clear).frame(width: 80, height: 80)
                }
            }

            let cpuView = VStack(spacing: 12) {
                Text("CPU").font(.headline)
                ZStack {
                    Group {
                        // Prefer raster asset if provided in Assets.xcassets or Resources
                        if UIImage(named: "cpu_female") != nil || Bundle.main.path(forResource: "cpu_female", ofType: "png") != nil {
                            Image("cpu_female")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 120, height: 120)
                                // idle breathing combined with win pulse
                                .scaleEffect((showConfetti ? 1.15 : 1.0) * (breathe ? 1.02 : 0.98))
                                .offset(x: fingerOffsetX / 8, y: headYOffset + (breathe ? -4 : 0))
                                .rotationEffect(.degrees(headRotation), anchor: .center)
                                .animation(.interpolatingSpring(stiffness: 200, damping: 8), value: headRotation)
                                .animation(Animation.easeInOut(duration: 3.6).repeatForever(autoreverses: true), value: breathe)
                                .animation(.spring(), value: showConfetti)
                        } else if UIImage(named: "cpu") != nil || Bundle.main.path(forResource: "cpu", ofType: "png") != nil {
                            Image("cpu")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 120, height: 120)
                                .scaleEffect((showConfetti ? 1.15 : 1.0) * (breathe ? 1.02 : 0.98))
                                .offset(x: fingerOffsetX / 8, y: headYOffset + (breathe ? -4 : 0))
                                .rotationEffect(.degrees(headRotation), anchor: .center)
                                .animation(.interpolatingSpring(stiffness: 200, damping: 8), value: headRotation)
                                .animation(Animation.easeInOut(duration: 3.6).repeatForever(autoreverses: true), value: breathe)
                                .animation(.spring(), value: showConfetti)
                        } else {
                            SVGWebView(name: cpuCharacterName(), width: 120, height: 120, triggerWin: showConfetti)
                                .frame(width: 120, height: 120)
                                .scaleEffect(showConfetti ? 1.12 : 1.0)
                                .offset(x: fingerOffsetX / 8, y: headYOffset)
                                .rotationEffect(.degrees(headRotation), anchor: .center)
                                .animation(.interpolatingSpring(stiffness: 200, damping: 8), value: headRotation)
                                .animation(.spring(), value: showConfetti)
                        }
                    }

                    // CPU finger overlay removed per UX request.

                    // Show the CPU's chosen direction as a label when it's revealed
                    if let dir = game.cpuDirection {
                        VStack {
                            Text(dir.rawValue)
                                .font(.title)
                                .bold()
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .cornerRadius(8)
                                .shadow(radius: 4)
                                .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
                            Spacer()
                        }
                        .frame(width: 120, height: 120)
                        .animation(.easeOut(duration: 0.25), value: game.cpuDirection)
                    }
                }
                if game.phase != .pointing {
                    Text(game.cpuHand?.rawValue ?? "-")
                } else {
                    // Maintain spacing so layout doesn't jump
                    Text("")
                        .frame(height: 18)
                }
            }

            HStack(alignment: .center, spacing: 40) { playerView; cpuView }

            if game.phase == .janken {
                HStack(spacing: 16) {
                    ForEach(Janken.allCases) { hand in
                        Button(action: {
                            // Chant: speak first phrase, wait 2s, then speak punchline and evaluate
                            speak("最初はグー")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                speak("じゃんけんぽん")
                                // small buffer then evaluate
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                        game.playJanken(player: hand)
                                        // If tie, announce and reset to janken
                                        if game.playerHand == game.cpuHand {
                                            // small delay to avoid cutting off the previous utterance
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                                speak("あいこでしょ")
                                                game.phase = .janken
                                                game.statusText = "あいこ！もう一度"
                                            }
                                        } else {
                                            // Do not speak the specific hand after じゃんけんぽん — keep only the chant.
                                        }
                                        withAnimation(.spring()) { fingerOffsetX = 0; fingerOffsetY = 0 }
                                    }
                            }
                        }) {
                            VStack { Text(hand.rawValue).font(.title2).bold(); Text(emojiForJanken(hand)).font(.largeTitle) }
                                .padding().frame(minWidth: 90).background(.ultraThinMaterial).cornerRadius(12).shadow(radius: 4)
                        }
                        .disabled(game.isLocked)
                    }
                }
            } else if game.phase == .pointing {
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        Button(action: { withAnimation { fingerOffsetX = 0; fingerOffsetY = -48 }; game.chooseDirection(.up); performAfterPointing() }) {
                            Text("↑ 上").font(.title3).padding().frame(minWidth: 120).background(Color.green.opacity(0.2)).cornerRadius(10)
                        }
                        .disabled(game.isLocked)
                        Button(action: { withAnimation { fingerOffsetX = -48; fingerOffsetY = 0 }; game.chooseDirection(.left); performAfterPointing() }) {
                            Text("← 左").font(.title3).padding().frame(minWidth: 120).background(Color.green.opacity(0.2)).cornerRadius(10)
                        }
                        .disabled(game.isLocked)
                    }
                    HStack(spacing: 16) {
                        Button(action: { withAnimation { fingerOffsetX = 48; fingerOffsetY = 0 }; game.chooseDirection(.right); performAfterPointing() }) {
                            Text("右 →").font(.title3).padding().frame(minWidth: 120).background(Color.green.opacity(0.2)).cornerRadius(10)
                        }
                        .disabled(game.isLocked)
                        Button(action: { withAnimation { fingerOffsetX = 0; fingerOffsetY = 48 }; game.chooseDirection(.down); performAfterPointing() }) {
                            Text("↓ 下").font(.title3).padding().frame(minWidth: 120).background(Color.green.opacity(0.2)).cornerRadius(10)
                        }
                        .disabled(game.isLocked)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    if game.statusText.contains("勝ち") { Text("🎉").font(.largeTitle) }
                        Button("もう一度") {
                        game.resetForNextRound()
                        withAnimation { headRotation = 0; fingerOffsetX = 0; fingerOffsetY = 0; showConfetti = false }
                        speak("じゃんけんをしてください")
                    }
                    .padding().background(Color.orange.opacity(0.2)).cornerRadius(8)
                }
            }

            Spacer()
        }
    }

    func emojiForJanken(_ hand: Janken) -> String { switch hand { case .gu: return "✊"; case .choki: return "✌️"; case .pa: return "🖐️" } }

}

struct ContentView_Previews: PreviewProvider { static var previews: some View { ContentView() } }

// MARK: - SVGWebView implementations
#if os(iOS)
// UIKit is already imported at file scope when needed; UIViewRepresentable implementation follows
struct SVGWebView: UIViewRepresentable {
    let name: String
    let width: CGFloat
    let height: CGFloat
    var triggerWin: Bool = false

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        load(svgInto: uiView)
        if triggerWin { uiView.evaluateJavaScript("triggerWin()", completionHandler: nil) }
    }

    private func load(svgInto uiView: WKWebView) {
        // Try Resources subdirectory first, then bundle root
        var filePath: String? = Bundle.main.path(forResource: name, ofType: "svg", inDirectory: "Resources")
        if filePath == nil { filePath = Bundle.main.path(forResource: name, ofType: "svg") }
        if let file = filePath {
            if let svg = try? String(contentsOfFile: file, encoding: .utf8) {
                let wrapped = makeWrappedHTML(with: svg)
                uiView.loadHTMLString(wrapped, baseURL: nil)
            }
        }
    }

    private func makeWrappedHTML(with svg: String) -> String {
        return """
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
                body { margin:0; padding:0; background:transparent; }
                #character { transform-origin: 100px 100px; animation: breath 3.6s ease-in-out infinite; }
                @keyframes breath { 0% { transform: translate(100px,100px) scale(0.98); } 50% { transform: translate(100px,100px) scale(1.02); } 100% { transform: translate(100px,100px) scale(0.98); } }
                .eye-closed { visibility: visible !important; }
                .eye-open { visibility: hidden !important; }
                #confetti { position: absolute; left:0; top:0; width:100%; height:100%; pointer-events:none; }
                .confetti-piece { position:absolute; width:8px; height:12px; opacity:0.9; transform-origin:center; }
            </style>
        </head>
        <body>
            \(svg)
            <div id="confetti"></div>
            <script>
                function blinkOnce() {
                    const l = document.getElementById('eye-left-closed');
                    const r = document.getElementById('eye-right-closed');
                    if (!l || !r) return;
                    l.style.visibility = 'visible'; r.style.visibility = 'visible';
                    setTimeout(()=>{ l.style.visibility='hidden'; r.style.visibility='hidden'; }, 160);
                }
                setInterval(()=>{ if (Math.random() < 0.35) blinkOnce(); }, 2400);

                window.triggerWin = function() {
                    const colors = ['#ff6fa0','#ffd166','#6fd3ff','#b1ffb8'];
                    const container = document.getElementById('confetti');
                    for(let i=0;i<20;i++){
                        const el = document.createElement('div');
                        el.className='confetti-piece';
                        el.style.background = colors[i%colors.length];
                        el.style.left = (50 + (Math.random()-0.5)*80) + '%';
                        el.style.top = '-10%';
                        el.style.transform = 'rotate('+ (Math.random()*360) +'deg)';
                        container.appendChild(el);
                        const fall = el.animate([
                            { transform: el.style.transform + ' translateY(0)', opacity:1 },
                            { transform: el.style.transform + ' translateY(140%) rotate(360deg)', opacity:0.9 }
                        ], { duration: 1400 + Math.random()*800, easing:'cubic-bezier(.2,.6,.2,1)' });
                        fall.onfinish = ()=>el.remove();
                    }
                }
            </script>
        </body>
        </html>
        """
    }
}

#elseif os(macOS)
// AppKit is already imported at file scope when needed; NSViewRepresentable implementation follows
struct SVGWebView: NSViewRepresentable {
    let name: String
    let width: CGFloat
    let height: CGFloat
    var triggerWin: Bool = false

    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero)
        web.setValue(false, forKey: "drawsBackground")
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        load(svgInto: nsView)
        if triggerWin { nsView.evaluateJavaScript("triggerWin()", completionHandler: nil) }
    }

    private func load(svgInto uiView: WKWebView) {
        // Try Resources subdirectory first, then bundle root
        var filePath: String? = Bundle.main.path(forResource: name, ofType: "svg", inDirectory: "Resources")
        if filePath == nil { filePath = Bundle.main.path(forResource: name, ofType: "svg") }
        if let file = filePath {
            if let svg = try? String(contentsOfFile: file, encoding: .utf8) {
                let wrapped = makeWrappedHTML(with: svg)
                uiView.loadHTMLString(wrapped, baseURL: nil)
            }
        }
    }

    private func makeWrappedHTML(with svg: String) -> String {
        return """
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
                body { margin:0; padding:0; background:transparent; }
                #character { transform-origin: 100px 100px; animation: breath 3.6s ease-in-out infinite; }
                @keyframes breath { 0% { transform: translate(100px,100px) scale(0.98); } 50% { transform: translate(100px,100px) scale(1.02); } 100% { transform: translate(100px,100px) scale(0.98); } }
                .eye-closed { visibility: visible !important; }
                .eye-open { visibility: hidden !important; }
                #confetti { position: absolute; left:0; top:0; width:100%; height:100%; pointer-events:none; }
                .confetti-piece { position:absolute; width:8px; height:12px; opacity:0.9; transform-origin:center; }
            </style>
        </head>
        <body>
            \(svg)
            <div id="confetti"></div>
            <script>
                function blinkOnce() {
                    const l = document.getElementById('eye-left-closed');
                    const r = document.getElementById('eye-right-closed');
                    if (!l || !r) return;
                    l.style.visibility = 'visible'; r.style.visibility = 'visible';
                    setTimeout(()=>{ l.style.visibility='hidden'; r.style.visibility='hidden'; }, 160);
                }
                setInterval(()=>{ if (Math.random() < 0.35) blinkOnce(); }, 2400);

                window.triggerWin = function() {
                    const colors = ['#ff6fa0','#ffd166','#6fd3ff','#b1ffb8'];
                    const container = document.getElementById('confetti');
                    for(let i=0;i<20;i++){
                        const el = document.createElement('div');
                        el.className='confetti-piece';
                        el.style.background = colors[i%colors.length];
                        el.style.left = (50 + (Math.random()-0.5)*80) + '%';
                        el.style.top = '-10%';
                        el.style.transform = 'rotate('+ (Math.random()*360) +'deg)';
                        container.appendChild(el);
                        const fall = el.animate([
                            { transform: el.style.transform + ' translateY(0)', opacity:1 },
                            { transform: el.style.transform + ' translateY(140%) rotate(360deg)', opacity:0.9 }
                        ], { duration: 1400 + Math.random()*800, easing:'cubic-bezier(.2,.6,.2,1)' });
                        fall.onfinish = ()=>el.remove();
                    }
                }
            </script>
        </body>
        </html>
        """
    }
}

 
#endif

