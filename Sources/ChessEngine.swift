import Foundation

// MARK: - Types
enum PieceType: Int, CaseIterable {
    case pawn = 0, knight, bishop, rook, queen, king
    var value: Int {
        switch self {
        case .pawn: return 100
        case .knight: return 320
        case .bishop: return 330
        case .rook: return 500
        case .queen: return 900
        case .king: return 20000
        }
    }
    var letter: String {
        switch self {
        case .pawn: return ""
        case .knight: return "N"
        case .bishop: return "B"
        case .rook: return "R"
        case .queen: return "Q"
        case .king: return "K"
        }
    }
}

enum ChessColor: Int {
    case white = 0, black
    var opposite: ChessColor { self == .white ? .black : .white }
}

struct Piece: Hashable {
    let type: PieceType
    let color: ChessColor
}

typealias Square = Int

extension Square {
    var file: Int { self & 7 }
    var rank: Int { self >> 3 }
    var name: String { "\(Character(UnicodeScalar(97 + file)!))\(rank + 1)" }
    static func from(_ name: String) -> Square? {
        guard name.count == 2 else { return nil }
        let cs = Array(name)
        guard let a = cs[0].asciiValue, a >= 97, a <= 104 else { return nil }
        guard let r = cs[1].wholeNumberValue, r >= 1, r <= 8 else { return nil }
        return (r - 1) * 8 + Int(a) - 97
    }
    static func at(file: Int, rank: Int) -> Square? {
        guard (0..<8).contains(file), (0..<8).contains(rank) else { return nil }
        return rank * 8 + file
    }
}

struct Move: Hashable {
    let from: Square
    let to: Square
    let promotion: PieceType?
    let isCastle: Bool
    let isEnPassant: Bool

    init(from: Square, to: Square, promotion: PieceType? = nil,
         isCastle: Bool = false, isEnPassant: Bool = false) {
        self.from = from; self.to = to; self.promotion = promotion
        self.isCastle = isCastle; self.isEnPassant = isEnPassant
    }
    var uci: String {
        var s = from.name + to.name
        if let p = promotion { s += p.letter.lowercased() }
        return s
    }
}

struct Board {
    var pieces: [Piece?]
    var sideToMove: ChessColor
    var castleWK: Bool = true
    var castleWQ: Bool = true
    var castleBK: Bool = true
    var castleBQ: Bool = true
    var enPassant: Square? = nil
    var halfmoveClock: Int = 0
    var fullmoveNumber: Int = 1
    var history: [Move] = []

    static var initial: Board {
        var pieces: [Piece?] = Array(repeating: nil, count: 64)
        let back: [PieceType] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]
        for f in 0..<8 {
            pieces[0 + f]  = Piece(type: back[f], color: .white)
            pieces[8 + f]  = Piece(type: .pawn,  color: .white)
            pieces[48 + f] = Piece(type: .pawn,  color: .black)
            pieces[56 + f] = Piece(type: back[f], color: .black)
        }
        return Board(pieces: pieces, sideToMove: .white)
    }

    func piece(at sq: Square) -> Piece? { pieces[sq] }

    func kingSquare(_ color: ChessColor) -> Square? {
        for i in 0..<64 {
            if let p = pieces[i], p.type == .king, p.color == color { return i }
        }
        return nil
    }
}

// MARK: - Move generation
enum MoveGen {
    static let knightOffsets: [(Int, Int)] = [(1, 2), (2, 1), (-1, 2), (-2, 1), (1, -2), (2, -1), (-1, -2), (-2, -1)]
    static let kingOffsets: [(Int, Int)] = [(0, 1), (1, 0), (0, -1), (-1, 0), (1, 1), (1, -1), (-1, 1), (-1, -1)]
    static let rookDirs: [(Int, Int)] = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    static let bishopDirs: [(Int, Int)] = [(1, 1), (1, -1), (-1, 1), (-1, -1)]

