import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

enum ImageTools {
    private static let context = CIContext()

    static func normalized(_ image: UIImage, maxSide: CGFloat = 2400) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, maxSide / longest)
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    static func flattenLayout(_ image: UIImage) async -> UIImage {
        let upright = normalized(image)
        guard let cg = upright.cgImage else { return upright }
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 1
        request.minimumSize = 0.3
        request.minimumConfidence = 0.5
        request.quadratureTolerance = 30
        request.minimumAspectRatio = 0.2
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        guard (try? handler.perform([request])) != nil, let quad = request.results?.first else { return upright }
        let ci = CIImage(cgImage: cg)
        let w = ci.extent.width, h = ci.extent.height
        func p(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x * w, y: point.y * h) }
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = ci
        filter.topLeft = p(quad.topLeft)
        filter.topRight = p(quad.topRight)
        filter.bottomLeft = p(quad.bottomLeft)
        filter.bottomRight = p(quad.bottomRight)
        guard let out = filter.outputImage, let made = context.createCGImage(out, from: out.extent) else { return upright }
        return UIImage(cgImage: made)
    }

    static func guessGrid(_ image: UIImage, cols: Int = 6) -> (rows: Int, cols: Int) {
        let ratio = image.size.height / max(image.size.width, 1)
        return (max(1, min(30, Int((CGFloat(cols) * ratio).rounded()))), cols)
    }

    static func split(_ image: UIImage, rows: Int, cols: Int) -> [[UIImage]] {
        guard let cg = image.cgImage else { return [] }
        let w = CGFloat(cg.width) / CGFloat(cols), h = CGFloat(cg.height) / CGFloat(rows)
        return (0..<rows).map { r in
            (0..<cols).compactMap { c in
                cg.cropping(to: CGRect(x: CGFloat(c) * w, y: CGFloat(r) * h, width: w, height: h).integral).map { UIImage(cgImage: $0) }
            }
        }
    }

    static func centerSquare(_ image: UIImage) -> UIImage {
        let upright = normalized(image, maxSide: 1200)
        guard let cg = upright.cgImage else { return upright }
        let side = min(cg.width, cg.height)
        let rect = CGRect(x: (cg.width - side) / 2, y: (cg.height - side) / 2, width: side, height: side)
        return cg.cropping(to: rect).map { UIImage(cgImage: $0) } ?? upright
    }

    static func mainColor(_ image: UIImage) -> LabColor {
        guard let cg = image.cgImage else { return LabColor(l: 50, a: 0, b: 0) }
        let ci = CIImage(cgImage: cg)
        let inset = ci.extent.insetBy(dx: ci.extent.width * 0.15, dy: ci.extent.height * 0.15)
        let filter = CIFilter.areaAverage()
        filter.inputImage = ci
        filter.extent = inset
        var pixel = [UInt8](repeating: 0, count: 4)
        if let out = filter.outputImage {
            context.render(out, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                           format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        }
        return LabColor.fromRGB(Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
    }

    static func jpeg(_ image: UIImage, side: CGFloat = 600) -> Data? {
        normalized(image, maxSide: side).jpegData(compressionQuality: 0.75)
    }
}

extension LabColor {
    var uiColor: UIColor { let (r, g, b) = rgb; return UIColor(red: r, green: g, blue: b, alpha: 1) }
}

extension SeamColor {
    var uiColor: UIColor { let (r, g, b) = rgb; return UIColor(red: r, green: g, blue: b, alpha: 1) }
}
