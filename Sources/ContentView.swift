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
        
        // 1. Stealth Script
        let stealthScript = """
        Object.defineProperty(navigator, 'webdriver', {get: () => undefined});
        document.body.style.paddingTop = '60px';
        document.body.style.backgroundColor = '#262421';
        document.addEventListener('gesturestart', function (e) { e.preventDefault(); });
        document.body.style.userSelect = 'none';
        """
        userContentController.addUserScript(WKUserScript(source: stealthScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        
        // 2. THE ULTIMATE SMART SCANNER
        let scannerScript = """
        var _lastFen = "";
        
        function getFEN() {
            // Step 1: Find all 64 squares individually
            var squares = [];
            for (var i = 0; i < 64; i++) {
                // Try class name first
                var sq = document.querySelector('.square-' + i);
                // Try data attribute fallback
                if (!sq) sq = document.querySelector('[data-square="' + i + '"]');
                
                if (sq) {
                    squares.push({id: i, el: sq});
                }
            }
            
            // If we didn't find all 64 squares, it's not a full board yet
            if (squares.length < 64) return null;

            // Step 2: Sort squares visually (Top-Left to Bottom-Right)
            squares.sort(function(a, b) {
                var rectA = a.el.getBoundingClientRect();
                var rectB = b.el.getBoundingClientRect();
                // If they are on different rows (top is significantly different)
                if (Math.abs(rectA.top - rectB.top) > 10) {
                    return rectA.top - rectB.top;
                }
                // Otherwise sort by left position
                return rectA.left - rectB.left;
            });

            // Step 3: Detect Orientation
            // Check the parent of the first square for orientation class
            var parent = squares[0].el.parentElement;
            var isBlackOrientation = false;
            if (parent && parent.className && parent.className.includes('orientation-black')) {
                isBlackOrientation = true;
            }

            // Step 4: Build FEN
            var fen = "";
            var emptyCount = 0;
            
            // If White: Start at index 0 (Top-Left is a8). Iterate 0 to 63.
            // If Black: Start at index 63 (Bottom-Right is a8). Iterate 63 down to 0.
            var start = isBlackOrientation ? 63 : 0;
            var end = isBlackOrientation ? -1 : 64;
            var step = isBlackOrientation ? -1 : 1;

            for (var i = start; i !== end; i += step) {
                var sq = squares[i].el;
                var img = sq.querySelector('img');
                var pieceChar = null;
                
                if (img) {
                    var src = (img.src || "").toLowerCase();
                    var cls = (img.className || "").toLowerCase();
                    var alt = (img.alt || "").toLowerCase();
                    var combined = src + " " + cls + " " + alt;
                    
                    // Determine Piece Type
                    if (combined.includes('king') || combined.includes('wk') || combined.includes('bk')) pieceChar = 'K';
                    else if (combined.includes('queen') || combined.includes('wq') || combined.includes('bq')) pieceChar = 'Q';
                    else if (combined.includes('rook') || combined.includes('wr') || combined.includes('br')) pieceChar = 'R';
                    else if (combined.includes('bishop') || combined.includes('wb') || combined.includes('bb')) pieceChar = 'B';
                    else if (combined.includes('knight') || combined.includes('wn') || combined.includes('bn')) pieceChar = 'N';
                    else if (combined.includes('pawn') || combined.includes('wp') || combined.includes('bp')) pieceChar = 'P';
                    
                    // Determine Color
                    var isWhitePiece = combined.includes('white') || combined.includes('wp') || combined.includes('wk') || combined.includes('wq') || combined.includes('wr') || combined.includes('wb') || combined.includes('wn');
                    var isBlackPiece = combined.includes('black') || combined.includes('bp') || combined.includes('bk') || combined.includes('bq') || combined.includes('br') || combined.includes('bb') || combined.includes('bn');
                    
                    if (pieceChar) {
                        if (emptyCount > 0) { fen += emptyCount; emptyCount = 0; }
                        fen += isWhitePiece ? pieceChar : pieceChar.toLowerCase();
                    } else {
                        emptyCount++;
                    }
                } else {
                    emptyCount++;
                }
                
                // End of row (every 8 squares)
                // We need to check if the next square is on a new row visually
                // Since we sorted them, every 8th item is a new row.
                // But we must handle the loop direction.
                // Simple way: Check index relative to start.
                var stepsTaken = Math.abs(i - start);
                if ((stepsTaken + 1) % 8 === 0) {
                    if (emptyCount > 0) { fen += emptyCount; emptyCount = 0; }
                    if (i !== end - step) { // Don't add slash after last row
                         fen += '/';
                    }
                }
            }
            
            // Add turn info (default to white for simplicity, engine can handle it)
            return fen + " w - - 0 1";
        }
        
        function stealthScan() {
            // Scan every 2.5 seconds
            setTimeout(stealthScan, 2500);
            try {
                var fen = getFEN();
                // Only send if valid and changed
                if (fen && fen.length > 10 && fen !== _lastFen && !fen.includes('8/8/8/8/8/8/8/8')) {
                    _lastFen = fen;
                    window.webkit.messageHandlers.fenDetector.postMessage(fen);
                }
            } catch(e) {
                // Silent fail
            }
        }
        
        // Start immediately
        setTimeout(stealthScan, 1000);
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
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(engine.currentURL.contains("chess.com") ? Color.blue : Color.clear).cornerRadius(8)
                    }
                    Spacer()
                    Button(action: { engine.currentURL = "https://lichess.org/analysis" }) {
                        Text("Lichess").fontWeight(.bold)
                            .foregroundColor(engine.currentURL.contains("lichess") ? .white : .gray)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(engine.currentURL.contains("lichess") ? Color.green : Color.clear).cornerRadius(8)
                    }
                    Button(action: { showManualInput.toggle() }) {
                        Image(systemName: "keyboard").foregroundColor(.yellow).font(.title3)
                    }
                }
                .padding(.top, 50).padding(.horizontal).background(Color.black.opacity(0.8))
                
                ChessWebView(engine: engine).ignoresSafeArea(edges: .bottom)
            }
            
            if showEngine {
                VStack {
                    Spacer()
                    
                    if showManualInput {
                        HStack {
                            TextField("Paste FEN...", text: $manualFEN)
                                .textFieldStyle(.roundedBorder).font(.caption)
                            Button(action: { engine.analyzeFEN(manualFEN); showManualInput = false }) {
                                Image(systemName: "cpu.fill").foregroundColor(.green).font(.title2)
                            }
                        }
                        .padding(.horizontal).padding(.bottom, 5)
                    }
                    
                    HStack {
                        Image(systemName: "shield.lefthalf.filled").foregroundColor(.green)
                        Text(engine.isThinking ? "  Calculating..." : "  Live Engine Active")
                            .font(.caption).foregroundColor(.gray)
                        Spacer()
                        Text("Scans: \(engine.scanCount)")
                            .font(.caption2).foregroundColor(.gray)
                    }
                    .padding(.horizontal).padding(.bottom, 2)
                    
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
                Text(isThinking ? "  Analyzing..." : "  Top 3 Moves").font(.headline).foregroundColor(.white)
                Spacer()
            }
            Divider().background(Color.white.opacity(0.3))
            if moves.isEmpty || moves[0].contains("Waiting") {
                Text("Waiting for position...").foregroundColor(.gray).font(.caption).padding(.vertical, 4)
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
            if !lastFEN.isEmpty {
                Text("FEN: \(lastFEN)")
                    .font(.system(size: 8, design: .monospaced)).foregroundColor(.gray).lineLimit(2)
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
