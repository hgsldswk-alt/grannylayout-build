import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

enum Renderer {
    @MainActor
    static func blanketImage(_ b: Blanket, model: AppModel, cell: CGFloat = 120) -> UIImage {
        let seam: CGFloat = max(2, cell * 0.05)
        let size = CGSize(width: CGFloat(b.cols) * (cell + seam) + seam, height: CGFloat(b.rows) * (cell + seam) + seam)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            b.seam.uiColor.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            for r in 0..<b.rows {
                for c in 0..<b.cols {
                    let rect = CGRect(x: seam + CGFloat(c) * (cell + seam), y: seam + CGFloat(r) * (cell + seam), width: cell, height: cell)
                    if let s = b.at(r, c) {
                        if let img = model.image(s.photo) { img.draw(in: rect) } else { s.color.uiColor.setFill(); ctx.fill(rect) }
                    } else {
                        UIColor(white: 0.9, alpha: 1).setFill(); ctx.fill(rect)
                    }
                }
            }
        }
    }

    @MainActor
    static func orderPDF(_ b: Blanket, model: AppModel) -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let preview = blanketImage(b, model: model)
        return UIGraphicsPDFRenderer(bounds: page).pdfData { ctx in
            ctx.beginPage()
            draw(b.name, CGRect(x: 50, y: 40, width: 512, height: 30), 22, bold: true)
            draw(L.f("pdf.size", b.count, b.cols, b.rows), CGRect(x: 50, y: 72, width: 512, height: 20), 12, bold: false)
            let scale = min(512 / preview.size.width, 640 / preview.size.height)
            preview.draw(in: CGRect(x: 50, y: 100, width: preview.size.width * scale, height: preview.size.height * scale))
            var y: CGFloat = 800
            for r in 0..<b.rows {
                if y > 720 { ctx.beginPage(); y = 50; draw(L.t("pdf.order"), CGRect(x: 50, y: y, width: 512, height: 26), 18, bold: true); y += 40 }
                let labels = (0..<b.cols).map { b.at(r, $0)?.label ?? "—" }.joined(separator: " → ")
                draw(L.f("assemble.row", r + 1), CGRect(x: 50, y: y, width: 90, height: 22), 14, bold: true)
                draw(labels, CGRect(x: 140, y: y, width: 422, height: 40), 14, bold: false)
                y += 44
            }
        }
    }

    private static func draw(_ text: String, _ rect: CGRect, _ size: CGFloat, bold: Bool) {
        (text as NSString).draw(in: rect, withAttributes: [
            .font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.black])
    }

    static func qr() -> UIImage? {
        let id = (Bundle.main.object(forInfoDictionaryKey: "APP_STORE_ID") as? String ?? "").trimmingCharacters(in: .whitespaces)
        let link = id.isEmpty || id.hasPrefix("$") ? "https://hgsldswk-alt.github.io/grannylayout-support/" : "https://apps.apple.com/app/id\(id)"
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(link.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    @MainActor
    static func shareCard(_ b: Blanket, model: AppModel) -> UIImage {
        let view = VStack(alignment: .leading, spacing: 12) {
            Image(uiImage: blanketImage(b, model: model, cell: 90)).resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(L.f("share.size", b.count, b.cols, b.rows)).font(.title2.weight(.heavy))
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.t("share.tags")).font(.subheadline.weight(.bold)).foregroundStyle(D.accent)
                    Text(L.t("app.name")).font(.caption).foregroundStyle(D.muted)
                }
                Spacer()
                if let qr = qr() { Image(uiImage: qr).interpolation(.none).resizable().frame(width: 70, height: 70) }
            }
        }
        .padding(18).frame(width: 380).background(D.paper).foregroundStyle(D.ink)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return renderer.uiImage ?? UIImage()
    }
}
