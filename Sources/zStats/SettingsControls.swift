import SwiftUI
import StatsCore

struct SettingsUpdateButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.primary.opacity(isEnabled ? 0.9 : 0.35))
            .padding(.horizontal, 12).frame(height: 30)
            .background(Color.primary.opacity(configuration.isPressed ? 0.10 : 0.045), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct SettingsNavigationButton: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    init(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) {
        self.title = title; self.symbol = symbol; self.selected = selected; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).frame(width: 16)
                Text(title)
            }
            .font(.system(size: 12, weight: selected ? .medium : .regular))
            .foregroundStyle(selected || hovered ? Color.primary : .secondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
            .background(selected ? Color(hex: 0x5B9CF6).opacity(0.12) : Color.primary.opacity(hovered ? 0.045 : 0), in: RoundedRectangle(cornerRadius: 8))
            // Plain buttons otherwise hit-test only their drawn icon and text.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct SettingsActionMenu<Content: View>: View {
    let title: String
    var symbol: String?
    var chevron: Bool
    @ViewBuilder var content: () -> Content
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false
    @State private var presented = false
    @FocusState private var menuFocused: Bool

    init(_ title: String, symbol: String? = nil, chevron: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.symbol = symbol; self.chevron = chevron; self.content = content
    }

    var body: some View {
        Button { presented.toggle() } label: {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .medium)) }
                Text(title).font(.system(size: 11, weight: .medium))
                if chevron { Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary) }
            }
            .foregroundStyle(Color.primary.opacity(isEnabled ? 0.85 : 0.35))
            .padding(.horizontal, 10).frame(height: 28)
            .background(Color.primary.opacity((hovered || presented) && isEnabled ? 0.09 : 0.045), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain).fixedSize()
        .onHover { hovered = $0 }
        .accessibilityLabel(title)
        .popover(isPresented: $presented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) { content() }
                .buttonStyle(SettingsMenuOptionStyle { presented = false })
                .padding(6).frame(minWidth: 170)
                .focusable().focusEffectDisabled().focused($menuFocused)
                .onAppear { menuFocused = true }
                .onExitCommand { presented = false }
        }
    }
}

struct SettingsMenuOptionStyle: PrimitiveButtonStyle {
    var dismiss: () -> Void
    func makeBody(configuration: Configuration) -> some View {
        SettingsMenuOption { configuration.trigger(); dismiss() } label: { configuration.label }
    }
}

struct SettingsMenuOption<Label: View>: View {
    var action: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            label().font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Color.primary.opacity(hovered ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovered = $0 }
    }
}


struct SettingsControlRow<Content: View>: View {
    var title: String
    var labelWidth: CGFloat
    @ViewBuilder var content: () -> Content
    init(_ title: String, labelWidth: CGFloat = 90, @ViewBuilder content: @escaping () -> Content) { self.title = title; self.labelWidth = labelWidth; self.content = content }
    var body: some View {
        HStack(spacing: 16) {
            Text(title).foregroundStyle(.secondary).frame(width: labelWidth, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }.frame(minHeight: 30)
    }
}

struct SettingsChoice<Value: Hashable>: View {
    var title: String
    @Binding var selection: Value
    var options: [Value]
    var label: (Value) -> String
    @State private var presented = false
    @State private var hovered = false
    @FocusState private var menuFocused: Bool
    init(_ title: String, selection: Binding<Value>, options: [Value], label: @escaping (Value) -> String) {
        self.title = title; self._selection = selection; self.options = options; self.label = label
    }
    var body: some View {
        Button { presented.toggle() } label: {
            HStack {
                Text(label(selection)).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
            }.font(.system(size: 12)).padding(.horizontal, 10).frame(height: 30)
                .background(Color.primary.opacity(hovered || presented ? 0.085 : 0.035), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).onHover { hovered = $0 }
            .accessibilityLabel(title).accessibilityValue(label(selection))
            .popover(isPresented: $presented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(options, id: \.self) { option in
                        Button {
                            presented = false
                            selection = option
                        } label: {
                            HStack {
                                Text(label(option))
                                Spacer()
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).opacity(selection == option ? 1 : 0)
                            }
                        }.accessibilityAddTraits(selection == option ? [.isSelected] : [])
                    }
                }.buttonStyle(SettingsMenuOptionStyle { presented = false })
                    .padding(6).frame(width: 205)
                    .focusable().focusEffectDisabled().focused($menuFocused)
                    .onAppear { menuFocused = true }
                    .onExitCommand { presented = false }
            }
    }
}