    static func legalMoves(_ board: Board) -> [Move] {
        var out: [Move] = []
        let side = board.sideToMove
        for sq in 0..<64 {
            guard let p = board.pieces[sq], p.color == side else { continue }
            pseudoMoves(board, from: sq, piece: p, into: &out)
        }
        return out.filter { move in
            var b = board; b.make(move)
            if let ks = b.kingSquare(side) {
                return !isAttacked(b, square: ks, by: side.opposite)
            }
            return false
        }
    }

    static func pseudoMoves(_ board: Board, from: Square, piece: Piece, into out: inout [Move]) {
        switch piece.type {
        case .pawn:   pawnMoves(board, from: from, piece: piece, into: &out)
        case .knight: leaperMoves(board, from: from, piece: piece, offsets: knightOffsets, into: &out)
        case .bishop: sliderMoves(board, from: from, piece: piece, dirs: bishopDirs, into: &out)
        case .rook:   sliderMoves(board, from: from, piece: piece, dirs: rookDirs, into: &out)
        case .queen:
            sliderMoves(board, from: from, piece: piece, dirs: rookDirs, into: &out)
            sliderMoves(board, from: from, piece: piece, dirs: bishopDirs, into: &out)
        case .king:
            leaperMoves(board, from: from, piece: piece, offsets: kingOffsets, into: &out)
            castlingMoves(board, piece: piece, into: &out)
        }
    }

    static func pawnMoves(_ b: Board, from: Square, piece: Piece, into out: inout [Move]) {
        let dir = piece.color == .white ? 1 : -1
        let startRank = piece.color == .white ? 1 : 6
        let promoRank = piece.color == .white ? 7 : 0
        let f = from.file, r = from.rank

        if let s1 = Square.at(file: f, rank: r + dir), b.pieces[s1] == nil {
            if s1.rank == promoRank {
                for pt in [PieceType.queen, .rook, .bishop, .knight] {
                    out.append(Move(from: from, to: s1, promotion: pt))
                }
            } else {
                out.append(Move(from: from, to: s1))
                if r == startRank, let s2 = Square.at(file: f, rank: r + 2 * dir), b.pieces[s2] == nil {
                    out.append(Move(from: from, to: s2))
                }
            }
        }
        for df in [-1, 1] {
            guard let s = Square.at(file: f + df, rank: r + dir) else { continue }
            if let target = b.pieces[s], target.color != piece.color {
                if s.rank == promoRank {
                    for pt in [PieceType.queen, .rook, .bishop, .knight] {
                        out.append(Move(from: from, to: s, promotion: pt))
                    }
                } else { out.append(Move(from: from, to: s)) }
            } else if let ep = b.enPassant, ep == s {
                out.append(Move(from: from, to: s, isEnPassant: true))
            }
        }
    }

    static func leaperMoves(_ b: Board, from: Square, piece: Piece, offsets: [(Int, Int)], into out: inout [Move]) {
        for (df, dr) in offsets {
            guard let s = Square.at(file: from.file + df, rank: from.rank + dr) else { continue }
            if let target = b.pieces[s], target.color == piece.color { continue }
            out.append(Move(from: from, to: s))
        }
    }

    static func sliderMoves(_ b: Board, from: Square, piece: Piece, dirs: [(Int, Int)], into out: inout [Move]) {
        for (df, dr) in dirs {
            var f = from.file + df, r = from.rank + dr
            while let s = Square.at(file: f, rank: r) {
                if let target = b.pieces[s] {
                    if target.color != piece.color { out.append(Move(from: from, to: s)) }
                    break
                }
                out.append(Move(from: from, to: s))
                f += df; r += dr
            }
        }
    }

