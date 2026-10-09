import SwiftUI
import WristMagicCore

/// A bounded foreground response, independent of the phone's AR rendering.
struct WatchSpellEffect: View {
  let spell: SpellID
  let reducedMotion: Bool
  @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
  @State private var started = Date()
  @State private var completed = false
  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: completed || reducedMotion || systemReducedMotion)) { timeline in
      Canvas { context, size in
        let reduced = reducedMotion || systemReducedMotion
        let elapsed = timeline.date.timeIntervalSince(started)
        let progress = reduced ? 0.5 : min(1, max(0, elapsed / 1.5))
        let opacity = reduced ? 1 : max(0, 1 - max(0, progress - 0.8) / 0.2)
        guard opacity > 0 else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        for index in 0..<24 {
          let angle = Double(index) * .pi * 2 / 24
          let radius = (8 + progress * 35) * (spell == .forcePush ? 1 : Double(index % 3 + 1) / 3)
          let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
          var path = Path()
          if spell == .lightning {
            path.move(to: center)
            path.addLine(to: CGPoint(x: point.x + 4, y: point.y - 5))
            path.addLine(to: point)
            context.stroke(path, with: .color(.yellow.opacity(opacity)), lineWidth: 1)
          } else {
            path.addEllipse(in: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4))
            context.fill(path, with: .color((spell == .fireball ? Color.orange : Color.yellow).opacity(opacity)))
          }
        }
      }
    }
    .frame(height: 80)
    .accessibilityHidden(true)
    .task {
      started = Date(); completed = false
      try? await Task.sleep(for: .milliseconds(1500))
      completed = true
    }
  }
}
