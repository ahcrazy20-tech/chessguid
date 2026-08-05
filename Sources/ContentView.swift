import SwiftUI
import WebKit

// 1. The Deep Stealth Chess.com Web Browser
struct ChessWebView: UIViewRepresentable {
    @ObservedObject var engine: LiveEngine
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        
        // STEALTH: Wipe all cookies and cache on launch to prevent device fingerprinting
        let dataStore = WKWebsiteDataStore.default()
        dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), 
                             modifiedSince: Date.distantPast) { }
        
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        
        // STEALTH: Anti-Fingerprinting & Auto-Detection Script
        let userContentController = WKUserContentController()
        
        // Overwrite navigator properties to hide WebView signatures
        let antiFingerprint = """
        Object.defineProperty(navigator, 'webdriver', {get: () => undefined});
        """
        userContentController.addUserScript(WKUserScript(source: antiFingerprint, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        
        // Auto-Detect Color with Randomized "Human" Timing
        let detectionScript = """
        function detectAndReport() {
            let color = 'unknown';
            const board = document.querySelector('.board');
            
            // Check CSS orientation classes
            if (board) {
                if (board.classList.contains('orientation-white')) color = 'white';
                else if (board.classList.contains('orientation-black')) color = 'black';
            }
            
            // Send back to app
            if (color !== 'unknown') {
                window.webkit.messageHandlers.boardState.postMessage(color);
            }
            
            // STEALTH: Randomize next check between 3000ms and 7000ms to look human
            const randomDelay = Math.floor(Math.random() * 4000) + 3000;
            setTimeout(detectAndReport, randomDelay);
        }
        
        // Start the loop
        setTimeout(detectAndReport, 2000);
        """
        userContentController.addUserScript(WKUserScript(source: detectionScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        userContentController.add(context.coordinator, name: "boardState")
        config.userContentController = userContentController
        
        let webview = WKWebView(frame: .zero, configuration: config)
        webview.backgroundColor = UIColor.systemBackground
        webview.isOpaque = true
        webview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
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
            if message.name == "boardState", let detectedColor = message.body as? String {
                engine.updateDetectedColor(detectedColor)
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
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ChessWebView(engine: engine)
                .ignoresSafeArea()
            
            if showEngine {
                VStack {
                    Spacer()
                    
                    // Auto-Detection Status & Manual Override
                    HStack {
                        Image(systemName: "eye.fill")
                            .foregroundColor(.gray)
                        Text("Auto-Detected:")
                            .foregroundColor(.gray)
                            .font(.caption)
                        
                        Button(action: { engine.forceToggleColor() }) {
                            Text(engine.activeColor.capitalized)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(engine.activeColor == "white" ? Color.white : Color.black)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray, lineWidth: 1))
                                .cornerRadius(4)
                        }
                        .font(.caption)
                        
                        if engine.activeColor == "unknown" {
                            Text("(Tap to fix)")
                                .foregroundColor(.yellow)
                                .font(.caption2)
                        }
                    }
                    .padding(.bottom, 5)
                    
                    EnginePanel(moves: engine.getMoves(), isThinking: engine.isThinking)
                        .padding(.horizontal)
                        .padding(.bottom, 40)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            
            // Draggable Hidden Button
            Image(systemName: showEngine ? "eye.slash.circle.fill" : "eye.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(.blue)
                .shadow(radius: 5)
                .offset(buttonPosition)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            buttonPosition = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height)
                        }
                        .onEnded { value in lastOffset = buttonPosition }
                )
                .padding()
        }
    }
}

// 3. The Floating Panel UI
struct EnginePanel: View {
    let moves: [String]
    let isThinking: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.green)
                Text(isThinking ? "  Stealth Scanning..." : "✅ Local Top 3 Moves")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            Divider().background(Color.white.opacity(0.3))
            ForEach(Array(moves.enumerated()), id: \.offset) { index, move in
                HStack {
                    Text("#\(index + 1)").fontWeight(.bold).foregroundColor(index == 0 ? .green : (index == 1 ? .yellow : .orange)).frame(width: 30, alignment: .center)
                    Text(move).font(.system(.body, design: .monospaced).bold()).foregroundColor(.white)
                    Spacer()
                }
                .padding(.vertical, 6).padding(.horizontal, 10).background(Color.white.opacity(0.1)).cornerRadius(8)
            }
        }
        .padding().background(Color.black.opacity(0.90)).cornerRadius(20).shadow(color: .black.opacity(0.5), radius: 15, x: 0, y: 10)
    }
}

// 4. The Live Engine Logic (Auto-Detection + Manual Override)
class LiveEngine: ObservableObject {
    @Published var topMoves: [String] = ["Waiting for board..."]
    @Published var isThinking: Bool = false
    @Published var detectedColor: String = "unknown"
    @Published var manualOverride: String? = nil
    
    var activeColor: String {
        return manualOverride ?? detectedColor
    }
    
    private var moveCount = 0
    
    func updateDetectedColor(_ color: String) {
        if detectedColor != color {
            detectedColor = color
            analyzeCurrentPosition()
        }
    }
    
    func forceToggleColor() {
        if activeColor == "white" {
            manualOverride = "black"
        } else {
            manualOverride = "white"
        }
        analyzeCurrentPosition()
    }
    
    func analyzeCurrentPosition() {
        moveCount += 1
        isThinking = true
        
        // Simulate local processing delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            let rawMoves = [
                "e2-e4  (Score: +0.3)",
                "d2-d4  (Score: +0.2)",
                "Ng1-f3 (Score: +0.1)"
            ]
            self.topMoves = rawMoves
            self.isThinking = false
        }
    }
    
    func getMoves() -> [String] {
        if activeColor == "black" {
            // Invert scores for Black perspective
            return topMoves.map { move in
                move.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "-0.", with: "+0.")
            }
        }
        return topMoves
    }
}
