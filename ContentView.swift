import SwiftUI
import AVFoundation

enum Janken: String, CaseIterable, Identifiable {
    public var id: String { rawValue }
    case gu = "グー"
    case choki = "チョキ"
    case pa = "パー"
}

enum Direction: String, CaseIterable {
    case left = "左"
    case right = "右"
}

final class GameLogic: ObservableObject {
    @Published var statusText: String = "じゃんけんをしてください"
    @Published var playerHand: Janken? = nil
    @Published var cpuHand: Janken? = nil
    @Published var playerDirection: Direction? = nil
    @Published var cpuDirection: Direction? = nil
    @Published var phase: Phase = .janken

    enum Phase {
        case janken
        case pointing
        case deciding
    }

    func playJanken(player: Janken) {
        playerHand = player
        cpuHand = Janken.allCases.randomElement()!

        if playerHand == cpuHand {
            statusText = "あいこ！もう一度"
            return
        }

        let playerWins = (playerHand == .gu && cpuHand == .choki) || (playerHand == .choki && cpuHand == .pa) || (playerHand == .pa && cpuHand == .gu)

        if playerWins {
            statusText = "あなたの勝ち！指して！"
        } else {
            statusText = "CPUの勝ち。首を向けて！"
        }
        phase = .pointing
    }

    func chooseDirection(_ dir: Direction) {
        guard phase == .pointing else { return }
        playerDirection = dir
        cpuDirection = Direction.allCases.randomElement()!

        if playerWinsLastJanken() {
            if playerDirection == cpuDirection {
                statusText = "あなたの勝ち！"
            } else {
                statusText = "はずれ。じゃんけんに戻ります"
                resetForNextRound()
                return
            }
        } else {
            if playerDirection == cpuDirection {
                statusText = "あなたの負け！"
            } else {
                statusText = "はずれ。じゃんけんに戻ります"
                resetForNextRound()
                return
            }
        }

        phase = .deciding
    }

    func playerWinsLastJanken() -> Bool {
        guard let p = playerHand, let c = cpuHand else { return false }
        return (p == .gu && c == .choki) || (p == .choki && c == .pa) || (p == .pa && c == .gu)
    }

    func resetForNextRound() {
        playerHand = nil
        cpuHand = nil
        playerDirection = nil
        cpuDirection = nil
        phase = .janken
        statusText = "じゃんけんをしてください"
    }
}

struct ContentView: View {
    @StateObject private var game = GameLogic()
    @State private var headRotation: Double = 0
    @State private var fingerOffset: CGFloat = 0
    @State private var showConfetti = false
    private let tts = AVSpeechSynthesizer()

