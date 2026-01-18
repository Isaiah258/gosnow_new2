//
//  RouteDetailView.swift
//  GoSnow
//
//  Created by OpenAI on 2025/02/14.
//
import SwiftUI
import MapboxMaps
import CoreLocation

struct RouteDetailView: View {
    let route: RouteRow
    let resortName: String?

    @State private var mapView: MapView?
    @StateObject private var overlay = RouteLineOverlayController()
    @State private var isLoadingTrack = false
    @State private var trackError: String? = nil
    @State private var showRecording = false
    @AppStorage("activeRouteId") private var activeRouteId: String = ""

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                mapBlock
                contentBlock
                disclaimerBlock
                followButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .navigationTitle("路线详情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadTrackIfNeeded()
        }
        .background(
            NavigationLink(isActive: $showRecording) {
                RecordingView()
            } label: {
                EmptyView()
            }
        )
    }

    private var mapBlock: some View {
        ZStack(alignment: .center) {
            MapViewRepresentable(style: .contour) { map in
                DispatchQueue.main.async {
                    mapView = map
                    overlay.attach(to: map)
                }
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            if isLoadingTrack {
                ProgressView("加载轨迹…")
                    .padding(10)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
            } else if let trackError {
                Text(trackError)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
            }
        }
    }

    private var contentBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(route.title)
                .font(.title2.weight(.semibold))

            if let resortName {
                Text(resortName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let resortId = route.resortId {
                Text("雪场 #\(resortId)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Label("\(route.likeCount)", systemImage: "hand.thumbsup")
                Label("\(route.commentCount)", systemImage: "bubble.left")
                if let date = route.createdAt {
                    Text(Self.dateFormatter.string(from: date))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let content = route.content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(content)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var disclaimerBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("免责声明")
                .font(.headline)
            Text("路线由用户分享，仅供参考。请根据当日雪况、个人能力与现场指引判断安全性，注意风险并遵守雪场规则。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var followButton: some View {
        Button {
            activeRouteId = route.id.uuidString
            showRecording = true
        } label: {
            Text("开始跟随")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
    }

    @MainActor
    private func loadTrackIfNeeded() async {
        guard overlay.isEmpty else { return }
        guard let url = route.trackFileUrl else {
            trackError = "暂无轨迹数据"
            return
        }
        isLoadingTrack = true
        trackError = nil
        do {
            let data = try await RoutesAPI.shared.downloadTrackData(trackFileUrl: url)
            let coords = try RoutesAPI.shared.decodeTrackCoordinates(from: data)
            overlay.render(coords)
            if let mapView, !coords.isEmpty {
                mapView.mapboxMap.setCamera(to: overlay.cameraOptions(for: coords))
            }
        } catch {
            trackError = "轨迹加载失败"
        }
        isLoadingTrack = false
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
        RouteDetailView(
            route: RouteRow(
                id: UUID(),
                userId: UUID(),
                resortId: 1,
                title: "晨间畅滑",
                content: "上半段视野很好，注意入口处结冰。",
                trackFilePath: "demo.json",
                trackFileUrl: nil,
                likeCount: 12,
                commentCount: 4,
                createdAt: Date(),
                hotScore: 30
            ),
            resortName: "北山"
        )
    }
}
