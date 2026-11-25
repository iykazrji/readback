import ReadbackCore
import SwiftUI

/// Readback's segmented control, in place of the stock `.segmented` picker (which SwiftUI on
/// macOS draws through AppKit and won't restyle): one plate with the controls' edge, and the
/// chosen segment a lighter plate that slides across when the choice changes. Left and Right
/// move the choice when it has keyboard focus. VoiceOver reads each segment as a button, the
/// chosen one selected. Part of the owner's black-and-white look, 2026-11-25.
struct Segmented<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let options: [(title: String, value: Value)]
    @Namespace private var namespace
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ label: String, selection: Binding<Value>, options: [(title: String, value: Value)]) {
        self.label = label
        _selection = selection
        self.options = options
    }

    private let inset: CGFloat = 3

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ControlMetrics.radius, style: .continuous)
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                segment(index)
            }
        }
        .padding(inset)
        .frame(height: ControlMetrics.height)
        .background(ControlMetrics.fill(scheme), in: shape)
        .overlay { shape.strokeBorder(ControlMetrics.edge(scheme), lineWidth: ControlMetrics.edgeWidth) }
        .keyboardFocusRing(focused, shape)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { move(by: -1); return .handled }
        .onKeyPress(.rightArrow) { move(by: 1); return .handled }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func segment(_ index: Int) -> some View {
        let chosen = options[index].value == selection
        let inner = RoundedRectangle(cornerRadius: ControlMetrics.radius - inset, style: .continuous)
        return Button {
            withAnimation(Motion.spring(reduceMotion)) { selection = options[index].value }
        } label: {
            Text(options[index].title)
                .font(.system(size: ControlMetrics.fontSize, weight: .medium))
                .foregroundStyle(chosen ? Color.primary : Color.secondary)
                .padding(.horizontal, ControlMetrics.padding)
                .frame(maxHeight: .infinity)
                .background {
                    if chosen {
                        inner.fill(chosenFill)
                            .overlay { inner.strokeBorder(chosenEdge, lineWidth: ControlMetrics.edgeWidth) }
                            .matchedGeometryEffect(id: "chosen", in: namespace)
                    }
                }
                .contentShape(inner)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func move(by delta: Int) {
        guard let current = options.firstIndex(where: { $0.value == selection }) else { return }
        let next = SegmentStep.step(from: current, by: delta, count: options.count)
        withAnimation(Motion.spring(reduceMotion)) { selection = options[next].value }
    }

    private var chosenFill: Color { scheme == .dark ? Color.white.opacity(0.17) : .white }
    private var chosenEdge: Color { scheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.12) }
}
