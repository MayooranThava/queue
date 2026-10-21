import SpriteKit
import UIKit

/// A transparent 20-frame overlay for the companion's two typing paws.
/// The desk, laptop and character artwork remain completely stationary.
/// Textures are generated once and reused instead of allocating every timer tick.
enum CompanionTypingFrames {
    static let textures: [SKTexture] = (0..<20).map { frame in
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 136, height: 76), format: format).image { renderer in
            let context = renderer.cgContext
            let phase = CGFloat(frame) * (.pi * 2 / 20)
            for paw in 0..<2 {
                let alternate = paw == 0 ? CGFloat(0) : .pi
                // Alternating key presses with a small natural follow-through.
                let press = (1 - cos(phase * 2 + alternate)) * 0.5
                let horizontal = sin(phase + alternate) * 2.8
                let centerX = CGFloat(paw == 0 ? 47 : 91) + horizontal
                let centerY = CGFloat(paw == 0 ? 36 : 39) + press * 6
                context.saveGState()
                context.setShadow(offset: CGSize(width: 1, height: 3), blur: 4,
                                  color: UIColor(red: 0.30, green: 0.18, blue: 0.13, alpha: 0.25).cgColor)
                let outline = CGRect(x: centerX - 19, y: centerY - 13, width: 38, height: 26)
                let path = UIBezierPath(roundedRect: outline, cornerRadius: 13)
                UIColor(red: 0.97, green: 0.88, blue: 0.73, alpha: 1).setFill()
                path.fill()
                context.restoreGState()
                // Soft lit upper surface, with subtle individual toe impressions.
                let highlight = UIBezierPath(ovalIn: CGRect(x: centerX - 16, y: centerY - 12,
                                                             width: 30, height: 17))
                UIColor(red: 1, green: 0.97, blue: 0.87, alpha: 0.93).setFill()
                highlight.fill()
                UIColor(red: 0.85, green: 0.72, blue: 0.62, alpha: 0.18).setStroke()
                for finger in 0..<3 {
                    let line = UIBezierPath()
                    let x = centerX - 7 + CGFloat(finger) * 7
                    line.move(to: CGPoint(x: x, y: centerY + 5))
                    line.addLine(to: CGPoint(x: x + 1, y: centerY + 9))
                    line.lineWidth = 1
                    line.stroke()
                }
            }
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }
}
