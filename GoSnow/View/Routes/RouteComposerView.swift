//
//  RouteComposerView.swift
//  GoSnow
//
//  Created by OpenAI on 2025/02/14.
//
import SwiftUI
import Supabase
import CoreLocation

struct RouteComposerView: View {
    @EnvironmentObject private var sessionsStore: SessionsStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSessionId: UUID? = nil
    @State private var title: String = ""
    @State private var content: String = ""
    @State private var agreeDisclaimer: Bool = false
    @State private var isPosting = false
    @State private var errorMessage: String? = nil

    let onPublished: () -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                sessionPicker
                sessionSummary
                formSection
                disclaimerSection

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await publish() }
                } label: {
                    Text(isPosting ? "发布中…" : "发布路线")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(!canPublish || isPosting)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .navigationTitle("发布路线")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("关闭") {
                    dismiss()
                }
            }
        }
        .onAppear {
            if selectedSessionId == nil {
                selectedSessionId = sessionsStore.sessions.first?.id
            }
        }
    }

    private var sessionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择滑行记录")
                .font(.headline)
            if sessionsStore.sessions.isEmpty {
                Text("暂无滑行记录")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Picker("记录", selection: Binding(get: {
                    selectedSessionId
                }, set: { selectedSessionId = $0 })) {
                    ForEach(sessionsStore.sessions) { session in
                        Text(sessionTitle(session)).tag(Optional(session.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var sessionSummary: some View {
        Group {
            if let session = selectedSession {
                VStack(alignment: .leading, spacing: 8) {
                    Text("记录详情")
                        .font(.headline)
                    HStack {
                        Text("日期")
                        Spacer()
                        Text(Self.dateFormatter.string(from: session.startAt))
                    }
                    HStack {
                        Text("距离")
                        Spacer()
                        Text(String(format: "%.1f km", session.distanceKm))
                    }
                    HStack {
                        Text("时长")
                        Spacer()
                        Text(timeString(seconds: session.durationSec))
                    }
                    if session.topSpeedKmh > 0 {
                        HStack {
                            Text("最高速度")
                            Spacer()
                            Text(String(format: "%.1f km/h", session.topSpeedKmh))
                        }
                    }
                }
                .font(.subheadline)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var formSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("路线内容")
                .font(.headline)

            TextField("路线标题（必填）", text: $title)
                .textFieldStyle(.roundedBorder)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $content)
                    .frame(minHeight: 140)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("可写：路线亮点、适合雪况、注意事项、入口/出口提示、风险提醒等…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                }
            }
        }
    }

    private var disclaimerSection: some View {
        Toggle(isOn: $agreeDisclaimer) {
            VStack(alignment: .leading, spacing: 4) {
                Text("我已阅读并同意免责声明")
                    .font(.subheadline.weight(.semibold))
                Text("路线仅供参考，需自行判断雪况与风险。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var selectedSession: SkiSession? {
        guard let id = selectedSessionId else { return nil }
        return sessionsStore.sessions.first(where: { $0.id == id })
    }

    private var canPublish: Bool {
        selectedSessionId != nil && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && agreeDisclaimer
    }

    @MainActor
    private func publish() async {
        guard let session = selectedSession else { return }
        guard let userId = DatabaseManager.shared.getCurrentUser()?.id else {
            errorMessage = "请先登录"
            return
        }

        isPosting = true
        errorMessage = nil
        defer { isPosting = false }

        do {
            guard let trackData = JSONLocalStore().loadRouteTrack(sessionId: session.id) else {
                errorMessage = "未找到该记录的轨迹数据"
                return
            }

            let path = "\(userId.uuidString)/\(session.id.uuidString)_\(Int(Date().timeIntervalSince1970)).json"
            let opts = FileOptions(contentType: "application/json")
            try await DatabaseManager.shared.client
                .storage
                .from("routes-tracks")
                .upload(path, data: trackData, options: opts)

            let publicURL = try DatabaseManager.shared.client
                .storage
                .from("routes-tracks")
                .getPublicURL(path: path)

            let payload = RouteInsert(
                userId: userId,
                resortId: session.resortId,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                trackFilePath: path,
                trackFileUrl: publicURL.absoluteString
            )

            _ = try await RoutesAPI.shared.insertRoute(payload)
            onPublished()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sessionTitle(_ session: SkiSession) -> String {
        "\(Self.dateFormatter.string(from: session.startAt)) · \(String(format: "%.1f", session.distanceKm)) km"
    }

    private func timeString(seconds: Int) -> String {
        let mins = max(seconds / 60, 0)
        let hours = mins / 60
        let remain = mins % 60
        if hours > 0 {
            return "\(hours)h \(remain)m"
        }
        return "\(remain)m"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview {
    NavigationStack {
        RouteComposerView(onPublished: {})
            .environmentObject(SessionsStore())
    }
}
