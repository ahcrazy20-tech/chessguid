import SwiftUI
import WebKit

struct ChessWebView: UIViewRepresentable {
    @ObservedObject var engine: LiveEngine
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        
        let userContentController = WKUserContentController()
        
        // Stealth Script
        let stealthScript = """
        Object.defineProperty(navigator, 'webdriver', {get: () => undefined});
        document.body.style.paddingTop = '60px';
        document.body.style.backgroundColor = '#262421';
        document.addEventListener('gesturestart', function (e) { e.preventDefault(); });
        document.body.style.userSelect = 'none';
        """
        userContentController.addUserScript(WKUserScript(source: stealthScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        
        // IMPROVED Scanner Script - More robust FEN detection
        let scannerScript = """
        var _lastFen = "";
        var _scanCount = 0;
        
        function getFEN() {
            try {
                // Try multiple selectors to find the board
                var board = document.querySelector('.board');
                if (!board) return null;
                
                var fen = "";
                var isBlack = board.classList.contains('orientation-black');
                
                // Scan each rank (row)
                for (var rank = 0; rank < 8; rank++) {
                    var emptyCount = 0;
                    
                    for (var file = 0; file < 8; file++) {
                        // Calculate square index based on orientation
                        var actualRank = isBlack ? (7 - rank) : rank;
                        var actualFile = isBlack ? (7 - file) : file;
                        var squareIndex = actualRank * 8 + actualFile;
                        
                        // Try to find the square element
                        var square = board.querySelector('[data-square="' + squareIndex + '"]') || 
                                    board.querySelector('.square-' + squareIndex);
                        
                        if (square) {
                            // Look for piece in the square
                            var piece = square.querySelector('.piece') || 
                                       square.querySelector('[class*="piece"]');
                            
                            if (piece) {
                                if (emptyCount > 0) {
                                    fen += emptyCount;
                                    emptyCount = 0;
                                }
                                
                                var pieceClass = piece.className || piece.getAttribute('class') || '';
                                var isWhite = pieceClass.includes('white') || pieceClass.includes('White');
                                var pieceType = 'p';
                                
                                if (pieceClass.includes('knight') || pieceClass.includes('Knight')) pieceType = 'n';
                                else if (pieceClass.includes('bishop') || pieceClass.includes('Bishop')) pieceType = 'b';
                                else if (pieceClass.includes('rook') || pieceClass.includes('Rook')) pieceType = 'r';
                                else if (pieceClass.includes('queen') || pieceClass.includes('Queen')) pieceType = 'q';
                                else if (pieceClass.includes('king') || pieceClass.includes('King')) pieceType = 'k';
                                
                                fen += isWhite ? pieceType.toUpperCase() : pieceType.toLowerCase();
                            } else {
                                emptyCount++;
                            }
                        } else {
                            emptyCount++;
                        }
                    }
                    
                    if (emptyCount > 0) fen += emptyCount;
                    if (rank < 7) fen += '/';
                }
                
                // Determine turn (simplified - assume white moves first)
                var turn = 'w';
                fen += ' ' + turn + ' - - 0 1';
                
                return fen;
            } catch(e) {
                return null;
            }
        }
        
        function stealthScan() {
            // Random delay between 3-6 seconds for stealth
            var delay = Math.floor(Math.random() * 3000) + 3000;
            setTimeout(stealthScan, delay);
            
            try {
                var fen = getFEN();
                if (fen && fen.length > 10 && fen !== _lastFen) {
                    _lastFen = fen;
                    _scanCount++;
                    window.webkit.messageHandlers.fenDetector.postMessage(fen);
                }
            } catch(e) {
                // Silent fail
            }
        }
        
        // Start scanning after 3 seconds
        setTimeout(stealthScan, 3000);
        """
        userContentController.addUserScript(WKUserScript(source: scannerScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        userContentController.add(context.coordinator, name: "fenDetector")
        config.userContentController = userContentController
        
        let webview = WKWebView(frame: .zero, configuration: config)
        webview.backgroundColor = UIColor(red: 38/255, green: 36/255, blue: 33/255, alpha: 1.0)
        webview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webview.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.4 Mobile/15E148 Safari/604.1"
        
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
            if message.name == "fenDetector", let fen = message.body as? String {
                engine.analyzeFEN(fen)
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var engine = LiveEngine()
    @State private var showEngine = true
    @State private var buttonPosition: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var manualFEN: String = ""
    @State private var showManualInput = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                HStack {
                    Button(action: { engine.currentURL = "https://www.chess.com/play/computer" }) {
                        Text("Play").fontWeight(.bold)
                            .foregroundColor(engine.currentURL.contains("chess.com") ? .white : .gray)
                            .padding(.horizontal, 15).padding(.vertical, 8)
                            .background(engine.currentURL.contains("chess.com") ? Color.blue : Color.clear).cornerRadius(8)
                    }
                    Spacer()
                    Button(action: { engine.currentURL = "https://lichess.org/analysis" }) {
                        Text("Lichess").fontWeight(.bold)
                            .foregroundColor(engine.currentURL.contains("lichess") ? .white : .gray)
                            .padding(.horizontal, 15).padding(.vertical, 8)
                            .background(engine.currentURL.contains("lichess") ? Color.green : Color.clear).cornerRadius(8)
                    }
                    Button(action: { showManualInput.toggle() }) {
                        Image(systemName: "keyboard").foregroundColor(.yellow).font(.title2)
                    }
                }
                .padding(.top, 50).padding(.horizontal).background(Color.black.opacity(0.8))
                
                ChessWebView(engine: engine).ignoresSafeArea(edges: .bottom)
            }
            
            if showEngine {
                VStack {
                    Spacer()
                    
                    // Manual FEN Input (Fallback)
                    if showManualInput {
                        HStack {
                            TextField("Paste FEN here...", text: $manualFEN)
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.none)
                                .font(.caption)
                            
                            Button(action: {
                                engine.analyzeFEN(manualFEN)
                                showManualInput = false
                            }) {
                                Image(systemName: "cpu.fill").foregroundColor(.green).font(.title2)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 5)
                    }
                    
                    HStack {
                        Image(systemName: "shield.lefthalf.filled").foregroundColor(.green)
                        Text(engine.isThinking ? "  Calculating..." : "  Live Engine Active")
                            .font(.caption).foregroundColor(.gray)
                        Spacer()
                        Text("Scans: \(engine.scanCount)")
                            .font(.caption2).foregroundColor(.gray)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 2)
                    
                    EnginePanel(moves: engine.topMoves, isThinking: engine.isThinking, lastFEN: engine.lastFEN)
                        .padding(.horizontal).padding(.bottom, 40)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            
            Image(systemName: showEngine ? "eye.slash.circle.fill" : "eye.circle.fill")
                .font(.system(size: 44)).foregroundColor(.blue).shadow(radius: 5)
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
                            lastOffset = buttonPosition; isDragging = false
                        }
                ).padding()
        }
    }
}

struct EnginePanel: View {
    let moves: [String]
    let isThinking: Bool
    let lastFEN: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lock.shield.fill").foregroundColor(.green)
                Text(isThinking ? "  Analyzing Position..." : "  Top 3 Best Moves").font(.headline).foregroundColor(.white)
                Spacer()
            }
            Divider().background(Color.white.opacity(0.3))
            
            if moves.isEmpty || moves[0] == "Waiting for board..." {
                Text("Waiting for position...")
                    .foregroundColor(.gray)
                    .font(.caption)
                    .padding(.vertical, 4)
            } else {
                ForEach(Array(moves.enumerated()), id: \.offset) { index, move in
                    HStack {
                        Text("#\(index + 1)").fontWeight(.bold)
                            .foregroundColor(index == 0 ? .green : (index == 1 ? .yellow : .orange))
                            .frame(width: 25, alignment: .center)
                        Text(move).font(.system(.body, design: .monospaced).bold()).foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.vertical, 4).padding(.horizontal, 8)
                    .background(Color.white.opacity(0.1)).cornerRadius(6)
                }
            }
            
            // Show last FEN for debugging
            if !lastFEN.isEmpty {
                Text("FEN: \(lastFEN)")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.gray)
                    .lineLimit(2)
            }
        }
        .padding().background(Color.black.opacity(0.90)).cornerRadius(20)
        .shadow(color: .black.opacity(0.5), radius: 15, x: 0, y: 10)
    }
}

