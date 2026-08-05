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
        
        let stealthScript = """
        Object.defineProperty(navigator, 'webdriver', {get: () => undefined});
        document.body.style.paddingTop = '60px';
        document.body.style.backgroundColor = '#262421';
        document.addEventListener('gesturestart', function (e) { e.preventDefault(); });
        document.body.style.userSelect = 'none';
        """
        userContentController.addUserScript(WKUserScript(source: stealthScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        
        // DEEP SEARCH SCANNER (Image Source + Debug Mode)
        let scannerScript = """
        var _lastFen = "";
        
        function getFEN() {
            try {
                var board = document.querySelector('.board');
                if (!board) return null;
                
                var fen = "";
                var isBlack = board.classList.contains('orientation-black');
                
                for (var rank = 0; rank < 8; rank++) {
                    var emptyCount = 0;
                    for (var file = 0; file < 8; file++) {
                        var actualRank = isBlack ? (7 - rank) : rank;
                        var actualFile = isBlack ? (7 - file) : file;
                        var squareIndex = actualRank * 8 + actualFile;
                        
                        var square = board.querySelector('.square-' + squareIndex) || 
                                     board.querySelector('[data-square="' + squareIndex + '"]');
                        
                        var pieceType = null;
                        var isWhite = false;
                        
                        if (square) {
                            var img = square.querySelector('img');
                            if (img && img.src) {
                                var src = img.src.toLowerCase();
                                
                                if (src.includes('wp') || src.includes('white-pawn') || src.includes('wpng')) { pieceType = 'p'; isWhite = true; }
                                else if (src.includes('wn') || src.includes('white-knight')) { pieceType = 'n'; isWhite = true; }
                                else if (src.includes('wb') || src.includes('white-bishop')) { pieceType = 'b'; isWhite = true; }
                                else if (src.includes('wr') || src.includes('white-rook')) { pieceType = 'r'; isWhite = true; }
                                else if (src.includes('wq') || src.includes('white-queen')) { pieceType = 'q'; isWhite = true; }
                                else if (src.includes('wk') || src.includes('white-king')) { pieceType = 'k'; isWhite = true; }
                                
                                else if (src.includes('bp') || src.includes('black-pawn')) { pieceType = 'p'; isWhite = false; }
                                else if (src.includes('bn') || src.includes('black-knight')) { pieceType = 'n'; isWhite = false; }
                                else if (src.includes('bb') || src.includes('black-bishop')) { pieceType = 'b'; isWhite = false; }
                                else if (src.includes('br') || src.includes('black-rook')) { pieceType = 'r'; isWhite = false; }
                                else if (src.includes('bq') || src.includes('black-queen')) { pieceType = 'q'; isWhite = false; }
                                else if (src.includes('bk') || src.includes('black-king')) { pieceType = 'k'; isWhite = false; }
                            }
                        }
                        
                        if (pieceType) {
                            if (emptyCount > 0) { fen += emptyCount; emptyCount = 0; }
                            fen += isWhite ? pieceType.toUpperCase() : pieceType.toLowerCase();
                        } else {
                            emptyCount++;
                        }
                    }
                    if (emptyCount > 0) fen += emptyCount;
                    if (rank < 7) fen += '/';
                }
                return fen + " w - - 0 1";
            } catch(e) { return null; }
        }
        
        function getDebugHTML() {
            try {
                var board = document.querySelector('.board');
                return board ? board.innerHTML.substring(0, 2000) : "No board found";
            } catch(e) { return "Error: " + e.message; }
        }
        
        function stealthScan() {
            var delay = Math.floor(Math.random() * 3000) + 2000;
            setTimeout(stealthScan, delay);
            try {
                var fen = getFEN();
                if (fen && fen.length > 10 && fen !== _lastFen) {
                    _lastFen = fen;
                    window.webkit.messageHandlers.fenDetector.postMessage(fen);
                }
            } catch(e) {}
        }
        setTimeout(stealthScan, 2000);
        """
        userContentController.addUserScript(WKUserScript(source: scannerScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        userContentController.add(context.coordinator, name: "fenDetector")
        userContentController.add(context.coordinator, name: "debugHTML")
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
            } else if message.name == "debugHTML", let html = message.body as? String {
                // FIX: Added 'self.' here to satisfy Swift's closure rules
                DispatchQueue.main.async {
                    self.engine.debugHTML = html
                }
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
    @State private var showDebug = false
    
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
                    Button(action: { 
                        showDebug = true
                        // Trigger debug scan via JS
                    }) {
                        Image(systemName: "ladybug.fill").foregroundColor(.red).font(.title3)
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
            
            if showDebug {
                ZStack {
                    Color.black.opacity(0.9).ignoresSafeArea()
                    VStack {
                        HStack {
                            Text("DEBUG HTML (Copy this if scanner fails)")
                                .foregroundColor(.white).font(.headline)
                            Spacer()
                            Button(action: { showDebug = false }) {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.red).font(.title)
                            }
                        }
                        .padding()
                        
                        ScrollView {
                            Text(engine.debugHTML)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.green)
                                .padding()
                        }
                        
                        Button(action: {
                            UIPasteboard.general.string = engine.debugHTML
                        }) {
                            Text("Copy to Clipboard")
                                .foregroundColor(.black)
                                .padding()
                                .background(Color.white)
                                .cornerRadius(10)
                        }
                        .padding(.bottom, 50)
                    }
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
    @Published var debugHTML: String = "Tap the red bug icon to scan HTML..."
    
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
