import Foundation

extension Board {
    static func fromFEN(_ fen: String) -> Board? {
        let components = fen.split(separator: " ")
        guard components.count >= 1 else { return nil }
        let rows = components[0].split(separator: "/")
        guard rows.count == 8 else { return nil }
        
        var pieces: [Piece?] = Array(repeating: nil, count: 64)
        
        // FEN starts at Rank 8 (top). In our array, Rank 8 starts at index 56.
        var sq = 56 
        
        for row in rows {
            for char in row {
                if let num = Int(String(char)) {
                    // Empty squares
                    for _ in 0..<num {
                        if sq < 64 { pieces[sq] = nil; sq += 1 }
                    }
                } else {
                    let color: ChessColor = char.isUppercase ? .white : .black
                    let type: PieceType?
                    
                    let lowerChar = String(char).lowercased()
                    switch lowerChar {
                    case "p": type = .pawn
                    case "n": type = .knight
                    case "b": type = .bishop
                    case "r": type = .rook
                    case "q": type = .queen
                    case "k": type = .king
                    default: type = nil
                    }
                    
                    if let type = type, sq < 64 {
                        pieces[sq] = Piece(type: type, color: color)
                        sq += 1
                    }
                }
            }
            // Move down one rank (subtract 16 because we go from 56 -> 40 -> 24...)
            sq -= 16
        }
        
        let side: ChessColor = components.count > 1 && components[1] == "b" ? .black : .white
        return Board(pieces: pieces, sideToMove: side)
    }
}