    static func castlingMoves(_ b: Board, piece: Piece, into out: inout [Move]) {
        let backRank = piece.color == .white ? 0 : 7
        let kingSq = Square.at(file: 4, rank: backRank)!
        guard b.pieces[kingSq]?.type == .king, b.pieces[kingSq]?.color == piece.color else { return }
        
        let kingSide  = piece.color == .white ? b.castleWK : b.castleBK
        let queenSide = piece.color == .white ? b.castleWQ : b.castleBQ

        if kingSide,
           b.pieces[Square.at(file: 5, rank: backRank)!] == nil,
           b.pieces[Square.at(file: 6, rank: backRank)!] == nil,
           b.pieces[Square.at(file: 7, rank: backRank)!]?.type == .rook,
           !isAttacked(b, square: kingSq, by: piece.color.opposite),
           !isAttacked(b, square: Square.at(file: 5, rank: backRank)!, by: piece.color.opposite),
           !isAttacked(b, square: Square.at(file: 6, rank: backRank)!, by: piece.color.opposite) {
            out.append(Move(from: kingSq, to: Square.at(file: 6, rank: backRank)!, isCastle: true))
        }
        if queenSide,
           b.pieces[Square.at(file: 3, rank: backRank)!] == nil,
           b.pieces[Square.at(file: 2, rank: backRank)!] == nil,
           b.pieces[Square.at(file: 1, rank: backRank)!] == nil,
           b.pieces[Square.at(file: 0, rank: backRank)!]?.type == .rook,
           !isAttacked(b, square: kingSq, by: piece.color.opposite),
           !isAttacked(b, square: Square.at(file: 3, rank: backRank)!, by: piece.color.opposite),
           !isAttacked(b, square: Square.at(file: 2, rank: backRank)!, by: piece.color.opposite) {
            out.append(Move(from: kingSq, to: Square.at(file: 2, rank: backRank)!, isCastle: true))
        }
    }

    static func isAttacked(_ b: Board, square: Square, by: ChessColor) -> Bool {
        let f = square.file, r = square.rank
        let dir = by == .white ? -1 : 1
        for df in [-1, 1] {
            if let s = Square.at(file: f + df, rank: r + dir),
               let p = b.pieces[s], p.color == by, p.type == .pawn { return true }
        }
        for (df, dr) in knightOffsets {
            if let s = Square.at(file: f + df, rank: r + dr),
               let p = b.pieces[s], p.color == by, p.type == .knight { return true }
        }
        for (df, dr) in kingOffsets {
            if let s = Square.at(file: f + df, rank: r + dr),
               let p = b.pieces[s], p.color == by, p.type == .king { return true }
        }
        for (df, dr) in rookDirs {
            var ff = f + df, rr = r + dr
            while let s = Square.at(file: ff, rank: rr) {
                if let p = b.pieces[s] {
                    if p.color == by, (p.type == .rook || p.type == .queen) { return true }
                    break
                }
                ff += df; rr += dr
            }
        }
        for (df, dr) in bishopDirs {
            var ff = f + df, rr = r + dr
            while let s = Square.at(file: ff, rank: rr) {
                if let p = b.pieces[s] {
                    if p.color == by, (p.type == .bishop || p.type == .queen) { return true }
                    break
                }
                ff += df; rr += dr
            }
        }
        return false
    }

    static func inCheck(_ b: Board, color: ChessColor) -> Bool {
        guard let ks = b.kingSquare(color) else { return false }
        return isAttacked(b, square: ks, by: color.opposite)
    }
}

// MARK: - Make move
extension Board {
    mutating func make(_ move: Move) {
        history.append(move)
        let moving = pieces[move.from]!
        let captured = pieces[move.to]

        pieces[move.from] = nil
        pieces[move.to] = moving

        if move.isEnPassant {
            let capSq = moving.color == .white ? move.to - 8 : move.to + 8
            pieces[capSq] = nil
        }
        if let promo = move.promotion {
            pieces[move.to] = Piece(type: promo, color: moving.color)
        }
        if move.isCastle {
            let backRank = moving.color == .white ? 0 : 7
            if move.to.file == 6 {
                pieces[Square.at(file: 5, rank: backRank)!] = pieces[Square.at(file: 7, rank: backRank)!]
                pieces[Square.at(file: 7, rank: backRank)!] = nil
            } else {
                pieces[Square.at(file: 3, rank: backRank)!] = pieces[Square.at(file: 0, rank: backRank)!]
                pieces[Square.at(file: 0, rank: backRank)!] = nil
            }
        }

        if moving.type == .king {
            if moving.color == .white { castleWK = false; castleWQ = false }
            else { castleBK = false; castleBQ = false }
        }
        if move.from == 0  || move.to == 0  { castleWQ = false }
        if move.from == 7  || move.to == 7  { castleWK = false }
        if move.from == 56 || move.to == 56 { castleBQ = false }
        if move.from == 63 || move.to == 63 { castleBK = false }

        enPassant = nil
        if moving.type == .pawn && abs(move.to.rank - move.from.rank) == 2 {
            enPassant = (move.from + move.to) / 2
        }

        if moving.type == .pawn || captured != nil {
            halfmoveClock = 0
        } else {
            halfmoveClock += 1
        }
        if sideToMove == .black { fullmoveNumber += 1 }
        sideToMove = sideToMove.opposite
    }
}

