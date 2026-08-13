import SwiftUI
import AppKit
import LMCore

enum MissionControlChrome {
    static var dashboardColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 320), spacing: 16, alignment: .top)]
    }

    static var panelFill: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    static var panelStroke: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
    }

    static func missionPanel<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(panelFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(panelStroke)
    }

    static func metricPill(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: 180, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    static func gridRow(label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
        }
    }

    static func validationRow(label: String, isPassing: Bool, detail: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(isPassing ? "OK" : "WAIT")
                .foregroundStyle(isPassing ? .green : .orange)
            Text(detail)
        }
    }

    nonisolated static func octalRegister(_ value: Int) -> String {
        String(format: "%06o", value & 0o177777)
    }

    nonisolated static func octalWord(_ value: Int) -> String {
        String(format: "%05o", value & 0o77777)
    }

    nonisolated static func octalChannel(_ value: Int) -> String {
        String(format: "%03o", value)
    }

    nonisolated static func meters(_ value: Double) -> String {
        String(format: "%.2f m", value)
    }

    nonisolated static func metersPerSecond(_ value: Double) -> String {
        String(format: "%.3f m/s", value)
    }

    nonisolated static func kilograms(_ value: Double) -> String {
        String(format: "%.1f kg", value)
    }

    nonisolated static func vector(_ value: LMVector3D) -> String {
        String(format: "%.2f, %.2f, %.2f", value.x, value.y, value.z)
    }

    nonisolated static func quaternion(_ value: LMQuaternion) -> String {
        String(format: "%.3f, %.3f, %.3f, %.3f", value.w, value.x, value.y, value.z)
    }
}
