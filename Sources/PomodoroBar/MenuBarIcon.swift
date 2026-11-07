import AppKit
import PomodoroCore

/// Draws the menu bar progress ring as a template image, so macOS tints it
/// to match the menu bar in light and dark mode.
enum MenuBarIcon {
    static func ring(progress: Double, phase: Phase, paused: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let lineWidth: CGFloat = 2
            let circle = rect.insetBy(dx: lineWidth / 2 + 0.5, dy: lineWidth / 2 + 0.5)
            let center = NSPoint(x: rect.midX, y: rect.midY)

            let track = NSBezierPath(ovalIn: circle)
            track.lineWidth = lineWidth
            NSColor.black.withAlphaComponent(0.3).setStroke()
            track.stroke()

            // Elapsed time fills clockwise from 12 o'clock.
            if progress > 0 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: circle.width / 2,
                              startAngle: 90, endAngle: 90 - 360 * progress, clockwise: true)
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .round
                NSColor.black.setStroke()
                arc.stroke()
            }

            NSColor.black.setFill()
            if paused {
                for x in [center.x - 2.5, center.x + 0.5] {
                    NSBezierPath(roundedRect: NSRect(x: x, y: center.y - 3, width: 2, height: 6),
                                 xRadius: 0.5, yRadius: 0.5).fill()
                }
            } else if phase.isBreak {
                // A filled center tells breaks apart from focus at a glance.
                NSBezierPath(ovalIn: NSRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
