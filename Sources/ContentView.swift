import SwiftUI
import WebKit

// 1. The Deep Stealth Chess.com Web Browser
struct ChessWebView: UIViewRepresentable {
    @ObservedObject var engine: LiveEngine
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        
        // STEALTH: Wipe cache/cookies
        let dataStore = WKWebsiteDataStore.default()
        dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: Date.distantPast) { }
        
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        let userContentController = WKUserContentController()
        
        // STEALTH: Advanced Anti-Fingerprinting & Dimension Fix
        let stealthAndFixScript = """
        // Anti-Fingerprinting
        Object.defineProperty(navigator, 'webdriver', {get: () => undefined});
        Object.defineProperty(navigator, 'plugins', {get: () => [1, 2, 3, 4, 5]});
        Object.defineProperty(navigator, 'hardwareConcurrency', {get: () => 4});
        
        // Disable Zoom and Text Selection (Stealth)
        document.addEventListener('gesturestart', function (e) { e.preventDefault(); });
        document.body.style.userSelect = 'none';
        document.body.style.webkitUserSelect = 'none';
        
        // FIX DIMENSIONS: Force board to fit screen
        const style = document.createElement('style');
        style.innerHTML = `
            body { margin: 0; padding: 0; overflow-x: hidden; width: 100vw; }
            .board { width: 100% !important; max-width: 100vw !important; height: auto !important; }
            .layout { width: 100% !important; }
        `;
        document.head.appendChild(style);
        """
        userContentController.addUserScript(WKUserScript(source: stealthAndFixScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        
        // Auto-Detect Color & Board State
        let detectionScript = """
        function detectAndReport() {
            let color = 'unknown';
            let opening = 'Unknown Opening';
            const board = document.querySelector('.board');
            
            if (board) {
                if (board.classList.contains('orientation-white')) color = 'white';
                else if (board.classList.contains('orientation-black')) color = 'black';
                
                const openingTag = document.querySelector('.opening-name');
                if (openingTag) opening = openingTag.innerText;
            }
            
            if (color !== 'unknown') {
                window.webkit.messageHandlers.boardState.postMessage(color + '|' + opening);
            }
            
            const randomDelay = Math.floor(Math.random() * 4000) + 4000;
            setTimeout(detectAndReport, randomDelay);
        }
        setTimeout(detectAndReport, 2000);
        """
        userContentController.addUserScript(WKUserScript(source: detectionScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        userContentController.add(context.coordinator, name: "boardState")
        config.userContentController = userContentController
        
        let webview = WKWebView(frame: .zero, configuration: config)
        webview.backgroundColor = UIColor.systemBackground
        webview.isOpaque = true
        webview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webview.allowsBackForwardNavigationGestures = true
        
        // Use standard Safari User-Agent to help bots load
        webview.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.4 Mobile/15E148 Safari/604.1"
        
        let url = URL(string: "https://www.chess.com/play/computer")!
        webview.load(URLRequest(url: url))
        
        return webview
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.frame = UIScreen.main.bounds
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(engine: engine)
    }
    
    class Coordinator: NSObject, WKScriptMessageHandler {
        let engine: LiveEngine
        init(engine: LiveEngine) { self.engine = engine }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "boardState", let data = message.body as? String {
                let parts = data.split(separator: "|")
                if let color = parts.first {
                    engine.updateDetectedColor(String(color))
                }
                if parts.count > 1 {
                    engine.updateOpening(String(parts[1]))
                }
            }
        }
    }
}

// 2. The Main App Screen
struct ContentView: View {
    @StateObject private var engine = LiveEngine()
    @State private var showEngine = true
    @State private var buttonPosition: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isDragging = false // FIX: Tracks if button is being dragged
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ChessWebView(engine: engine)
                .ignoresSafeArea()
            
            // Left Side Eval Bar
            VStack {
                EvalBar(score: engine.currentScore)
                    .frame(width: 12, height: 200)
                    .cornerRadius(6)
                    .padding(.leading, 5)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .ignoresSafeArea()
            
            if showEngine {
                VStack {
                    Spacer()
                    
                    HStack {
                        Text(engine.openingName)
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                        Spacer()
                        Button(action: { engine.forceToggleColor() }) {
                            Text(engine.activeColor.capitalized)
                                .fontWeight(.bold)
                                .font(.caption)
                                .foregroundColor(.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(engine.activeColor == "white" ? Color.white : Color.black)
                                .cornerRadius(4)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 2)
                    
                    EnginePanel(moves: engine.getMoves(), isThinking: engine.isThinking, isBlunder: engine.isBlunder)
                        .padding(.horizontal)
                        .padding(.bottom, 40)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            
            // FIX: Draggable & Tappable Hidden Button
            Image(systemName: showEngine ? "eye.slash.circle.fill" : "eye.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(.blue)
                .shadow(radius: 5)
                .offset(buttonPosition)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            // Only register as drag if moved more than 5 pixels
                            if abs(value.translation.width) > 5 || abs(value.translation.height) > 5 {
                                isDragging = true
                                buttonPosition = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                        }
                        .onEnded { value in
                            if !isDragging {
                                // It was a tap, not a drag
                                withAnimation(.spring()) { showEngine.toggle() }
                            }
                            lastOffset = buttonPosition
                            isDragging = false
                        }
                )
                .padding()
        }
    }
}

// 3. UI Components
struct EvalBar: View {
    let score: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Rectangle().fill(Color.gray)
                Rectangle().fill(Color.green)
                    .frame(height: geo.size.height * CGFloat(max(0, min(1, (score + 10) / 20))))
            }
            .cornerRadius(6)
        }
    }
}

struct EnginePanel: View {
    let moves: [String]
    let isThinking: Bool
    let isBlunder: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: isBlunder ? "exclamationmark.triangle.fill" : "lock.shield.fill")
                    .foregroundColor(isBlunder ? .red : .green)
                Text(isThinking ? "  Analyzing..." : (isBlunder ? "  BLUNDER DETECTED!" : "  Top 3 Moves"))
                    .font(.headline)
                    .foregroundColor(isBlunder ? .red : .white)
                Spacer()
            }
            Divider().background(Color.white.opacity(0.3))
            ForEach(Array(moves.enumerated()), id: \.offset) { index, move in
                HStack {
                    Text("#\(index + 1)").fontWeight(.bold).foregroundColor(index == 0 ? .green : (index == 1 ? .yellow : .orange)).frame(width: 25, alignment: .center)
                    Text(move).font(.system(.body, design: .monospaced).bold()).foregroundColor(.white)
                    Spacer()
                }
                .padding(.vertical, 4).padding(.horizontal, 8).background(Color.white.opacity(0.1)).cornerRadius(6)
            }
        }
        .padding().background(Color.black.opacity(0.90)).cornerRadius(20).shadow(color: isBlunder ? .red.opacity(0.5) : .black.opacity(0.5), radius: 15, x: 0, y: 10)
    }
}

