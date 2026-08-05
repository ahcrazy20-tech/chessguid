import SwiftUI
import WebKit

// 1. The Chess.com Web Browser
struct ChessWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let webview = WKWebView()
        // Using Lichess because chess.com sometimes blocks WebViews. 
        // You can change this back to "https://www.chess.com/play/computer" if you want.
        let url = URL(string: "https://lichess.org/analysis")! 
        webview.load(URLRequest(url: url))
        return webview
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// 2. The Main App Screen
struct ContentView: View {
    @StateObject private var engine = MockEngine()
    @State private var showEngine = true
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // The Chess Browser
            ChessWebView()
                .ignoresSafeArea()
            
            // The Floating Engine Panel
            if showEngine {
                EnginePanel(moves: engine.topMoves, isThinking: engine.isThinking)
                    .padding()
                    .transition(.move(edge: .bottom))
            }
            
            // Toggle Button to hide/show the panel
            VStack {
                HStack {
                    Spacer()
                    Button(action: { withAnimation { showEngine.toggle() } }) {
                        Image(systemName: showEngine ? "chevron.down.circle.fill" : "chevron.up.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.blue)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(isThinking ? " 🧠 Thinking..." : "✅ Best Moves")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            
            ForEach(Array(moves.enumerated()), id: \.offset) { index, move in
                HStack {
                    Text("#\(index + 1)")
                        .fontWeight(.bold)
                        .foregroundColor(index == 0 ? .green : (index == 1 ? .yellow : .orange))
                        .frame(width: 25)
                    Text(move)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(8)
                .background(Color.white.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding()
        .background(Color.black.opacity(0.85))
        .cornerRadius(15)
        .shadow(radius: 10)
    }
}

// 4. The Simulated Engine (Replaces the broken Process code)
class MockEngine: ObservableObject {
    @Published var topMoves: [String] = ["Waiting for board..."]
    @Published var isThinking: Bool = false
    
    func startAnalyzing() {
        isThinking = true
        
        // Simulate the engine thinking for 1.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.topMoves = [
                "#1: e2-e4 (+0.3)",
                "#2: d2-d4 (+0.2)",
                "#3: Ng1-f3 (+0.1)"
            ]
            self.isThinking = false
        }
    }
}
