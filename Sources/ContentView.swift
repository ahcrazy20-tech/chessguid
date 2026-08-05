import SwiftUI
import WebKit
import Foundation

// 1. The Chess.com Web Browser
struct ChessWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let webview = WKWebView()
        let url = URL(string: "https://www.chess.com/play/computer")! // Opens chess.com
        webview.load(URLRequest(url: url))
        return webview
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// 2. The Main App Screen
struct ContentView: View {
    @StateObject private var engine = StockfishEngine()
    @State private var showEngine = true
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // The Chess.com Browser
            ChessWebView()
                .ignoresSafeArea()
            
            // The Floating Engine Panel
            if showEngine {
                EnginePanel(moves: engine.topMoves, isThinking: engine.isThinking)
                    .padding()
                    .transition(.move(edge: .bottom))
            }
            
            // Toggle Button
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
            engine.startEngine()
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
                Text(isThinking ? " Thinking..." : "✅ Best Moves")
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

// 4. The Stockfish Engine Logic
class StockfishEngine: ObservableObject {
    @Published var topMoves: [String] = ["Waiting for engine..."]
    @Published var isThinking: Bool = false
    
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    
    func startEngine() {
        // Find the stockfish binary inside the app bundle
        guard let stockfishPath = Bundle.main.path(forResource: "stockfish", ofType: nil) else {
            topMoves = ["Error: Engine not found"]
            return
        }
        
        process = Process()
        process?.executableURL = URL(fileURLWithPath: stockfishPath)
        
        inputPipe = Pipe()
        outputPipe = Pipe()
        
        process?.standardInput = inputPipe
        process?.standardOutput = outputPipe
        
        // Read engine output
        outputPipe?.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let output = String(data: data, encoding: .utf8) else { return }
            self?.parseOutput(output)
        }
        
        try? process?.run()
        
        // Initialize UCI
        sendCommand("uci")
        sendCommand("setoption name MultiPV value 3") // Ask for top 3 moves
        sendCommand("isready")
        
        // Start analyzing the starting position
        analyzeFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
    }
    
    func analyzeFen(_ fen: String) {
        isThinking = true
        sendCommand("position fen \(fen)")
        sendCommand("go depth 15") // Depth 15 is fast and strong
    }
    
    private func sendCommand(_ command: String) {
        let data = (command + "\n").data(using: .utf8)!
        inputPipe?.fileHandleForWriting.write(data)
    }
    
    private func parseOutput(_ output: String) {
        let lines = output.components(separatedBy: "\n")
        var currentMoves: [String] = []
        
        for line in lines {
            if line.contains("info") && line.contains("pv") && line.contains("multipv") {
                if let move = extractMove(from: line) {
                    currentMoves.append(move)
                }
            }
        }
        
        if !currentMoves.isEmpty {
            DispatchQueue.main.async {
                self.topMoves = currentMoves
                self.isThinking = false
            }
        }
    }
    
    private func extractMove(from line: String) -> String? {
        let parts = line.components(separatedBy: " ")
        guard let pvIndex = parts.firstIndex(of: "pv"),
              let multiPVIndex = parts.firstIndex(of: "multipv") else { return nil }
        
        let rank = parts[multiPVIndex + 1]
        let pv = parts[(pvIndex + 1)...].joined(separator: " ")
        let bestMove = pv.components(separatedBy: " ").first ?? ""
        
        // Format the move nicely (e.g., e2e4 -> e2-e4)
        if bestMove.count == 4 {
            return "#\(rank): \(bestMove.prefix(2))-\(bestMove.suffix(2))"
        }
        return "#\(rank): \(bestMove)"
    }
}