// MARK: - Evaluation
enum Eval {
    static let pstPawn: [Int] = [
        0,  0,  0,  0,  0,  0,  0,  0,
        5, 10, 10,-20,-20, 10, 10,  5,
        5, -5,-10,  0,  0,-10, -5,  5,
        0,  0,  0, 20, 20,  0,  0,  0,
        5,  5, 10, 25, 25, 10,  5,  5,
        10, 10, 20, 30, 30, 20, 10, 10,
        50, 50, 50, 50, 50, 50, 50, 50,
        0,  0,  0,  0,  0,  0,  0,  0
    ]
    static let pstKnight: [Int] = [
        -50,-40,-30,-30,-30,-30,-40,-50,
        -40,-20,  0,  5,  5,  0,-20,-40,
        -30,  5, 10, 15, 15, 10,  5,-30,
        -30,  0, 15, 20, 20, 15,  0,-30,
        -30,  5, 15, 20, 20, 15,  5,-30,
        -30,  0, 10, 15, 15, 10,  0,-30,
        -40,-20,  0,  0,  0,  0,-20,-40,
        -50,-40,-30,-30,-30,-30,-40,-50
    ]
    static let pstBishop: [Int] = [
        -20,-10,-10,-10,-10,-10,-10,-20,
        -10,  0,  0,  0,  0,  0,  5,-10,
        -10, 10, 10, 10, 10, 10, 10,-10,
        -10,  0, 10, 10, 10, 10,  0,-10,
        -10,  5,  5, 10, 10,  5,  5,-10,
        -10,  0,  5, 10, 10,  5,  0,-10,
        -10,  0,  0,  0,  0,  0,  0,-10,
        -20,-10,-10,-10,-10,-10,-10,-20
    ]
    static let pstRook: [Int] = [
        0,  0,  5, 10, 10,  5,  0,  0,
        -5,  0,  0,  0,  0,  0,  0, -5,
        -5,  0,  0,  0,  0,  0,  0, -5,
        -5,  0,  0,  0,  0,  0,  0, -5,
        -5,  0,  0,  0,  0,  0,  0, -5,
        -5,  0,  0,  0,  0,  0,  0, -5,
        5, 10, 10, 10, 10, 10, 10,  5,
        0,  0,  0,  0,  0,  0,  0,  0
    ]
    static let pstQueen: [Int] = [
        -20,-10,-10, -5, -5,-10,-10,-20,
        -10,  0,  5,  0,  0,  0,  0,-10,
        -10,  5,  5,  5,  5,  5,  0,-10,
        0,  0,  5,  5,  5,  5,  0, -5,
        -5,  0,  5,  5,  5,  5,  0, -5,
        -10,  0,  5,  5,  5,  5,  0,-10,
        -10,  0,  0,  0,  0,  0,  0,-10,
        -20,-10,-10, -5, -5,-10,-10,-20
    ]
    static let pstKing: [Int] = [
        20, 30, 10,  0,  0, 10, 30, 20,
        20, 20,  0,  0,  0,  0, 20, 20,
        -10,-20,-20,-20,-20,-20,-20,-10,
        -20,-30,-30,-40,-40,-30,-30,-20,
        -30,-40,-40,-50,-50,-40,-40,-30,
        -30,-40,-40,-50,-50,-40,-40,-30,
        -30,-40,-40,-50,-50,-40,-40,-30,
        -30,-40,-40,-50,-50,-40,-40,-30
    ]

