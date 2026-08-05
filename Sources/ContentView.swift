import SwiftUI

struct ContentView: View {
    @State private var fenInput = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    @State private var moves: [String] = []
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Chess Helper (TrollStore)")
                    .font(.largeTitle).bold()
                
                TextField("Paste FEN here...", text: $fenInput)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .padding(.horizontal)
                
                Button(action: analyzePosition) {
                    Text("Analyze Position")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                
                if !moves.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(moves.enumerated()), id: \.offset) { index, move in
                            HStack {
                                Text("#\(index + 1)")
                                    .fontWeight(.bold)
                                    .frame(width: 30)
                                Text(move)
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                            }
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .padding(.top)
            .navigationTitle("Helper")
        }
    }
    
    func analyzePosition() {
        // Placeholder: Replace this later with actual Stockfish engine calls
        moves = [
            "1. e2e4 (Score: +0.3)",
            "2. d2d4 (Score: +0.2)",
            "3. Ng1f3 (Score: +0.1)"
        ]
    }
}
