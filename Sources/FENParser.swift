import Foundation

extension Board {
    static func fromFEN(_ fen: String) -> Board? {
        let components = fen.split(separator: " ")
        guard components.count >= 1 else { return nil }
        let rows = components[0].split(separator: "/")
        guard rows.count == 8 else { return nil }
        
        var pieces: [Piece?] = Array(repeating: nil, count: 64)
        var sq = 56 // Start from a8 (top-left)
        
        for row in rows {
            var fileInRow = 0
            for char in row {
                if let num = Int(String(char)) {
                    // Empty squares
                    sq += num
                    fileInRow += num
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
                    }
                    sq += 1
                    fileInRow += 1
                }
            }
            // Move to next rank (go down 2 ranks in our indexing)
            sq = 56 - (8 - fileInRow) - (7 - rows.firstIndex(of: row)!) * 8
        }
        
        let side: ChessColor = components.count > 1 && components[1] == "b" ? .black : .white
        return Board(pieces: pieces, sideToMove: side)
    }
}
