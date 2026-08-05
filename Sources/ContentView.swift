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
        
        // 2. THE SMART SCANNER (Orientation-independent, reads image files)
        let scannerScript = """
        var _lastFen = "";
        
        function getFENSmart() {
            // Find the board by looking for a div with exactly 64 square-like children
            var boards = document.querySelectorAll('div');
            var boardEl = null;
            for (var i = 0; i < boards.length; i++) {
                if (boards[i].children.length === 64) {
                    if (boards[i].children[0].className.includes('square')) {
                        boardEl = boards[i];
                        break;
                    }
                }
            }
            if (!boardEl) return null;

            var squares = Array.prototype.slice.call(boardEl.children);
            
            // Sort squares by visual position (top to bottom, left to right)
            // This makes it work for both White and Black orientation automatically!
            squares.sort(function(a, b) {
                var rectA = a.getBoundingClientRect();
                var rectB = b.getBoundingClientRect();
                if (Math.abs(rectA.top - rectB.top) > 10) {
                    return rectA.top - rectB.top;
                }
                return rectA.left - rectB.left;
            });

            var fen = "";
            for (var i = 0; i < 64; i++) {
                var img = squares[i].querySelector('img');
                var piece = null;
                
                if (img && img.src) {
                    var src = img.src.toLowerCase();
                    // Read piece from image filename (e.g., wP.png, bK.png)
                    if (src.includes('wp') || src.includes('white-pawn')) piece = 'P';
                    else if (src.includes('wn') || src.includes('white-knight')) piece = 'N';
                    else if (src.includes('wb') || src.includes('white-bishop')) piece = 'B';
                    else if (src.includes('wr') || src.includes('white-rook')) piece = 'R';
                    else if (src.includes('wq') || src.includes('white-queen')) piece = 'Q';
                    else if (src.includes('wk') || src.includes('white-king')) piece = 'K';
                    else if (src.includes('bp') || src.includes('black-pawn')) piece = 'p';
                    else if (src.includes('bn') || src.includes('black-knight')) piece = 'n';
                    else if (src.includes('bb') || src.includes('black-bishop')) piece = 'b';
                    else if (src.includes('br') || src.includes('black-rook')) piece = 'r';
                    else if (src.includes('bq') || src.includes('black-queen')) piece = 'q';
                    else if (src.includes('bk') || src.includes('black-king')) piece = 'k';
                }
                
                if (piece) {
                    fen += piece;
                } else {
                    // Count consecutive empty squares in the same row
                    var emptyCount = 1;
                    while (i + 1 < 64 && squares[i+1].querySelector('img') === null) {
                        var rectCurr = squares[i].getBoundingClientRect();
                        var rectNext = squares[i+1].getBoundingClientRect();
                        // Check if next square is visually in the same row
                        if (Math.abs(rectCurr.top - rectNext.top) < 10) {
                            emptyCount++;
                            i++;
                        } else {
                            break;
                        }
                    }
                    fen += emptyCount;
                }
                
                // Add '/' at the end of each row (every 8 squares)
                if ((i + 1) % 8 === 0 && i < 63) {
                    fen += '/';
                }
            }
            return fen + " w - - 0 1";
        }
        
        function stealthScan() {
            // Check every 3 seconds
            setTimeout(stealthScan, 3000);
            try {
                var fen = getFENSmart();
                if (fen && fen.length > 10 && fen !== _lastFen && !fen.includes('8/8/8/8/8/8/8/8')) {
                    _lastFen = fen;
                    window.webkit.messageHandlers.fenDetector.postMessage(fen);
                }
            } catch(e) {}
        }
        
        // Start scanning after 2 seconds
        setTimeout(stealthScan, 2000);
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
