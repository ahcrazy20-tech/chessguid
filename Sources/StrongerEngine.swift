import Foundation

// MARK: - Improved evaluation
enum EvalV2 {
    static func evaluate(_ b: Board) -> Int {
        var score = 0
        var mobW = 0, mobB = 0

        for sq in 0..<64 {
            guard let p = b.pieces[sq] else { continue }
            let table = Eval.pst(for: p.type)
            let idx = p.color == .white ? sq : (63 - sq)
            let sign = p.color == .white ? 1 : -1
            score += sign * (p.type.value + table[idx])
        }

        var moves: [Move] = []
        moves.reserveCapacity(48)
        for sq in 0..<64 {
            guard let p = b.pieces[sq] else { continue }
            moves.removeAll(keepingCapacity: true)
            MoveGen.pseudoMoves(b, from: sq, piece: p, into: &moves)
            if p.color == .white { mobW += moves.count } else { mobB += moves.count }
        }
        score += (mobW - mobB) * 2

        if let wk = b.kingSquare(.white), wk.file == 4 && wk.rank == 0 && b.fullmoveNumber > 8 {
            score -= 30
        }
        if let bk = b.kingSquare(.black), bk.file == 4 && bk.rank == 7 && b.fullmoveNumber > 8 {
            score += 30
        }

        for file in 0..<8 {
            var w = 0, bl = 0
            for rank in 0..<8 {
                if let p = b.pieces[rank * 8 + file], p.type == .pawn {
                    if p.color == .white { w += 1 } else { bl += 1 }
                }
            }
            if w > 1  { score -= 15 * (w - 1) }
            if bl > 1 { score += 15 * (bl - 1) }
        }

        var wB = 0, bB = 0
        for sq in 0..<64 {
            if let p = b.pieces[sq], p.type == .bishop {
                if p.color == .white { wB += 1 } else { bB += 1 }
            }
        }
        if wB >= 2 { score += 30 }
        if bB >= 2 { score -= 30 }

        return score
    }
}

// MARK: - Stronger search
final class SearchV2 {
    var nodes = 0
    let maxNodes: Int
    let timeLimit: TimeInterval
    var startTime = Date()

    private var tt: [UInt64: (depth: Int, score: Int, flag: TTFlag, bestMove: Move?)] = [:]
    private var killers: [[Move?]] = Array(repeating: [nil, nil], count: 32)

    enum TTFlag { case exact, lower, upper }

    init(maxNodes: Int = 500_000, timeLimit: TimeInterval = 3.0) {
        self.maxNodes = maxNodes
        self.timeLimit = timeLimit
    }

    func topMoves(_ board: Board, count: Int = 3, maxDepth: Int = 6) -> [(move: Move, score: Int, san: String)] {
        startTime = Date()
        nodes = 0
        tt.removeAll(keepingCapacity: true)

        var lastResults: [(Move, Int)] = []
        var moves = MoveGen.legalMoves(board)
        guard !moves.isEmpty else { return [] }

        for depth in 1...maxDepth {
            if outOfBudget() { break }
            var thisDepth: [(Move, Int)] = []
            let ordered = moves.sorted { orderScore(board, $0, ply: 0, ttMove: nil) > orderScore(board, $1, ply: 0, ttMove: nil) }
            for m in ordered {
                var b = board; b.make(m)
                let s = -negamax(b, depth: depth - 1, alpha: -1_000_000, beta: 1_000_000, ply: 1)
                thisDepth.append((m, s))
                if outOfBudget() { break }
            }
            thisDepth.sort { $0.1 > $1.1 }
            lastResults = thisDepth
            moves = thisDepth.map { $0.0 }
        }

        return lastResults.prefix(count).map { (m, s) in (m, s, board.san(for: m)) }
    }

    private func outOfBudget() -> Bool {
        nodes >= maxNodes || Date().timeIntervalSince(startTime) > timeLimit
    }

    private func negamax(_ b: Board, depth: Int, alpha aIn: Int, beta bIn: Int, ply: Int) -> Int {
        nodes += 1
        if depth <= 0 { return quiescence(b, alpha: aIn, beta: bIn) }
        if outOfBudget() { return sign(b.sideToMove) * EvalV2.evaluate(b) }

        let hash = zobristHash(b)
        var ttMove: Move? = nil
        if let entry = tt[hash], entry.depth >= depth {
            switch entry.flag {
            case .exact: return entry.score
            case .lower: if entry.score >= bIn { return entry.score }
            case .upper: if entry.score <= aIn { return entry.score }
            }
            ttMove = entry.bestMove
        }

        let moves = MoveGen.legalMoves(b)
        if moves.isEmpty {
            if MoveGen.inCheck(b, color: b.sideToMove) { return -100_000 + ply }
            return 0
        }

        let ordered = moves.sorted { orderScore(b, $0, ply: ply, ttMove: ttMove) > orderScore(b, $1, ply: ply, ttMove: ttMove) }

        var alpha = aIn
        var best = -1_000_000
        var bestLocal: Move? = nil
        for m in ordered {
            var nb = b; nb.make(m)
            let s = -negamax(nb, depth: depth - 1, alpha: -bIn, beta: -alpha, ply: ply + 1)
            if s > best { best = s; bestLocal = m }
            if best > alpha { alpha = best }
            if alpha >= bIn {
                if b.pieces[m.to] == nil && !m.isCastle && ply < killers.count {
                    if killers[ply][0] != m {
                        killers[ply][1] = killers[ply][0]
                        killers[ply][0] = m
                    }
                }
                break
            }
            if outOfBudget() { break }
        }
        let flag: TTFlag = best <= aIn ? .upper : (best >= bIn ? .lower : .exact)
        tt[hash] = (depth, best, flag, bestLocal)
        return best
    }

    private func quiescence(_ b: Board, alpha aIn: Int, beta: Int) -> Int {
        let stand = sign(b.sideToMove) * EvalV2.evaluate(b)
        if stand >= beta { return beta }
        var alpha = max(aIn, stand)
        let moves = MoveGen.legalMoves(b).filter { b.pieces[$0.to] != nil || $0.isEnPassant }
        let ordered = moves.sorted { orderScore(b, $0, ply: 0, ttMove: nil) > orderScore(b, $1, ply: 0, ttMove: nil) }
        for m in ordered {
            var nb = b; nb.make(m)
            let s = -quiescence(nb, alpha: -beta, beta: -alpha)
            if s >= beta { return beta }
            if s > alpha { alpha = s }
            if outOfBudget() { break }
        }
        return alpha
    }

    private func sign(_ c: ChessColor) -> Int { c == .white ? 1 : -1 }

    private func orderScore(_ b: Board, _ m: Move, ply: Int, ttMove: Move?) -> Int {
        var s = 0
        if let tt = ttMove, tt == m { s += 10_000 }
        if let victim = b.pieces[m.to] {
            let attacker = b.pieces[m.from]?.type.value ?? 0
            s += victim.type.value * 10 - attacker
        }
        if m.promotion != nil { s += 800 }
        if ply < killers.count {
            if killers[ply][0] == m { s += 400 }
            else if killers[ply][1] == m { s += 300 }
        }
        return s
    }

    private func zobristHash(_ b: Board) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for i in 0..<64 {
            if let p = b.pieces[i] {
                let code = UInt64(p.type.rawValue) * 2 + UInt64(p.color.rawValue) + 1
                h = h &* 0x100000001b3
                h ^= code &* UInt64(i + 1)
            }
        }
        h ^= UInt64(b.sideToMove.rawValue)
        return h
    }
}
