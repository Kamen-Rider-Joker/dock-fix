import AppKit

/// Menu bar artwork, kept monochrome so macOS can tint it for every menu bar appearance.
enum MenuBarIconStyle: String, CaseIterable {
    case original
    case rocket
    case protection
    case diagnostics
    case cat
    case game
    case puzzle
    case lightning
    case cloud
    case cloudSun
    case arcade
    case bobAvatar
    case tuftAvatar
    case twinTailAvatar
    case bird
    case fish
    case alien
    case panda
    case fox
    case frog
    case bubbleTea
    case sushi
    case ghost
    case robot

    var title: String {
        switch self {
        case .original: L("dockUnstick（默认）", "dockUnstick (Default)")
        case .rocket: L("小火箭", "Little Rocket")
        case .protection: L("稳定守护", "Protection")
        case .diagnostics: L("状态诊断", "Diagnostics")
        case .cat: L("猫咪技师", "Cat Mechanic")
        case .game: L("游戏模式", "Game Mode")
        case .puzzle: L("拼图工坊", "Puzzle Workshop")
        case .lightning: L("闪电修复", "Lightning Fix")
        case .cloud: L("云朵", "Cloud")
        case .cloudSun: L("晴间多云", "Cloud & Sun")
        case .arcade: L("街机模式", "Arcade")
        case .bobAvatar: L("短发头像", "Bob Avatar")
        case .tuftAvatar: L("呆毛头像", "Tuft Avatar")
        case .twinTailAvatar: L("双马尾头像", "Twin-tail Avatar")
        case .bird: L("小鸟", "Little Bird")
        case .fish: L("小鱼", "Little Fish")
        case .alien: L("像素外星人", "Pixel Alien")
        case .panda: L("熊猫", "Panda")
        case .fox: L("小狐狸", "Fox")
        case .frog: L("小青蛙", "Frog")
        case .bubbleTea: L("珍珠奶茶", "Bubble Tea")
        case .sushi: L("寿司", "Sushi")
        case .ghost: L("小幽灵", "Ghost")
        case .robot: L("机器人", "Robot")
        }
    }

    func image() -> NSImage {
        let image: NSImage
        switch self {
        case .original:
            let symbol = AXIsProcessTrusted() ? "dock.arrow.down.rectangle" : "exclamationmark.triangle"
            image = Self.symbolCanvas(symbol, pointSize: 16.5, weight: .medium)
        case .rocket:
            image = Self.rocketCanvas()
        case .protection:
            image = Self.symbolCanvas("checkmark.shield.fill", pointSize: 17, weight: .medium)
        case .diagnostics:
            image = Self.symbolCanvas("stethoscope", pointSize: 16.5, weight: .medium)
        case .cat:
            image = Self.symbolCanvas("cat.fill", pointSize: 16.5, weight: .medium)
        case .game:
            image = Self.symbolCanvas("gamecontroller.fill", pointSize: 16.5, weight: .medium)
        case .puzzle:
            image = Self.symbolCanvas("puzzlepiece.extension.fill", pointSize: 16.5, weight: .medium)
        case .lightning:
            image = Self.symbolCanvas("bolt.fill", pointSize: 16.5, weight: .medium)
        case .cloud:
            image = Self.symbolCanvas("cloud.fill", pointSize: 16.5, weight: .medium)
        case .cloudSun:
            image = Self.symbolCanvas("cloud.sun.fill", pointSize: 16.5, weight: .medium)
        case .arcade:
            image = Self.symbolCanvas("arcade.stick", pointSize: 16.5, weight: .medium)
        case .bobAvatar:
            image = Self.avatarCanvas(.bob)
        case .tuftAvatar:
            image = Self.avatarCanvas(.tuft)
        case .twinTailAvatar:
            image = Self.avatarCanvas(.twinTail)
        case .bird:
            image = Self.symbolCanvas("bird.fill", pointSize: 16.5, weight: .medium)
        case .fish:
            image = Self.symbolCanvas("fish.fill", pointSize: 16.5, weight: .medium)
        case .alien:
            image = Self.emojiCanvas("👾")
        case .panda:
            image = Self.emojiCanvas("🐼")
        case .fox:
            image = Self.emojiCanvas("🦊")
        case .frog:
            image = Self.emojiCanvas("🐸")
        case .bubbleTea:
            image = Self.emojiCanvas("🧋")
        case .sushi:
            image = Self.emojiCanvas("🍣")
        case .ghost:
            image = Self.emojiCanvas("👻")
        case .robot:
            image = Self.emojiCanvas("🤖")
        }
        image.isTemplate = !isEmoji
        image.accessibilityDescription = AXIsProcessTrusted()
            ? L("DockUnstick 正在运行", "DockUnstick is running")
            : L("DockUnstick 需要辅助功能权限", "DockUnstick needs Accessibility permission")
        return image
    }

