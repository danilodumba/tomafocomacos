import SwiftUI

/// Silhueta do tomate do ícone do app, em vetor.
///
/// Mesma geometria de `scripts/make_icon.py` (superelipse achatada + coroa de sépalas):
/// se um lado mudar, o outro precisa acompanhar, senão barra de menus e Dock divergem.
///
/// Todos os contornos são polígonos com a **mesma orientação** (`oriented(_:)`): com
/// `nonzero`, um subpath invertido viraria buraco no lugar de somar ao corpo.
struct TomatoMark: Shape {

    // Unidades normalizadas: x em [-1, 1], y para baixo. Corpo centrado na origem.
    private static let bodyExponent = 2.15   // > 2 achata os polos e cria o ombro do tomate
    private static let bodyFlatten = 0.84    // altura do corpo em relação à largura
    private static let base = CGPoint(x: 0, y: -0.72)  // de onde saem cabinho e sépalas
    private static let stemHeight = 0.60
    private static let stemHalfWidthBottom = 0.10
    private static let stemHalfWidthTop = 0.055
    private static let sepals: [(angle: Double, length: Double, width: Double)] = [
        (38, 0.70, 0.19), (-38, 0.70, 0.19), (82, 0.70, 0.16), (-82, 0.70, 0.16)
    ]

    private static let minY = base.y - stemHeight
    private static let maxY = bodyFlatten

    func path(in rect: CGRect) -> Path {
        let height = Self.maxY - Self.minY
        let scale = min(rect.width / 2, rect.height / height)
        let centerY = (Self.maxY + Self.minY) / 2

        func place(_ p: CGPoint) -> CGPoint {
            CGPoint(x: rect.midX + p.x * scale, y: rect.midY + (p.y - centerY) * scale)
        }

        var path = Path()
        for polygon in Self.polygons() {
            let points = Self.oriented(polygon).map(place)
            path.addLines(points)
            path.closeSubpath()
        }
        return path
    }

    // MARK: - Contornos

    private static func polygons() -> [[CGPoint]] {
        [body(), stem()] + sepals.map(sepal)
    }

    /// Corpo: superelipse. Elipse pura viraria bola; expoente alto demais vira caixa.
    private static func body(steps: Int = 180) -> [CGPoint] {
        let e = 2 / bodyExponent
        return (0..<steps).map { i in
            let t = 2 * Double.pi * Double(i) / Double(steps)
            let c = cos(t), s = sin(t)
            return CGPoint(
                x: copysign(pow(abs(c), e), c),
                y: copysign(pow(abs(s), e), s) * bodyFlatten
            )
        }
    }

    private static func stem() -> [CGPoint] {
        let top = base.y - stemHeight
        return [
            CGPoint(x: base.x - stemHalfWidthBottom, y: base.y),
            CGPoint(x: base.x - stemHalfWidthTop, y: top),
            CGPoint(x: base.x + stemHalfWidthTop, y: top),
            CGPoint(x: base.x + stemHalfWidthBottom, y: base.y)
        ]
    }

    /// Uma sépala: folha pontuda saindo da base do cabinho. 0° aponta para cima.
    private static func sepal(_ s: (angle: Double, length: Double, width: Double)) -> [CGPoint] {
        let a = s.angle * .pi / 180
        let dx = sin(a), dy = -cos(a)
        let px = -dy, py = dx  // perpendicular
        let bulge = 1.15

        let tip = CGPoint(x: base.x + dx * s.length, y: base.y + dy * s.length)
        let b1 = CGPoint(x: base.x + px * s.width, y: base.y + py * s.width)
        let b2 = CGPoint(x: base.x - px * s.width, y: base.y - py * s.width)
        let mid = (x: base.x + dx * s.length * 0.55, y: base.y + dy * s.length * 0.55)
        let c1 = CGPoint(x: mid.x + px * s.width * bulge, y: mid.y + py * s.width * bulge)
        let c2 = CGPoint(x: mid.x - px * s.width * bulge, y: mid.y - py * s.width * bulge)

        return [b1] + cubic(b1, c1, c1, tip) + cubic(tip, c2, c2, b2)
    }

    // MARK: - Utilitários

