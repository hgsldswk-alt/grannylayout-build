import SwiftUI

struct ListView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L.t("list.title")).font(.largeTitle.weight(.heavy))
                Button(L.t("list.new")) { model.capturing = true }
                    .buttonStyle(MainButton())
                    .accessibilityIdentifier("list.new")
                Text(L.t("list.new.hint")).font(.footnote).foregroundStyle(D.muted)
                ForEach(model.library.blankets) { b in
                    Button { model.path = [.canvas(b.id)] } label: {
                        HStack(spacing: 14) {
                            MiniGrid(blanket: b).frame(width: 74, height: 74)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(b.name).font(.headline).foregroundStyle(D.ink)
                                Text(L.f("list.size", b.squares.count, b.cols, b.rows)).font(.subheadline).foregroundStyle(D.muted)
                                if b.progress > 0 {
                                    Text(b.finished ? L.t("list.done") : L.f("list.progress", b.progress, b.count))
                                        .font(.caption.weight(.semibold)).foregroundStyle(D.accent)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(D.muted)
                        }
                        .padding(12)
                        .background(D.card, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(D.line))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("list.blanket")
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 24)
        }
        .background(D.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct MiniGrid: View {
    let blanket: Blanket
    var body: some View {
        VStack(spacing: 1) {
            ForEach(0..<blanket.rows, id: \.self) { r in
                HStack(spacing: 1) {
                    ForEach(0..<blanket.cols, id: \.self) { c in
                        Rectangle().fill(blanket.at(r, c).map { Color(uiColor: $0.color.uiColor) } ?? D.line)
                    }
                }
            }
        }
        .padding(2)
        .background(Color(uiColor: blanket.seam.uiColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct CaptureConfirm: View {
    @EnvironmentObject private var model: AppModel
    @State var capture: PendingCapture

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L.f("capture.found", capture.cols, capture.rows, capture.cols * capture.rows))
                        .font(.title3.weight(.bold))
                        .accessibilityIdentifier("capture.found")
                    Image(uiImage: capture.image).resizable().scaledToFit()
                        .overlay {
                            GeometryReader { geo in
                                Path { p in
                                    for c in 1..<max(capture.cols, 2) where c < capture.cols {
                                        let x = geo.size.width * CGFloat(c) / CGFloat(capture.cols)
                                        p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: geo.size.height))
                                    }
                                    for r in 1..<max(capture.rows, 2) where r < capture.rows {
                                        let y = geo.size.height * CGFloat(r) / CGFloat(capture.rows)
                                        p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y))
                                    }
                                }
                                .stroke(Color.yellow, lineWidth: 2)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    HStack(spacing: 10) {
                        Stepper(L.f("capture.cols", capture.cols), value: $capture.cols, in: 1...30).accessibilityIdentifier("capture.cols")
                    }
                    Stepper(L.f("capture.rows", capture.rows), value: $capture.rows, in: 1...30).accessibilityIdentifier("capture.rows")
                    Text(L.t("capture.hint")).font(.footnote).foregroundStyle(D.muted)
                    Button(L.t("common.done")) { model.confirm(capture) }
                        .buttonStyle(MainButton())
                        .accessibilityIdentifier("capture.done")
                }
                .padding(18)
            }
            .background(D.paper.ignoresSafeArea())
            .navigationTitle(L.t("list.new"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L.t("common.cancel")) { model.pending = nil }.accessibilityIdentifier("capture.cancel") } }
        }
    }
}

struct CanvasView: View {
    @EnvironmentObject private var model: AppModel
    let id: UUID
    @State private var selected: Int?

