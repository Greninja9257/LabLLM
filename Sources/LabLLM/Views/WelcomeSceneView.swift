import SwiftUI

private enum ParticleRule: CaseIterable { case float, stream, orbit, still }

private struct WordParticle: Identifiable {
    let id = UUID()
    let word: String
    let rule: ParticleRule
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var life: CGFloat
    var maxLife: CGFloat
    var angle: CGFloat
    var angularVelocity: CGFloat
    let size: CGFloat
}

@MainActor
private final class ParticleLife: ObservableObject {
    @Published private(set) var frame = 0
    private(set) var particles = (0 ..< 118).map { _ in WordParticle.make() }
    private var lastTick = Date()

    func advance(at date: Date, reduceMotion: Bool) {
        guard !reduceMotion else { return }
        let delta = min(0.08, max(0.01, date.timeIntervalSince(lastTick)))
        lastTick = date
        for index in particles.indices {
            particles[index].life -= CGFloat(delta)
            if particles[index].life <= 0 { particles[index] = WordParticle.make(); continue }
            switch particles[index].rule {
            case .float:
                particles[index].vx += CGFloat.random(in: -0.006 ... 0.006) * CGFloat(delta)
                particles[index].vy += CGFloat.random(in: -0.004 ... 0.004) * CGFloat(delta)
            case .stream:
                particles[index].vx += CGFloat.random(in: -0.002 ... 0.002) * CGFloat(delta)
            case .orbit:
                particles[index].angle += particles[index].angularVelocity * CGFloat(delta)
                particles[index].x += cos(particles[index].angle) * 0.010 * CGFloat(delta)
                particles[index].y += sin(particles[index].angle) * 0.010 * CGFloat(delta)
            case .still: break
            }
            particles[index].x += particles[index].vx * CGFloat(delta)
            particles[index].y += particles[index].vy * CGFloat(delta)
            if particles[index].x < -0.08 || particles[index].x > 1.08 || particles[index].y < -0.08 || particles[index].y > 1.08 {
                particles[index] = WordParticle.make()
            }
        }
        frame &+= 1
    }
}

private extension WordParticle {
    static func make() -> WordParticle {
        let rule = ParticleRule.allCases.randomElement() ?? .float
        let words = ["attention", "context", "token", "gradient", "learn", "predict", "vector", "layer", "probability", "language", "<|end|>", "{ }", "0101"]
        let life = CGFloat.random(in: 18 ... 65)
        let velocity: (CGFloat, CGFloat)
        switch rule {
        case .float: velocity = (CGFloat.random(in: -0.018 ... 0.018), CGFloat.random(in: -0.014 ... 0.012))
        case .stream: velocity = (CGFloat.random(in: 0.018 ... 0.055), CGFloat.random(in: -0.006 ... 0.006))
        case .orbit: velocity = (0, 0)
        case .still: velocity = (CGFloat.random(in: -0.002 ... 0.002), CGFloat.random(in: -0.002 ... 0.002))
        }
        return WordParticle(word: words.randomElement() ?? "token", rule: rule,
                            x: CGFloat.random(in: 0 ... 1), y: CGFloat.random(in: 0 ... 1),
                            vx: velocity.0, vy: velocity.1, life: life, maxLife: life,
                            angle: CGFloat.random(in: 0 ... .pi * 2), angularVelocity: CGFloat.random(in: -0.55 ... 0.55),
                            size: CGFloat.random(in: 8 ... 14))
    }
}

struct ParticleLifeBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var field = ParticleLife()
    private let ticker = Timer.publish(every: 1.0 / 24.0, on: .main, in: .common).autoconnect()

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            _ = field.frame
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.035, green: 0.055, blue: 0.085)))
            for particle in field.particles {
                let age = max(0, min(1, particle.life / particle.maxLife))
                let fade = min(age * 3, (1 - age) * 3, 1)
                let text = Text(particle.word)
                    .font(.system(size: particle.size, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(red: 0.77, green: 0.86, blue: 0.93).opacity(Double(0.04 + 0.14 * fade)))
                context.draw(text, at: CGPoint(x: particle.x * size.width, y: particle.y * size.height), anchor: .center)
            }
        }
        .onReceive(ticker) { field.advance(at: $0, reduceMotion: reduceMotion) }
        .accessibilityHidden(true)
    }
}
