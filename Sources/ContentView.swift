import SwiftUI
import WebKit

// 1. The WebView with Real Stockfish JS Injection
struct ChessWebView: UIViewRepresentable {
    @ObservedObject var engine: LiveEngine
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        
        let userContentController = WKUserContentController()
        
        // INJECT REAL STOCKFISH ENGINE (WebAssembly)
        let stockfishInjection = """
        // Load Stockfish.js from CDN
        var script = document.createElement('script');
        script.src = 'https://cdnjs.cloudflare.com/ajax/libs/stockfish.js/10.0.0/stockfish.js';
        document.head.appendChild(script);
        
        script.onload = function() {
            // Initialize the Web Worker
            var engine = new Worker(script.src);
            engine.postMessage('uci');
            engine.postMessage('setoption name MultiPV value 3');
            
            engine.onmessage = function(event) {
                var line = event.data;
                // Only send relevant analysis lines back to Swift
                if (line.startsWith('info') && line.includes('pv') && line.includes('multipv')) {
                    window.webkit.messageHandlers.engineOutput.postMessage(line);
                }
            };
            
            // Expose function to Swift to trigger analysis
            window.analyzeFEN = function(fen) {
                engine.postMessage('position fen ' + fen);
                engine.postMessage('go depth 15');
            };
        };
        
        // Monitor Lichess URL for FEN changes (Format: /analysis/[fen])
        setInterval(function() {
            var path = window.location.pathname;
            if (path.startsWith('/analysis/')) {
                var fen = path.replace('/analysis/', '').replace(/_/g, ' ');
                if (window.lastFen !== fen && window.analyzeFEN) {
                    window.lastFen = fen;
                    window.analyzeFEN(fen);
                }
            }
        }, 1000);
        """
        userContentController.addUserScript(WKUserScript(source: stockfishInjection, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        userContentController.add(context.coordinator, name: "engineOutput")
        config.userContentController = userContentController
        
        let webview = WKWebView(frame: .zero, configuration: config)
        webview.backgroundColor = UIColor(red: 38/255, green: 36/255, blue: 33/255, alpha: 1.0)
        webview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        let url = URL(string: engine.currentURL)!
        webview.load(URLRequest(url: url))
        
        return webview
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.frame = UIScreen.main.bounds
        if let currentURL = uiView.url, currentURL.absoluteString != engine.currentURL {
            uiView.load(URLRequest(url: URL(string: engine.currentURL)!))
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(engine: engine)
    }
    
    class Coordinator: NSObject, WKScriptMessageHandler {
        let engine: LiveEngine
        init(engine: LiveEngine) { self.engine = engine }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "engineOutput", let line = message.body as? String {
                engine.parseUCIOutput(line)
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
    @State private var isDragging = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Top Navigation Bar
                HStack {
                    Button(action: { engine.switchToChessCom() }) {
                        Text("Play")
                            .fontWeight(.bold)
                            .foregroundColor(engine.currentURL.contains("chess.com") ? .white : .gray)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 8)
                            .background(engine.currentURL.contains("chess.com") ? Color.blue : Color.clear)
                            .cornerRadius(8)
                    }
                    Spacer()
                    Button(action: { engine.switchToLichess() }) {
                        Text("Real Engine")
                            .fontWeight(.bold)
                            .foregroundColor(engine.currentURL.contains("lichess") ? .white : .gray)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 8)
                            .background(engine.currentURL.contains("lichess") ? Color.green : Color.clear)
                            .cornerRadius(8)
                    }
                }
                .padding(.top, 50)
                .padding(.horizontal)
                .background(Color.black.opacity(0.8))
                
                ChessWebView(engine: engine)
                    .ignoresSafeArea(edges: .bottom)
            }
            
            // Eval Bar
            VStack {
                EvalBar(score: engine.currentScore)
                    .frame(width: 12, height: 150)
                    .cornerRadius(6)
                    .padding(.leading, 5)
                    .padding(.top, 100)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .ignoresSafeArea()
            
            if showEngine {
                VStack {
                    Spacer()
                    HStack {
                        Text(engine.currentURL.contains("lichess") ? "Live Stockfish Analysis" : "Tap 'Real Engine' to analyze")
                            .font(.caption2)
                            .foregroundColor(engine.currentURL.contains("lichess") ? .green : .gray)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 2)
                    
                    EnginePanel(moves: engine.topMoves, isThinking: engine.isThinking)
                        .padding(.horizontal)
                        .padding(.bottom, 40)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            
            // Draggable Button
            Image(systemName: showEngine ? "eye.slash.circle.fill" : "eye.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(.blue)
                .shadow(radius: 5)
                .offset(buttonPosition)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if abs(value.translation.width) > 5 || abs(value.translation.height) > 5 {
                                isDragging = true
                                buttonPosition = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height)
                            }
                        }
                        .onEnded { value in
                            if !isDragging { withAnimation(.spring()) { showEngine.toggle() } }
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
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "cpu.fill").foregroundColor(.green)
                Text(isThinking ? "  Calculating..." : "  Top 3 Engine Moves")
                    .font(.headline).foregroundColor(.white)
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
        .padding().background(Color.black.opacity(0.90)).cornerRadius(20).shadow(color: .black.opacity(0.5), radius: 15, x: 0, y: 10)
    }
}

// 4. The Live Engine Logic (Real UCI Parser)
class LiveEngine: ObservableObject {
    @Published var topMoves: [String] = ["Waiting for position..."]
    @Published var isThinking: Bool = false
    @Published var currentScore: Double = 0.0
    @Published var currentURL: String = "https://www.chess.com/play/computer"
    
    private var parsedMoves: [Int: (move: String, score: String)] = [:]
    
    func switchToChessCom() {
        currentURL = "https://www.chess.com/play/computer"
        topMoves = ["Switch to Real Engine to analyze"]
        objectWillChange.send()
    }
    
    func switchToLichess() {
        currentURL = "https://lichess.org/analysis"
        topMoves = ["Waiting for position..."]
        objectWillChange.send()
    }
    
    // Parse real Stockfish UCI output
    func parseUCIOutput(_ line: String) {
        isThinking = true
        let parts = line.split(separator: " ")
        
        guard let multipvIndex = parts.firstIndex(of: "multipv"),
              let pvIndex = parts.firstIndex(of: "pv") else { return }
        
        let rank = Int(parts[multipvIndex + 1]) ?? 0
        let pv = parts[(pvIndex + 1)...].joined(separator: " ")
        let bestMove = pv.split(separator: " ").first.map(String.init) ?? ""
        
        var scoreStr = "0.0"
        if let cpIndex = parts.firstIndex(of: "cp") {
            let cp = Int(parts[cpIndex + 1]) ?? 0
            scoreStr = String(format: "%+.1f", Double(cp) / 100.0)
            if rank == 1 { currentScore = Double(cp) / 100.0 }
        } else if let mateIndex = parts.firstIndex(of: "mate") {
            let mate = Int(parts[mateIndex + 1]) ?? 0
            scoreStr = mate > 0 ? "M\(mate)" : "-M\(abs(mate))"
            if rank == 1 { currentScore = mate > 0 ? 10.0 : -10.0 }
        }
        
        parsedMoves[rank] = (move: bestMove, score: scoreStr)
        
        // Update UI with top 3 moves
        var newMoves: [String] = []
        for i in 1...3 {
            if let data = parsedMoves[i] {
                // Format move like e2e4 to e2-e4
                let formattedMove = data.move.count == 4 ? "\(data.move.prefix(2))-\(data.move.suffix(2))" : data.move
                newMoves.append("\(formattedMove)  (Score: \(data.score))")
            }
        }
        
        if !newMoves.isEmpty {
            DispatchQueue.main.async {
                self.topMoves = newMoves
                self.isThinking = false
            }
        }
    }
}