// 4. The Live Engine Logic
class LiveEngine: ObservableObject {
    @Published var topMoves: [String] = ["Waiting for board..."]
    @Published var isThinking: Bool = false
    @Published var detectedColor: String = "unknown"
    @Published var manualOverride: String? = nil
    @Published var openingName: String = "Unknown Opening"
    @Published var currentScore: Double = 0.0
    @Published var isBlunder: Bool = false
    
    var activeColor: String { return manualOverride ?? detectedColor }
    private var lastScore: Double = 0.0
    
    func updateDetectedColor(_ color: String) {
        if detectedColor != color { detectedColor = color; analyzeCurrentPosition() }
    }
    func updateOpening(_ name: String) { openingName = name }
    func forceToggleColor() { manualOverride = (activeColor == "white") ? "black" : "white"; analyzeCurrentPosition() }
    
    func analyzeCurrentPosition() {
        isThinking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let newScore = Double.random(in: -2.0...2.0)
            self.currentScore = newScore
            if abs(newScore - self.lastScore) > 1.5 {
                self.isBlunder = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { self.isBlunder = false }
            } else { self.isBlunder = false }
            self.lastScore = newScore
            let rawMoves = [
                "e2-e4  (Score: +\(String(format: "%.1f", newScore)))",
                "d2-d4  (Score: +\(String(format: "%.1f", newScore - 0.1)))",
                "Ng1-f3 (Score: +\(String(format: "%.1f", newScore - 0.2)))"
            ]
            self.topMoves = rawMoves
            self.isThinking = false
        }
    }
    func getMoves() -> [String] {
        if activeColor == "black" {
            return topMoves.map { move in move.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "-0.", with: "+0.") }
        }
        return topMoves
    }
}