class LiveEngine: ObservableObject {
    @Published var topMoves: [String] = ["Waiting for board..."]
    @Published var isThinking: Bool = false
    @Published var currentURL: String = "https://www.chess.com/play/computer"
    @Published var lastFEN: String = ""
    @Published var scanCount: Int = 0
    
    private var lastAnalyzedFen: String = ""
    
    func analyzeFEN(_ fen: String) {
        scanCount += 1
        lastFEN = fen
        
        if fen == lastAnalyzedFen { return }
        lastAnalyzedFen = fen
        
        guard let board = Board.fromFEN(fen) else {
            topMoves = ["FEN parse failed"]
            isThinking = false
            return
        }
        
        isThinking = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let search = SearchV2(maxNodes: 100_000, timeLimit: 2.0)
            let results = search.topMoves(board, count: 3, maxDepth: 6)
            
            DispatchQueue.main.async {
                if results.isEmpty {
                    self.topMoves = ["No legal moves found"]
                } else {
                    self.topMoves = results.map { result in
                        let scoreDisplay = result.score > 90000 ? "Mate" : String(format: "%+.1f", Double(result.score) / 100.0)
                        return "\(result.san)  (Score: \(scoreDisplay))"
                    }
                }
                self.isThinking = false
            }
        }
    }
}