struct SettingsLabelSegments: View {
    @Binding var selection: WidgetLabel
    var body: some View {
        HStack(spacing: 3) {
            ForEach(WidgetLabel.allCases, id: \.self) { option in
                Button { selection = option } label: {
                    Text(option.rawValue).font(.system(size: 11, weight: selection == option ? .medium : .regular))
                        .foregroundStyle(selection == option ? Color.primary : .secondary)
                        .frame(maxWidth: .infinity).frame(height: 24)
                        .background(selection == option ? Color.primary.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Label: " + option.rawValue)
                    .accessibilityAddTraits(selection == option ? [.isSelected] : [])
            }
        }.padding(3).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }
}

struct SettingsTextInput: View {
    @Binding var text: String
    @FocusState private var focused: Bool
    var body: some View {
        TextField("Automatic", text: $text).textFieldStyle(.plain).font(.system(size: 12))
            .focused($focused).tint(Color(hex: 0x5B9CF6))
            .padding(.horizontal, 10).frame(height: 30)
            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(focused ? Color(hex: 0x5B9CF6).opacity(0.7) : Color.primary.opacity(0.08), lineWidth: focused ? 1 : 0.5))
            .accessibilityLabel("Custom widget label")
    }
}

struct SettingsSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack {
                configuration.label.font(.system(size: 12))
                Spacer(minLength: 12)
                Capsule().fill(configuration.isOn ? Color(hex: 0x5B9CF6) : Color.primary.opacity(0.16))
                    .frame(width: 28, height: 16)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(.white).frame(width: 12, height: 12).padding(2)
                    }
            }.contentShape(Rectangle()).frame(minHeight: 30)
        }.buttonStyle(.plain)
            .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch) }
    }
}

struct SettingsValueSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var title: String
    @FocusState private var focused: Bool
    private var fraction: Double { min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound))) }
    private func set(_ proposed: Double) { value = min(range.upperBound, max(range.lowerBound, (proposed / step).rounded() * step)) }
    var body: some View {
        HStack(spacing: 12) {
            GeometryReader { proxy in
                let width = max(1, proxy.size.width - 12)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10)).frame(height: 3).padding(.horizontal, 6)
                    Capsule().fill(Color.primary.opacity(0.35)).frame(width: width * fraction, height: 3).padding(.leading, 6)
                    Circle().fill(Color.primary.opacity(0.9)).frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(focused ? Color(hex: 0x5B9CF6) : .clear, lineWidth: 2))
                        .offset(x: width * fraction)
                }.frame(height: 30).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                        focused = true
                        set(range.lowerBound + (event.location.x - 6) / width * (range.upperBound - range.lowerBound))
                    })
            }.frame(height: 30).focusable().focusEffectDisabled().focused($focused)
                .onKeyPress(.leftArrow) { set(value - step); return .handled }
                .onKeyPress(.rightArrow) { set(value + step); return .handled }
                .accessibilityElement(children: .ignore).accessibilityLabel(title).accessibilityValue("\(Int(value)) points")
                .accessibilityAdjustableAction { direction in
                    switch direction { case .increment: set(value + step); case .decrement: set(value - step); @unknown default: break }
                }
            Text("\(Int(value)) pt").font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 46, height: 26).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}


struct SettingsCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: () -> Content
    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) { self.title = title; self.content = content }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title { Text(title).font(.system(size: 12, weight: .semibold)) }
            content()
        }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
            .padding(16).background(Color.panel, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SettingsNote: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            RoundedRectangle(cornerRadius: 4).fill(configuration.isOn ? Color(hex: 0x5B9CF6) : Color.primary.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                .overlay { if configuration.isOn { Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white) } }
                .frame(width: 14, height: 14).padding(3).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.checkbox) }
    }
}
