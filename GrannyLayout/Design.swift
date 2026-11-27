import SwiftUI
import UIKit

enum D {
    static let paper = Color(red: 0.980, green: 0.965, blue: 0.945)
    static let card = Color.white
    static let ink = Color(red: 0.200, green: 0.149, blue: 0.122)
    static let muted = Color(red: 0.490, green: 0.420, blue: 0.376)
    static let line = Color(red: 0.902, green: 0.859, blue: 0.816)
    static let accent = Color(red: 0.710, green: 0.329, blue: 0.235)
    static let pale = Color(red: 0.953, green: 0.902, blue: 0.863)
}

struct MainButton: ButtonStyle {
    var filled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(filled ? .white : D.ink)
            .background((filled ? D.accent : D.pale).opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct CameraPicker: UIViewControllerRepresentable {
    let done: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(done: done) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (UIImage?) -> Void
        init(done: @escaping (UIImage?) -> Void) { self.done = done }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            done(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { done(nil) }
    }
}

struct SquareTile: View {
    @EnvironmentObject private var model: AppModel
    let square: Square?
    var locked = false
    var highlight = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let square {
                if let img = model.image(square.photo) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Color(uiColor: square.color.uiColor)
                }
            } else {
                RoundedRectangle(cornerRadius: 4).strokeBorder(D.line, style: StrokeStyle(lineWidth: 1.5, dash: [4]))
            }
            if locked {
                Image(systemName: "lock.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    .padding(3).background(.black.opacity(0.45), in: Circle()).padding(2)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(highlight ? D.accent : .clear, lineWidth: 3))
    }
}
