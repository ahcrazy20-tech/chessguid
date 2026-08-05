import SwiftUI
import WebKit

struct ChessWebView: UIViewRepresentable {
    @ObservedObject var engine: LiveEngine
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        
        // FIX FOR LOGIN: Persistent data store & Process Pool
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
        userContentController.addUserScript(WKUserScript(source: stealthScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
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
}

struct ContentView: View {
    @StateObject private var engine = LiveEngine()
    @State private var showEngine = true
    @State private var buttonPosition: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var fenInput: String = ""
    
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
                    
                    // FEN Input for Live Analysis
                    HStack {
                        TextField("Paste FEN here...", text: $fenInput)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .font(.caption)
                        
                        Button(action: { engine.analyzeFEN(fenInput) }) {
                            Image(systemName: "cpu.fill").foregroundColor(.green).font(.title2)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 5)
                    
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
                Text(isThinking ? "  Calculating..." : "  Top 3 Engine Moves").font(.headline).foregroundColor(.white)
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
    @Published var topMoves: [String] = ["Paste FEN & tap CPU to analyze"]
    @Published var isThinking: Bool = false
    @Published var currentURL: String = "https://www.chess.com/play/computer"
    
    func analyzeFEN(_ fen: String) {
        guard let board = Board.fromFEN(fen) else {
            topMoves = ["Invalid FEN format"]
            return
        }
        
        isThinking = true
        topMoves = ["Calculating..."]
        
        // Run on background thread to prevent UI freeze
        DispatchQueue.global(qos: .userInitiated).async {
            let search = SearchV2(maxNodes: 100_000, timeLimit: 2.0)
            let results = search.topMoves(board, count: 3, maxDepth: 6)
            
            DispatchQueue.main.async {
                if results.isEmpty {
                    self.topMoves = ["No legal moves"]
                } else {
                    self.topMoves = results.map { "\($0.san)  (Score: \($0.score / 100))" }
                }
                self.isThinking = false
            }
        }
    }
}
