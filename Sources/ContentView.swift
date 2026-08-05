import SwiftUI
import WebKit

struct ChessWebView: UIViewRepresentable {
    @ObservedObject var engine: LiveEngine
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        
        // FIX FOR LOGIN: Persistent data store
        config.websiteDataStore = WKWebsiteDataStore.default()
        
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        
        let userContentController = WKUserContentController()
        
        // STEALTH SCRIPT
        let stealthScript = """
        Object.defineProperty(navigator, 'webdriver', {get: () => undefined});
        document.body.style.paddingTop = '60px';
        document.body.style.backgroundColor = '#262421';
        document.addEventListener('gesturestart', function (e) { e.preventDefault(); });
        document.body.style.userSelect = 'none';
        """
        userContentController.addUserScript(WKUserScript(source: stealthScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        
        // LIVE BOARD SCANNER SCRIPT (Automatic FEN Detection)
        let scannerScript = """
        var _lastFen = "";
        var _scanInterval = setInterval(function() {
            var _board = document.querySelector('.board');
            if (!_board) return;
            
            var _fen = "";
            var _isBlack = _board.classList.contains('orientation-black');
            
            for (var _r = 0; _r < 8; _r++) {
                var _empty = 0;
                for (var _f = 0; _f < 8; _f++) {
                    var _sqIndex = _isBlack ? (7-_r)*8 + (7-_f) : _r*8 + _f;
                    var _square = _board.querySelector('.square-' + _sqIndex);
                    
                    if (_square) {
                        var _pieceEl = _square.querySelector('.piece');
                        if (_pieceEl) {
                            if (_empty > 0) { _fen += _empty; _empty = 0; }
                            var _cls = _pieceEl.getAttribute('class') || "";
                            var _isWhite = _cls.indexOf('white') !== -1;
                            var _type = 'p';
                            
                            if (_cls.indexOf('knight') !== -1) _type = 'n';
                            else if (_cls.indexOf('bishop') !== -1) _type = 'b';
                            else if (_cls.indexOf('rook') !== -1) _type = 'r';
                            else if (_cls.indexOf('queen') !== -1) _type = 'q';
                            else if (_cls.indexOf('king') !== -1) _type = 'k';
                            
                            _fen += _isWhite ? _type.toUpperCase() : _type.toLowerCase();
                        } else {
                            _empty++;
                        }
                    } else {
                        _empty++;
                    }
                }
                if (_empty > 0) _fen += _empty;
                if (_r < 7) _fen += "/";
            }
            _fen += " w - - 0 1";
            
            if (_fen !== _lastFen && _fen.length > 10) {
                _lastFen = _fen;
                window.webkit.messageHandlers.fenDetector.postMessage(_fen);
            }
        }, 1500);
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
                // Automatically analyze the new position
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
                }
                .padding(.top, 50).padding(.horizontal).background(Color.black.opacity(0.8))
                
                ChessWebView(engine: engine).ignoresSafeArea(edges: .bottom)
            }
            
            if showEngine {
                VStack {
                    Spacer()
                    
                    HStack {
                        Image(systemName: "cpu.fill").foregroundColor(.green)
                        Text(engine.isThinking ? "  Calculating..." : "  Live Engine Active")
                            .font(.caption).foregroundColor(.gray)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 2)
                    
                    EnginePanel(moves: engine.topMoves, isThinking: engine.isThinking)
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
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lock.shield.fill").foregroundColor(.green)
                Text(isThinking ? "  Analyzing Position..." : "  Top 3 Best Moves").font(.headline).foregroundColor(.white)
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

class LiveEngine: ObservableObject {
    @Published var topMoves: [String] = ["Waiting for board..."]
    @Published var isThinking: Bool = false
    @Published var currentURL: String = "https://www.chess.com/play/computer"
    
    private var lastAnalyzedFen: String = ""
    
    func analyzeFEN(_ fen: String) {
        // Prevent analyzing the same position twice
        if fen == lastAnalyzedFen { return }
        lastAnalyzedFen = fen
        
        guard let board = Board.fromFEN(fen) else {
            // If FEN parsing fails (sometimes happens on initial load), wait for next update
            return
        }
        
        isThinking = true
        topMoves = ["Calculating..."]
        
        // Run on background thread to prevent UI freeze
        DispatchQueue.global(qos: .userInitiated).async {
            // Use the powerful SearchV2 engine
            let search = SearchV2(maxNodes: 100_000, timeLimit: 2.0)
            let results = search.topMoves(board, count: 3, maxDepth: 6)
            
            DispatchQueue.main.async {
                if results.isEmpty {
                    self.topMoves = ["No legal moves"]
                } else {
                    // Format moves nicely
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