    /// Amostra uma bézier cúbica em polilinha (exclui o ponto inicial).
    private static func cubic(
        _ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p3: CGPoint, steps: Int = 24
    ) -> [CGPoint] {
        (1...steps).map { i in
            let t = Double(i) / Double(steps)
            let u = 1 - t
            let w0 = u * u * u, w1 = 3 * u * u * t, w2 = 3 * u * t * t, w3 = t * t * t
            return CGPoint(
                x: w0 * p0.x + w1 * c1.x + w2 * c2.x + w3 * p3.x,
                y: w0 * p0.y + w1 * c1.y + w2 * c2.y + w3 * p3.y
            )
        }
    }

    /// Devolve o polígono com área assinada positiva, para todos os subpaths girarem no
    /// mesmo sentido. Sépalas espelhadas nascem com orientação invertida.
    private static func oriented(_ points: [CGPoint]) -> [CGPoint] {
        var area = 0.0
        for i in points.indices {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            area += a.x * b.y - b.x * a.y
        }
        return area < 0 ? points.reversed() : points
    }
}

/// Ícone da barra de menus: o tomate dentro de um anel metade tinta (topo), metade cyan (base).
///
/// **É `NSImage`, não uma `View`, de propósito.** O rótulo do `MenuBarExtra` só renderiza
/// `Text` e `Image`: a primeira versão disto era um `ZStack` de `Circle`/`Shape` e o item
/// saiu VAZIO na barra de menus. Rasterizar aqui e entregar como `Image(nsImage:)` resolve.
///
/// **Uma imagem pronta por tema, não uma cor dinâmica.** `NSImage` cacheia a rasterização,
/// então uma `NSColor` dinâmica lida dentro do `drawingHandler` congelaria no tema vigente
/// na primeira vez que o ícone foi desenhado e não acompanharia a troca claro/escuro.
enum MenuBarIcon {
    /// 18pt é o tamanho de conteúdo padrão da barra de menus do macOS.
    static let side: CGFloat = 18
    private static let lineWidth: CGFloat = 1.7
    private static let tomatoInset: CGFloat = 2.2

    /// Barra clara: tinta navy. Branco puro sumiria.
    static let onLightBar: NSImage = make(ink: NSColor(Brand.navy))
    /// Barra escura: tinta branca, igual ao tomate do ícone do app.
    static let onDarkBar: NSImage = make(ink: .white)

    static func image(for scheme: ColorScheme) -> NSImage {
        scheme == .dark ? onDarkBar : onLightBar
    }

    private static func make(ink: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            // O traço é centrado no caminho: sem a folga de meia espessura ele vazaria.
            let circle = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
            let center = CGPoint(x: circle.midX, y: circle.midY)
            let radius = circle.width / 2

            ctx.setLineWidth(lineWidth)
            ctx.setLineCap(.butt)
            // Contexto com y para baixo: ângulo cresce no sentido horário e 0 é 3h.
            // A cyan vai do topo (−π/2) até embaixo (π/2), no mesmo sentido e no mesmo
            // ponto de partida do arco de progresso do ícone do app.
            ctx.setStrokeColor(NSColor(Brand.cyan).cgColor)
            ctx.addArc(
                center: center, radius: radius,
                startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
            ctx.strokePath()
            ctx.setStrokeColor(ink.cgColor)
            ctx.addArc(
                center: center, radius: radius,
                startAngle: .pi / 2, endAngle: 3 * .pi / 2, clockwise: false)
            ctx.strokePath()

            let box = circle.insetBy(dx: lineWidth + tomatoInset, dy: lineWidth + tomatoInset)
            ctx.setFillColor(ink.cgColor)
            ctx.addPath(TomatoMark().path(in: box).cgPath)
            ctx.fillPath()
            return true
        }
        // Template deixaria o macOS pintar tudo de uma cor só e a metade cyan sumiria.
        image.isTemplate = false
        return image
    }
}

#Preview {
    HStack(spacing: 16) {
        Image(nsImage: MenuBarIcon.onLightBar).renderingMode(.original)
        Image(nsImage: MenuBarIcon.onDarkBar).renderingMode(.original)
        TomatoMark().fill(Brand.textPrimary).frame(width: 64, height: 64)
    }
    .padding()
}