    var body: some View {
        if let b = model.blanket(id) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(b.name).font(.title2.weight(.heavy)).lineLimit(1)
                        Spacer()
                        Button { model.undoLast(id) } label: { Label(L.t("canvas.undo"), systemImage: "arrow.uturn.backward") }
                            .font(.subheadline.weight(.semibold))
                            .disabled((model.undo[id] ?? []).isEmpty)
                            .accessibilityIdentifier("canvas.undo")
                    }
                    let clashes = b.clashes(threshold: Shuffler.defaultThreshold).count
                    Text(L.f("canvas.info", b.squares.count, b.cols, b.rows) + " · " + (clashes == 0 ? L.t("canvas.clash.none") : L.f("canvas.clash", clashes)))
                        .font(.footnote).foregroundStyle(D.muted)
                        .accessibilityIdentifier("canvas.info")
                    grid(b)
                    HStack(spacing: 8) {
                        Text(L.t("canvas.seam")).font(.footnote).foregroundStyle(D.muted)
                        ForEach(SeamColor.allCases) { seam in
                            Circle().fill(Color(uiColor: seam.uiColor))
                                .frame(width: 26, height: 26)
                                .overlay(Circle().stroke(b.seam == seam ? D.accent : D.line, lineWidth: b.seam == seam ? 3 : 1))
                                .onTapGesture { model.update(id) { $0.seam = seam } }
                        }
                    }
                    Text(L.t("canvas.hint")).font(.footnote).foregroundStyle(D.muted)
                    Button(L.t("canvas.shuffle")) { selected = nil; model.shuffle(id) }
                        .buttonStyle(MainButton())
                        .accessibilityIdentifier("canvas.shuffle")
                    HStack(spacing: 8) {
                        Button(L.t("canvas.add")) { model.addingSquareTo = id }.buttonStyle(MainButton(filled: false))
                            .accessibilityIdentifier("canvas.add")
                        Button(L.t("canvas.assemble")) { model.path.append(.assemble(id)) }.buttonStyle(MainButton(filled: false))
                            .accessibilityIdentifier("canvas.assemble")
                        Button(L.t("canvas.export")) { model.export(id) }.buttonStyle(MainButton(filled: false))
                            .accessibilityIdentifier("canvas.export")
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .background(D.paper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(L.t("canvas.share")) { model.shareCard(id) }
                        Button(L.t("canvas.copy-code")) { model.copyCode(id) }
                        Button(L.t("canvas.paste-code")) {
                            model.pasteCode(id, text: model.testing ? ProcessInfo.processInfo.environment["UITEST_CODE"] : UIPasteboard.general.string)
                        }
                        Button(L.t("canvas.rename")) { model.renamingBlanket = true }
                        Stepper(L.f("capture.rows", b.rows), value: Binding(get: { b.rows }, set: { v in model.update(id) { $0.rows = v; $0.normalize() } }), in: 1...30)
                        Stepper(L.f("capture.cols", b.cols), value: Binding(get: { b.cols }, set: { v in model.update(id) { $0.cols = v; $0.normalize() } }), in: 1...30)
                        Button(L.t("canvas.delete"), role: .destructive) { model.delete(id) }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityIdentifier("canvas.more")
                }
            }
            .alert(L.t("canvas.rename"), isPresented: $model.renamingBlanket) {
                TextField(L.t("canvas.rename"), text: Binding(get: { model.blanket(id)?.name ?? "" },
                                                              set: { v in model.update(id, undoable: false) { $0.name = String(v.prefix(30)) } }))
                Button(L.t("common.done")) {}
            }
        }
    }

    private func grid(_ b: Blanket) -> some View {
        VStack(spacing: 3) {
            ForEach(0..<b.rows, id: \.self) { r in
                HStack(spacing: 3) {
                    ForEach(0..<b.cols, id: \.self) { c in
                        let i = r * b.cols + c
                        let square = b.at(r, c)
                        SquareTile(square: square, locked: square.map { b.locked.contains($0.id) } ?? false, highlight: selected == i)
                            .onTapGesture { tap(i) }
                            .contextMenu {
                                if let square {
                                    Button(b.locked.contains(square.id) ? L.t("canvas.unlock") : L.t("canvas.lock")) {
                                        model.update(id) { bl in
                                            if bl.locked.contains(square.id) { bl.locked.remove(square.id) } else { bl.locked.insert(square.id) }
                                        }
                                    }
                                }
                            }
                            .draggable(String(i))
                            .dropDestination(for: String.self) { items, _ in
                                guard let from = items.first.flatMap(Int.init) else { return false }
                                model.update(id) { $0.swapCells(from, i) }
                                selected = nil
                                return true
                            }
                            .accessibilityElement()
                            .accessibilityLabel(square?.label ?? "—")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("cell.\(i)")
                    }
                }
            }
        }
        .padding(3)
        .background(Color(uiColor: b.seam.uiColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func tap(_ i: Int) {
        if let s = selected {
            if s != i { model.update(id) { $0.swapCells(s, i) } }
            selected = nil
        } else {
            selected = i
        }
    }
}

struct AssembleView: View {
    @EnvironmentObject private var model: AppModel
    let id: UUID

    var body: some View {
        if let b = model.blanket(id) {
            let p = min(b.progress, max(b.count - 1, 0))
            let row = p / b.cols, col = p % b.cols
            ScrollView {
                VStack(spacing: 14) {
                    HStack {
                        Text(L.t("assemble.title")).foregroundStyle(D.muted)
                        Spacer()
                        Text(L.f("assemble.progress", b.progress, b.count)).font(.subheadline.weight(.bold))
                            .accessibilityIdentifier("assemble.progress")
                    }
                    ProgressView(value: Double(b.progress), total: Double(max(b.count, 1))).tint(D.accent)
                    if b.finished {
                        Text(L.t("assemble.finished")).font(.system(size: 36, weight: .heavy)).foregroundStyle(D.accent)
                            .multilineTextAlignment(.center)
                        Button(L.t("canvas.share")) { model.shareCard(id) }.buttonStyle(MainButton())
                    } else {
                        Text(L.f("assemble.row", row + 1)).font(.system(size: 46, weight: .heavy))
                            .accessibilityIdentifier("assemble.row")
                        HStack(spacing: 6) {
                            ForEach(0..<b.cols, id: \.self) { c in
                                VStack(spacing: 3) {
                                    SquareTile(square: b.at(row, c), highlight: c == col)
                                        .opacity(c < col ? 0.45 : 1)
                                    Text(b.at(row, c)?.label ?? "—").font(.caption.weight(c == col ? .heavy : .regular))
                                        .foregroundStyle(c == col ? D.accent : D.muted)
                                }
                            }
                        }
                        .padding(10)
                        .background(D.card, in: RoundedRectangle(cornerRadius: 16))
                        Text((0..<b.cols).map { b.at(row, $0)?.label ?? "—" }.joined(separator: " → "))
                            .font(.title2.weight(.heavy)).multilineTextAlignment(.center)
                        Button(L.f("assemble.done", b.at(row, col)?.label ?? "")) { model.advance(id) }
                            .buttonStyle(MainButton())
                            .font(.title2)
                            .accessibilityIdentifier("assemble.next")
                        Button(L.t("assemble.back")) { model.stepBack(id) }
                            .font(.subheadline).foregroundStyle(D.muted)
                            .disabled(b.progress == 0)
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 24)
            }
            .background(D.paper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct MilestoneView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(spacing: 14) {
            Text(L.t("milestone.label")).font(.caption.weight(.bold)).foregroundStyle(D.muted)
            Text(L.t("milestone.title")).font(.system(size: 32, weight: .heavy)).foregroundStyle(D.accent).multilineTextAlignment(.center)
            Text(L.t("milestone.body")).foregroundStyle(D.muted).multilineTextAlignment(.center)
            Button(L.t("canvas.share")) {
                model.showMilestone = false
                if case .assemble(let id)? = model.path.last { model.shareCard(id) }
            }
            .buttonStyle(MainButton())
            .accessibilityIdentifier("milestone.share")
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(D.card, in: RoundedRectangle(cornerRadius: 26))
        .padding(12)
    }
}
