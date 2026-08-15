import Foundation
import MLX

struct EmbeddingPoint: Identifiable {
    let id = UUID()
    let label: String
    var x: Float
    var y: Float
    var highDim: [Float]   // kept for similarity-based relaxation
}

/// Projects the model's trained token embeddings into 2D so related tokens can be
/// seen clustering together. Position = real PCA of the actual embedding matrix
/// (not decorative); a short force-directed relaxation pass afterward nudges
/// cosine-similar tokens closer, which is what produces the "settling into
/// clusters" motion in the view.
enum EmbeddingMap {
    static func compute(model: GPT, tokenizer: Tokenizer, maxTokens: Int = 140) -> [EmbeddingPoint] {
        let weight = model.tokEmb.weight
        eval(weight)
        let flat = weight.asArray(Float.self)
        let shape = weight.shape2   // (vocab, nEmbd)
        let vocab = shape.0, dim = shape.1
        guard vocab > 1, dim > 0 else { return [] }

        // Sample a spread of ids, skipping the reserved special-token block at the
        // top of the vocab (those aren't "words" and would clutter the map).
        let specialIDs = Set(tokenizer.special.values)
        var candidateIDs = Array(0 ..< vocab).filter { !specialIDs.contains($0) }
        candidateIDs.shuffle()
        let ids = Array(candidateIDs.prefix(maxTokens))
        guard !ids.isEmpty else { return [] }

        var vectors: [[Float]] = ids.map { id in
            Array(flat[(id * dim) ..< (id * dim + dim)])
        }

        // Center.
        var mean = [Float](repeating: 0, count: dim)
        for v in vectors { for i in 0 ..< dim { mean[i] += v[i] } }
        for i in 0 ..< dim { mean[i] /= Float(vectors.count) }
        for i in vectors.indices { for j in 0 ..< dim { vectors[i][j] -= mean[j] } }

        // Covariance (dim x dim), then top-2 components via power iteration + deflation.
        var cov = [[Float]](repeating: [Float](repeating: 0, count: dim), count: dim)
        for v in vectors {
            for a in 0 ..< dim {
                let va = v[a]
                if va == 0 { continue }
                for b in a ..< dim { cov[a][b] += va * v[b] }
            }
        }
        for a in 0 ..< dim { for b in 0 ..< a { cov[a][b] = cov[b][a] } }

        let (pc1, _) = powerIteration(cov, dim: dim)
        let deflated = deflate(cov, dim: dim, vector: pc1)
        let (pc2, _) = powerIteration(deflated, dim: dim)

        var points: [EmbeddingPoint] = []
        for (i, v) in vectors.enumerated() {
            let x = dot(v, pc1), y = dot(v, pc2)
            let label = tokenizer.decode([Int32(ids[i])])
            points.append(EmbeddingPoint(label: label.isEmpty ? "·" : label, x: x, y: y, highDim: v))
        }

        normalize(&points)
        return points
    }

    /// One relaxation step: cosine-similar points attract, all points mildly repel.
    /// Called repeatedly by the view on a timer to animate the "settling" motion.
    static func relax(_ points: inout [EmbeddingPoint], strength: Float = 0.02) {
        let n = points.count
        guard n > 1 else { return }
        var dx = [Float](repeating: 0, count: n)
        var dy = [Float](repeating: 0, count: n)

        for i in 0 ..< n {
            for j in (i + 1) ..< n {
                let vx = points[j].x - points[i].x
                let vy = points[j].y - points[i].y
                let dist = max(sqrt(vx * vx + vy * vy), 0.01)
                let sim = cosine(points[i].highDim, points[j].highDim)   // -1...1

                // Similar tokens attract (pull toward each other); all pairs get a
                // small repulsion so the layout doesn't collapse to a point.
                let attract = max(sim, 0) * strength
                let repel = -strength * 0.35 / (dist * dist)
                let force = attract + repel

                let fx = (vx / dist) * force
                let fy = (vy / dist) * force
                dx[i] += fx; dy[i] += fy
                dx[j] -= fx; dy[j] -= fy
            }
        }
        for i in 0 ..< n { points[i].x += dx[i]; points[i].y += dy[i] }
        normalize(&points)
    }

    // MARK: - Small linear algebra helpers (pure Swift, no MLX)

    private static func powerIteration(_ m: [[Float]], dim: Int, iterations: Int = 60) -> ([Float], Float) {
        var v = (0 ..< dim).map { _ in Float.random(in: -1...1) }
        normalizeVec(&v)
        var eigenvalue: Float = 0
        for _ in 0 ..< iterations {
            var next = [Float](repeating: 0, count: dim)
            for a in 0 ..< dim {
                var s: Float = 0
                for b in 0 ..< dim { s += m[a][b] * v[b] }
                next[a] = s
            }
            eigenvalue = sqrt(next.reduce(0) { $0 + $1 * $1 })
            if eigenvalue > 1e-8 { for i in 0 ..< dim { next[i] /= eigenvalue } }
            v = next
        }
        return (v, eigenvalue)
    }

    private static func deflate(_ m: [[Float]], dim: Int, vector: [Float]) -> [[Float]] {
        var out = m
        // Estimate the eigenvalue via Rayleigh quotient, then subtract λ·v·vᵀ.
        var mv = [Float](repeating: 0, count: dim)
        for a in 0 ..< dim { for b in 0 ..< dim { mv[a] += m[a][b] * vector[b] } }
        let lambda = dot(mv, vector)
        for a in 0 ..< dim { for b in 0 ..< dim { out[a][b] -= lambda * vector[a] * vector[b] } }
        return out
    }

    private static func dot(_ a: [Float], _ b: [Float]) -> Float {
        var s: Float = 0; for i in 0 ..< min(a.count, b.count) { s += a[i] * b[i] }; return s
    }
    private static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        let na = sqrt(dot(a, a)), nb = sqrt(dot(b, b))
        guard na > 1e-8, nb > 1e-8 else { return 0 }
        return dot(a, b) / (na * nb)
    }
    private static func normalizeVec(_ v: inout [Float]) {
        let n = sqrt(dot(v, v)); if n > 1e-8 { for i in v.indices { v[i] /= n } }
    }
    private static func normalize(_ points: inout [EmbeddingPoint]) {
        guard let maxAbs = points.map({ max(abs($0.x), abs($0.y)) }).max(), maxAbs > 1e-6 else { return }
        for i in points.indices { points[i].x /= maxAbs; points[i].y /= maxAbs }
    }
}
