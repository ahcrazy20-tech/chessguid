import SwiftUI
import WebKit

// 1. The Chess.com Web Browser (Fixed to load real chess.com)
struct ChessWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        
        // TRICK: Spoof the User-Agent so chess.com thinks we are Safari
        config.applicationNameForUserAgent = "Version/17.0 Mobile/15E148 Safari/604.1"
        
        let webview = WKWebView(frame: .zero, configuration: config)
        
        // Fix the black screen: Make background transparent and force full size
        webview.backgroundColor = UIColor.systemBackground
        webview.isOpaque = true
        webview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        // Load real chess.com
        let url = URL(string: "https://www.chess.com/play/computer")!
        webview.load(URLRequest(url: url))
        
        return webview
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Force the webview to fill the screen
        uiView.frame = UIScreen.main.bounds
    }
}

// 2. The Main App Screen
struct ContentView: View {
    @StateObject private var engine = MockEngine()
    @State private var showEngine = true
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // The Chess Browser (Fills entire screen)
            ChessWebView()
                .ignoresSafeArea()
            
            // The Floating Engine Panel (Fixed positioning)
            if showEngine {
                VStack {
                    Spacer() // Pushes the panel to the bottom
                    
                    EnginePanel(moves: engine.topMoves, isThinking: engine.isThinking)
                        .padding(.horizontal)
                        .padding(.bottom, 40) // Lift it up so it doesn't touch the home bar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            
            // Toggle Button (Top Right)
            VStack {
                HStack {
                    Spacer()
                    Button(action: { 
                        withAnimation(.spring()) { showEngine.toggle() } 
                    }) {
                        Image(systemName: showEngine ? "eye.slash.circle.fill" : "eye.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.blue)
                            .shadow(radius: 5)
                            .padding()
                    }
                }
                Spacer()
            }
        }
        .onAppear {
            engine.startAnalyzing()
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
                Image(systemName: "cpu.fill")
                    .foregroundColor(.blue)
                Text(isThinking ? "Calculating best moves..." : "Top 3 Engine Moves")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            
            Divider().background(Color.white.opacity(0.3))
            
            ForEach(Array(moves.enumerated()), id: \.offset) { index, move in
                HStack {
                    Text("#\(index + 1)")
                        .fontWeight(.bold)
                        .foregroundColor(index == 0 ? .green : (index == 1 ? .yellow : .orange))
                        .frame(width: 30, alignment: .center)
                    
                    Text(move)
                        .font(.system(.body, design: .monospaced).bold())
                        .foregroundColor(.white)
                    
                    Spacer()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.black.opacity(0.90))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.5), radius: 15, x: 0, y: 10)
    }
}

// 4. The Engine Logic
class MockEngine: ObservableObject {
    @Published var topMoves: [String] = ["Waiting for board..."]
    @Published var isThinking: Bool = false
    
    func startAnalyzing() {
        isThinking = true
        
        // Simulate thinking
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.topMoves = [
                "e2-e4  (Score: +0.3)",
                "d2-d4  (Score: +0.2)",
                "Ng1-f3 (Score: +0.1)"
            ]
            self.isThinking = false
        }
    }
}
