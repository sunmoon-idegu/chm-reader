import AppKit
import SwiftUI

struct TypographyPanel: View {
    private var prefs = ReadingPrefs()
    /// Fixed-layout documents (PDF) can only change the background.
    private let themeOnly: Bool

    init(themeOnly: Bool = false) { self.themeOnly = themeOnly }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !themeOnly {
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle("字型")
                    Picker("字型", selection: prefs.$font) {
                        ForEach(ReaderFont.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                SliderRow(title: "字級", value: prefs.$fontSize, range: 12...40, step: 1) { "\(Int($0)) pt" }
                SliderRow(title: "行高", value: prefs.$lineHeight, range: 1.2...3.0, step: 0.1) { String(format: "%.1f 倍", $0) }
                SliderRow(title: "段距", value: prefs.$paragraphSpacing, range: 0...3, step: 0.1) { String(format: "%.1f 行", $0) }
                SliderRow(title: "版面寬度", value: prefs.$pageWidth, range: 24...80, step: 2) { "\(Int($0)) 字" }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("背景")
                HStack(alignment: .center, spacing: 8) {
                    ForEach(ReaderTheme.allCases.filter { $0 != .custom }) { theme in
                        ThemeSwatch(theme: theme, selected: prefs.theme == theme) { prefs.theme = theme }
                    }
                    Divider().frame(height: 26)
                    ColorPicker(selection: customColor, supportsOpacity: false) {
                        Text("自訂").font(.callout)
                    }
                    .fixedSize()
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor, lineWidth: prefs.theme == .custom ? 2 : 0))
                }
            }

            HStack {
                Spacer()
                Button("恢復預設") { resetDefaults() }
                    .controlSize(.small)
            }
        }
    }

    private var customColor: Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hex: prefs.customBackground) ?? .white) },
            set: {
                prefs.customBackground = NSColor($0).hexString
                prefs.theme = .custom
            })
    }

    private func resetDefaults() {
        for key in [Pref.font, Pref.fontSize, Pref.lineHeight, Pref.paragraphSpacing, Pref.pageWidth, Pref.theme, Pref.customBackground] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.subheadline.weight(.semibold))
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(title)
                Spacer()
                Text(format(value))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .center, spacing: 10) {
                StepButton(systemImage: "minus", disabled: value <= range.lowerBound) { set(value - step) }
                // No `step:` on the Slider: stepped sliders draw a tick per value and snap, which is hard to drag.
                Slider(value: Binding(get: { value }, set: { set($0) }), in: range)
                    .controlSize(.regular)
                    .tint(.accentColor)
                StepButton(systemImage: "plus", disabled: value >= range.upperBound) { set(value + step) }
            }
        }
    }

    private func set(_ newValue: Double) {
        let snapped = (newValue / step).rounded() * step
        value = min(max(snapped, range.lowerBound), range.upperBound)
    }
}

private struct StepButton: View {
    let systemImage: String
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background(Circle().fill(Color.secondary.opacity(0.15)))
        .opacity(disabled ? 0.35 : 1)
        .disabled(disabled)
    }
}

private struct ThemeSwatch: View {
    let theme: ReaderTheme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(theme.label)
                .font(.caption)
                .foregroundStyle(Color(nsColor: NSColor(hex: theme.palette.1) ?? .black))
                .frame(width: 48, height: 30)
                .background(Color(nsColor: NSColor(hex: theme.palette.0) ?? .white), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .help(theme.label)
    }
}
