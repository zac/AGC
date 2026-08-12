import SwiftUI
import AGC

struct DSKYKey: Identifiable {
    let code: DSKYKeyCode
    let accent: Bool

    var id: String {
        code.label
    }

    var label: String {
        code.label
    }
}

struct DSKYKeyButtonStyle: ButtonStyle {
    let accent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(accent ? Color.accentColor : Color.primary)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if accent {
            return Color.accentColor.opacity(isPressed ? 0.35 : 0.22)
        }
        return Color(nsColor: .textBackgroundColor).opacity(isPressed ? 0.75 : 1)
    }
}

struct QuickDSKYSequence: Identifiable {
    let script: DSKYScript

    var id: String { script.id }
    var label: String { script.id }
}

enum DSKYIndicatorLabel {
    static let labels: [Int: String] = [
        11: "UPLINK ACTY",
        12: "NO ATT",
        13: "STBY",
        14: "KEY REL",
        15: "OPER ERR",
        21: "TEMP",
        22: "GIMBAL LOCK",
        23: "PROG",
        24: "RESTART",
        25: "TRACKER",
        26: "ALT",
        27: "VEL"
    ]
}