    var menuPreview: NSImage {
        let source = image()
        // NSMenuItem does not consistently resolve template rendering inside submenus.
        return NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            let scale = min(16 / source.size.width, 16 / source.size.height)
            let width = source.size.width * scale
            let height = source.size.height * scale
            source.draw(
                in: NSRect(x: (16 - width) / 2, y: (16 - height) / 2, width: width, height: height),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: false,
                hints: nil
            )
            return true
        }
    }

    /// A 24 x 21 pt canvas gives the artwork the same visual weight as common
    /// macOS menu bar icons while retaining room for the status item's hit area.
    private static let canvasSize = NSSize(width: 24, height: 21)

    private var isEmoji: Bool {
        switch self {
        case .alien, .panda, .fox, .frog, .bubbleTea, .sushi, .ghost, .robot:
            return true
        default:
            return false
        }
    }

    private static func emojiCanvas(_ emoji: String) -> NSImage {
        NSImage(size: canvasSize, flipped: false) { _ in
            let font = NSFont(name: "Apple Color Emoji", size: 18)
                ?? NSFont.systemFont(ofSize: 18)
            let text = emoji as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let size = text.size(withAttributes: attributes)
            text.draw(
                at: NSPoint(
                    x: (canvasSize.width - size.width) / 2,
                    y: (canvasSize.height - size.height) / 2 + 1
                ),
                withAttributes: attributes
            )
            return true
        }
    }

    private static func rocketCanvas() -> NSImage {
        NSImage(size: canvasSize, flipped: false) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            let body = NSBezierPath()
            body.move(to: NSPoint(x: 12, y: 20))
            body.curve(
                to: NSPoint(x: 15.3, y: 15.7),
                controlPoint1: NSPoint(x: 13.8, y: 18.5),
                controlPoint2: NSPoint(x: 15.3, y: 17.5)
            )
            body.curve(
                to: NSPoint(x: 14, y: 6.1),
                controlPoint1: NSPoint(x: 15.3, y: 13.4),
                controlPoint2: NSPoint(x: 14.8, y: 8.3)
            )
            body.curve(
                to: NSPoint(x: 10, y: 6.1),
                controlPoint1: NSPoint(x: 13, y: 5.1),
                controlPoint2: NSPoint(x: 11, y: 5.1)
            )
            body.curve(
                to: NSPoint(x: 8.7, y: 15.7),
                controlPoint1: NSPoint(x: 9.2, y: 8.3),
                controlPoint2: NSPoint(x: 8.7, y: 13.4)
            )
            body.curve(
                to: NSPoint(x: 12, y: 20),
                controlPoint1: NSPoint(x: 8.7, y: 17.5),
                controlPoint2: NSPoint(x: 10.2, y: 18.5)
            )
            body.appendOval(in: NSRect(x: 10.3, y: 12.2, width: 3.4, height: 3.4))
            body.windingRule = .evenOdd
            body.fill()

            let leftFin = NSBezierPath()
            leftFin.move(to: NSPoint(x: 9.2, y: 10.2))
            leftFin.line(to: NSPoint(x: 5.2, y: 6.2))
            leftFin.line(to: NSPoint(x: 6, y: 12.3))
            leftFin.close()
            leftFin.fill()

            let rightFin = NSBezierPath()
            rightFin.move(to: NSPoint(x: 14.8, y: 10.2))
            rightFin.line(to: NSPoint(x: 18.8, y: 6.2))
            rightFin.line(to: NSPoint(x: 18, y: 12.3))
            rightFin.close()
            rightFin.fill()

            let flame = NSBezierPath()
            flame.move(to: NSPoint(x: 9.8, y: 6))
            flame.curve(
                to: NSPoint(x: 12, y: 1.2),
                controlPoint1: NSPoint(x: 10.3, y: 4.7),
                controlPoint2: NSPoint(x: 11.2, y: 2.2)
            )
            flame.curve(
                to: NSPoint(x: 14.2, y: 6),
                controlPoint1: NSPoint(x: 12.8, y: 2.2),
                controlPoint2: NSPoint(x: 13.7, y: 4.7)
            )
            flame.close()
            flame.fill()
            return true
        }
    }

    private static func symbolCanvas(_ name: String, pointSize: CGFloat, weight: NSFont.Weight) -> NSImage {
        NSImage(size: canvasSize, flipped: false) { _ in
            guard let symbol = symbol(name, pointSize: pointSize, weight: weight)
                ?? symbol("wrench.fill", pointSize: pointSize, weight: weight)
            else { return false }

            let inset = NSRect(x: 1, y: 1, width: 22, height: 19)
            let scale = min(inset.width / symbol.size.width, inset.height / symbol.size.height)
            let width = symbol.size.width * scale
            let height = symbol.size.height * scale
            let rect = NSRect(
                x: inset.midX - width / 2,
                y: inset.midY - height / 2,
                width: width,
                height: height
            )
            symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                        respectFlipped: false, hints: nil)
            return true
        }
    }

    private enum AvatarKind {
        case bob
        case tuft
        case twinTail
    }

    /// Simple monochrome anime portraits that stay readable at menu bar size.
    private static func avatarCanvas(_ kind: AvatarKind) -> NSImage {
        NSImage(size: canvasSize, flipped: false) { _ in
            let transform = NSAffineTransform()
            transform.translateX(by: 1.1, yBy: 1.1)
            transform.scale(by: 1.1)
            transform.concat()

            NSColor.black.setStroke()
            NSColor.black.setFill()

            let face = NSBezierPath(ovalIn: NSRect(x: 5.3, y: 2.2, width: 11.4, height: 11.8))
            face.lineWidth = 1.25
            face.stroke()

            let hair = NSBezierPath()
            switch kind {
            case .bob:
                hair.move(to: NSPoint(x: 4.8, y: 9.5))
                hair.curve(to: NSPoint(x: 11, y: 16.2),
                           controlPoint1: NSPoint(x: 4.7, y: 14.7),
                           controlPoint2: NSPoint(x: 7.1, y: 16.3))
                hair.curve(to: NSPoint(x: 17.2, y: 9.5),
                           controlPoint1: NSPoint(x: 14.9, y: 16.3),
                           controlPoint2: NSPoint(x: 17.3, y: 14.7))
                hair.line(to: NSPoint(x: 14.6, y: 8.8))
                hair.line(to: NSPoint(x: 12.8, y: 10.1))
                hair.line(to: NSPoint(x: 11, y: 8.9))
                hair.line(to: NSPoint(x: 9.2, y: 10.1))
                hair.line(to: NSPoint(x: 7.4, y: 8.8))
            case .tuft:
                hair.move(to: NSPoint(x: 5.1, y: 9.3))
                hair.line(to: NSPoint(x: 9.4, y: 16.6))
                hair.line(to: NSPoint(x: 10.2, y: 14.9))
                hair.line(to: NSPoint(x: 12.2, y: 16.2))
                hair.line(to: NSPoint(x: 12.9, y: 14.4))
                hair.line(to: NSPoint(x: 15.5, y: 15.7))
                hair.line(to: NSPoint(x: 16.9, y: 9.3))
                hair.line(to: NSPoint(x: 14.2, y: 8.9))
                hair.line(to: NSPoint(x: 12.6, y: 10.2))
                hair.line(to: NSPoint(x: 10.8, y: 8.8))
                hair.line(to: NSPoint(x: 9.1, y: 10.2))
                hair.line(to: NSPoint(x: 7.5, y: 8.9))
            case .twinTail:
                NSBezierPath(ovalIn: NSRect(x: 1.5, y: 7.2, width: 4.2, height: 5.6)).fill()
                NSBezierPath(ovalIn: NSRect(x: 16.3, y: 7.2, width: 4.2, height: 5.6)).fill()
                hair.move(to: NSPoint(x: 4.9, y: 9.6))
                hair.curve(to: NSPoint(x: 11, y: 16.3),
                           controlPoint1: NSPoint(x: 4.7, y: 14.8),
                           controlPoint2: NSPoint(x: 7.2, y: 16.4))
                hair.curve(to: NSPoint(x: 17.1, y: 9.6),
                           controlPoint1: NSPoint(x: 14.8, y: 16.4),
                           controlPoint2: NSPoint(x: 17.3, y: 14.8))
                hair.line(to: NSPoint(x: 14.4, y: 8.8))
                hair.line(to: NSPoint(x: 12.7, y: 10.2))
                hair.line(to: NSPoint(x: 11, y: 8.8))
                hair.line(to: NSPoint(x: 9.3, y: 10.2))
                hair.line(to: NSPoint(x: 7.6, y: 8.8))
            }
            hair.close()
            hair.fill()

            for x in [8.4, 13.6] {
                NSBezierPath(ovalIn: NSRect(x: x, y: 9.5, width: 1.05, height: 1.05)).fill()
            }
            let smile = NSBezierPath()
            smile.lineWidth = 1
            smile.lineCapStyle = .round
            smile.move(to: NSPoint(x: 9.2, y: 6.7))
            smile.curve(to: NSPoint(x: 12.8, y: 6.7),
                        controlPoint1: NSPoint(x: 10.1, y: 5.8),
                        controlPoint2: NSPoint(x: 11.9, y: 5.8))
            smile.stroke()
            return true
        }
    }

    private static func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight))
    }
}