    static func pst(for type: PieceType) -> [Int] {
        switch type {
        case .pawn:   return pstPawn
        case .knight: return pstKnight
        case .bishop: return pstBishop
        case .rook:   return pstRook
        case .queen:  return pstQueen
        case .king:   return pstKing
        }
    }

    static func evaluate(_ b: Board) -> Int {
        var score = 0
        for sq in 0..<64 {
            guard let p = b.pieces[sq] else { continue }
            let material = p.type.value
            let table = pst(for: p.type)
            let idx = p.color == .white ? sq : (63 - sq)
            let posBonus = table[idx]
            let sign = p.color == .white ? 1 : -1
            score += sign * (material + posBonus)
        }
        return score
    }
}

// MARK: - Search
final class Search {
    var nodes = 0
    let maxNodes: Int
    let timeLimit: TimeInterval
    var startTime = Date()

    init(maxNodes: Int = 200_000, timeLimit: TimeInterval = 2.5) {
        self.maxNodes = maxNodes
        self.timeLimit = timeLimit
    }

    func topMoves(_ board: Board, count: Int = 3, depth: Int = 4) -> [(move: Move, score: Int, san: String)] {
        startTime = Date()
        nodes = 0
        let moves = MoveGen.legalMoves(board)
        guard !moves.isEmpty else { return [] }

        var scored: [(Move, Int)] = []
        for m in moves {
            var b = board; b.make(m)
            let s = -negamax(b, depth: depth - 1, alpha: -1_000_000, beta: 1_000_000, color: b.sideToMove)
            scored.append((m, s))
            if outOfBudget() { break }
        }
        scored.sort { $0.1 > $1.1 }
        return scored.prefix(count).map { (m, s) in (m, s, board.san(for: m)) }
    }

    private func outOfBudget() -> Bool {
        if nodes >= maxNodes { return true }
        return Date().timeIntervalSince(startTime) > timeLimit
    }

    private func negamax(_ b: Board, depth: Int, alpha aIn: Int, beta: Int, color: ChessColor) -> Int {
        nodes += 1
        if depth <= 0 { return quiescence(b, alpha: aIn, beta: beta, color: color) }
        if outOfBudget() { return sign(color) * Eval.evaluate(b) }

        let moves = MoveGen.legalMoves(b)
        if moves.isEmpty {
            if MoveGen.inCheck(b, color: b.sideToMove) {
                return -100_000 + (10 - depth)
            }
            return 0
        }
        let ordered = moves.sorted { orderScore(b, $0) > orderScore(b, $1) }

        var alpha = aIn
        var best = -1_000_000
        for m in ordered {
            var nb = b; nb.make(m)
            let s = -negamax(nb, depth: depth - 1, alpha: -beta, beta: -alpha, color: nb.sideToMove)
            if s > best { best = s }
            if best > alpha { alpha = best }
            if alpha >= beta { break }
            if outOfBudget() { break }
        }
        return best
    }

    private func quiescence(_ b: Board, alpha aIn: Int, beta: Int, color: ChessColor) -> Int {
        let stand = sign(color) * Eval.evaluate(b)
        if stand >= beta { return beta }
        var alpha = max(aIn, stand)
        let moves = MoveGen.legalMoves(b).filter { b.pieces[$0.to] != nil || $0.isEnPassant }
        let ordered = moves.sorted { orderScore(b, $0) > orderScore(b, $1) }
        for m in ordered {
            var nb = b; nb.make(m)
            let s = -quiescence(nb, alpha: -beta, beta: -alpha, color: nb.sideToMove)
            if s >= beta { return beta }
            if s > alpha { alpha = s }
            if outOfBudget() { break }
        }
        return alpha
    }

    private func sign(_ c: ChessColor) -> Int { c == .white ? 1 : -1 }

    private func orderScore(_ b: Board, _ m: Move) -> Int {
        var s = 0
        if let victim = b.pieces[m.to] {
            let attacker = b.pieces[m.from]?.type.value ?? 0
            s += victim.type.value * 10 - attacker
        }
        if m.promotion != nil { 