    var body: some View {
        VStack(spacing: 20) {
            Text(game.statusText)
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)
                .padding(.top)

            HStack(alignment: .center, spacing: 40) {
                VStack(spacing: 12) {
                    Text("あなた")
                        .font(.headline)
                    Image(systemName: symbolForHand(game.playerHand))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundStyle(.blue)
                    Text(game.playerHand?.rawValue ?? "-")
                }

                VStack(spacing: 12) {
                    Text("CPU")
                        .font(.headline)
                            ZStack {
                                // Load local svg via simple WebView wrapper for vector display
                                SVGWebView(name: "cpu", width: 120, height: 120, triggerWin: showConfetti)
                                    .frame(width: 120, height: 120)
                                    .rotationEffect(.degrees(headRotation), anchor: .center)
                                    .animation(.interpolatingSpring(stiffness: 200, damping: 8), value: headRotation)

                                // pointing finger indicator
                                if game.phase != .janken {
                                    Image(systemName: "hand.point.right.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 36, height: 36)
                                        .offset(x: fingerOffset)
                                        .foregroundStyle(.red)
                                        .animation(.easeInOut(duration: 0.25), value: fingerOffset)
                                }
                            }
                    Text(game.cpuHand?.rawValue ?? "-")
                }
            }

            if game.phase == .janken {
                HStack(spacing: 16) {
                    ForEach(Janken.allCases) { hand in
                        Button(action: {
                            game.playJanken(player: hand)
                            speak("じゃんけん\(hand.rawValue)！")
                            // small animation
                            withAnimation(.spring()) { fingerOffset = 0 }
                        }) {
                            VStack {
                                Text(hand.rawValue)
                                    .font(.title2)
                                    .bold()
                                Text(emojiForJanken(hand))
                                    .font(.largeTitle)
                            }
                            .padding()
                            .frame(minWidth: 90)
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                            .shadow(radius: 4)
                        }
                    }
                }
            } else if game.phase == .pointing {
                HStack(spacing: 24) {
                    Button(action: {
                        withAnimation { fingerOffset = -40 }
                        game.chooseDirection(.left)
                        performAfterPointing()
                    }) {
                        Text("← 左")
                            .font(.title3)
                            .padding()
                            .frame(minWidth: 120)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(10)
                    }
                    Button(action: {
                        withAnimation { fingerOffset = 40 }
                        game.chooseDirection(.right)
                        performAfterPointing()
                    }) {
                        Text("右 →")
                            .font(.title3)
                            .padding()
                            .frame(minWidth: 120)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(10)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    if game.statusText.contains("勝ち") { Text("🎉").font(.largeTitle) }
                    Button("もう一度") {
                        game.resetForNextRound()
                        withAnimation { headRotation = 0; fingerOffset = 0; showConfetti = false }
                        speak("じゃんけんをしてください")
                    }
                    .padding()
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(8)
                }
            }

            Spacer()
        }
        .padding()
        .onChange(of: game.cpuDirection) { newDir in
            guard let d = newDir else { return }
            // rotate head toward direction
            withAnimation(.easeOut(duration: 0.3)) {
                headRotation = (d == .left) ? -30 : 30
            }
        }
        .onChange(of: game.phase) { p in
                if p == .pointing {
                    speak("あっちむいてほい")
                } else if p == .deciding {
                    if game.statusText.contains("勝ち") {
                        speak("おめでとう、あなたの勝ちです")
                        withAnimation { showConfetti = true }
                        // reset the flag after short delay so next time it can trigger again
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { withAnimation { showConfetti = false } }
                    } else if game.statusText.contains("負け") {
                        speak("残念、あなたの負けです")
                    }
                }
        }
    }

    func performAfterPointing() {
        // speak short phrase and apply small delay to show head rotation
        speak("あっちむいてほい！")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            // keep rotation for a bit then reset conditionally
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if game.phase == .deciding {
                    // leave result displayed
                } else {
                    withAnimation { headRotation = 0; fingerOffset = 0 }
                }
            }
        }
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)

        // Try to pick a female-sounding Japanese voice if available.
        if let femaleVoice = AVSpeechSynthesisVoice.speechVoices().first(where: { v in
            // prefer Japanese voices
            guard v.language == "ja-JP" else { return false }
            let id = v.identifier.lowercased()
            let name = v.name.lowercased()
            // look for hints that indicate a female or Siri female voice
            return id.contains("female") || name.contains("female") || id.contains("siri") && name.contains("siri") || name.contains("yuka") || name.contains("yui") || name.contains("haru") || name.contains("kyoko")
        }) {
            utterance.voice = femaleVoice
        } else if let ja = AVSpeechSynthesisVoice(language: "ja-JP") {
            utterance.voice = ja
        }

        utterance.rate = 0.5
        tts.stopSpeaking(at: .immediate)
        tts.speak(utterance)
    }

    func symbolForHand(_ hand: Janken?) -> String {
        // Prefer SF Symbols on platforms that support them; on macOS, verify symbol exists and fallback to emoji
        func symbolName(for h: Janken) -> String {
            switch h {
            case .gu: return "hand.rock.fill"
            case .choki: return "hand.scissors.fill"
            case .pa: return "hand.paper.fill"
            }
        }

        if let h = hand {
#if os(macOS)
            // check if system symbol exists (available on macOS 11+ via NSImage)
            let name = symbolName(for: h)
            if #available(macOS 11.0, *) {
                if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
                    return name
                } else {
                    // fallback to emoji for macOS when symbol not available
                    switch h {
                    case .gu: return "✊"
                    case .choki: return "✌️"
                    case .pa: return "🖐️"
                    }
                }
            } else {
                switch h {
                case .gu: return "✊"
                case .choki: return "✌️"
                case .pa: return "🖐️"
                }
            }
#else
            return symbolName(for: h)
#endif
        }

        return "hand.raised.fill"
    }

    func emojiForJanken(_ hand: Janken) -> String {
        switch hand {
        case .gu: return "✊"
        case .choki: return "✌️"
        case .pa: return "🖐️"
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

import WebKit

#if os(iOS)
import UIKit

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
        if let file = Bundle.main.path(forResource: name, ofType: "svg", inDirectory: "Resources") {
            do {
                let svg = try String(contentsOfFile: file, encoding: .utf8)
                let wrapped = makeWrappedHTML(with: svg)
                uiView.loadHTMLString(wrapped, baseURL: nil)
            } catch { }
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
import AppKit

struct SVGWebView: NSViewRepresentable {
    let name: String
    let width: CGFloat
    let height: CGFloat
    var triggerWin: Bool = false

    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero)
        // make background transparent on macOS
        web.setValue(false, forKey: "drawsBackground")
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        load(svgInto: nsView)
        if triggerWin { nsView.evaluateJavaScript("triggerWin()", completionHandler: nil) }
    }

    private func load(svgInto uiView: WKWebView) {
        if let file = Bundle.main.path(forResource: name, ofType: "svg", inDirectory: "Resources") {
            do {
                let svg = try String(contentsOfFile: file, encoding: .utf8)
                let wrapped = makeWrappedHTML(with: svg)
                uiView.loadHTMLString(wrapped, baseURL: nil)
            } catch { }
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

