import Foundation
import Testing

// La animación de carga de la IA (el atardecer del icono): que el sol nunca se salga de su
// sitio, que la descarga lo haga subir y que la imagen quieta sea la del icono.

@Suite("Animación del atardecer")
struct SunsetMotionTests {
    private let times = stride(from: 0.0, through: 12.0, by: 0.05).map { $0 }

    @Test func theSunStaysBetweenHiddenAndHalfOut() {
        for phase in [SunsetMotion.Phase.preparing, .thinking, .progress(-1), .progress(0.4), .progress(2)] {
            for time in times {
                let rise = SunsetMotion.rise(phase, at: time)
                #expect(rise >= 0 && rise <= 1, "\(phase) en \(time)")
            }
        }
    }

    @Test func preparingRisesAndSetsThinkingStaysUp() {
        let preparing = times.map { SunsetMotion.rise(.preparing, at: $0) }
        #expect(preparing.min()! < 0.35 && preparing.max()! > 0.95)
        let thinking = times.map { SunsetMotion.rise(.thinking, at: $0) }
        #expect(thinking.min()! > 0.89)
    }

    @Test func downloadingRaisesTheSunWithProgress() {
        let steps = stride(from: 0.0, through: 1.0, by: 0.1).map { SunsetMotion.rise(.progress($0), at: 3) }
        #expect(zip(steps, steps.dropFirst()).allSatisfy { $0 < $1 })
        #expect(abs(SunsetMotion.rise(.progress(1), at: 0) - 1) < 1e-9)
        #expect(abs(SunsetMotion.rise(.progress(5), at: 0) - 1) < 1e-9)
    }

    @Test func rippleRunsDownTheReflection() {
        for time in times {
            for index in SunsetMotion.Icon.bars.indices {
                #expect(abs(SunsetMotion.ripple(index, at: time)) <= 1)
            }
        }
        // Cada barra va un poco por detrás de la de encima.
        #expect(SunsetMotion.ripple(0, at: 0.3) != SunsetMotion.ripple(1, at: 0.3))
    }

    @Test func theGlintCrossesTheHorizon() {
        let positions = times.map { SunsetMotion.glint(at: $0) }
        #expect(positions.min()! < 0 && positions.max()! > 1)
        #expect(positions.allSatisfy { $0 >= -0.25 && $0 <= 1.25 })
    }

    @Test func stillFrameLooksLikeTheIcon() {
        // Con «Reducir movimiento»: el sol arriba y el destello en el centro.
        #expect(SunsetMotion.rise(.preparing, at: SunsetMotion.stillTime) > 0.95)
        #expect(abs(SunsetMotion.glint(at: SunsetMotion.stillTime) - 0.5) < 0.001)
        // Las barras del reflejo, como en el icono: cada una más estrecha y tenue.
        let bars = SunsetMotion.Icon.bars
        #expect(zip(bars, bars.dropFirst()).allSatisfy { $0.width > $1.width && $0.opacity > $1.opacity && $0.y < $1.y })
        #expect(bars.allSatisfy { $0.y > SunsetMotion.Icon.horizon && $0.y < SunsetMotion.Icon.bottom })
    }
}
