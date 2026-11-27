import StoreKit
import SwiftUI

@main
struct GrannyLayoutApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(D.accent)
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var phase

    private var reviewCanvas: Bool {
        let onCanvas: Bool
        if case .canvas? = model.path.last { onCanvas = true } else { onCanvas = false }
        return (onCanvas || model.path.isEmpty) && !model.renamingBlanket && !model.capturing && model.addingSquareTo == nil
            && model.pending == nil && model.share == nil && !model.showMilestone && model.toast == nil && !model.testing
    }

    var body: some View {
        NavigationStack(path: $model.path) {
            ListView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .canvas(let id): CanvasView(id: id)
                    case .assemble(let id): AssembleView(id: id)
                    }
                }
        }
        .foregroundStyle(D.ink)
        .reviewAfterCoreAction(when: reviewCanvas) { requestReview() }
        .task(id: reviewCanvas && model.exportReviewReady && phase == .active) {
            guard reviewCanvas, model.exportReviewReady, phase == .active else { return }
            do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
            guard !Task.isCancelled, reviewCanvas else { return }
            model.requestExportReview { requestReview() }
        }
        .fullScreenCover(isPresented: $model.capturing) {
            if model.testing {
                Color.clear.onAppear { model.captured(Fixtures.layoutPhoto()) }
            } else {
                CameraPicker { model.captured($0) }.ignoresSafeArea()
            }
        }
        .fullScreenCover(item: Binding(get: { model.addingSquareTo.map { Target(id: $0) } }, set: { model.addingSquareTo = $0?.id })) { target in
            if model.testing {
                Color.clear.onAppear { model.addSquare(Fixtures.squareImage(Fixtures.palette[2], seed: 9), to: target.id) }
            } else {
                CameraPicker { model.addSquare($0, to: target.id) }.ignoresSafeArea()
            }
        }
        .sheet(item: $model.pending) { capture in CaptureConfirm(capture: capture) }
        .sheet(item: $model.share) { share in
            ActivitySheet(items: share.items).presentationDetents([.medium, .large])
        }
        .overlay {
            if model.showMilestone {
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { model.showMilestone = false }
                    MilestoneView()
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .padding(.vertical, 10).padding(.horizontal, 16)
                    .background(D.ink.opacity(0.9), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(.bottom, 20)
                    .accessibilityIdentifier("toast")
            }
        }
    }
}

private struct Target: Identifiable { let id: UUID }
