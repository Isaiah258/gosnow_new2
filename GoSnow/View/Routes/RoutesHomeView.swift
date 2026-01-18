//
//  RoutesHomeView.swift
//  GoSnow
//
//  Created by OpenAI on 2025/02/14.
//
import SwiftUI
import Supabase

struct RoutesHomeView: View {
    @State private var routes: [RouteRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var sortOption: RoutesSortOption = .latest
    @State private var resorts: [ResortOption] = []
    @State private var selectedResortId: Int? = nil
    @State private var showComposer = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                filterBar

                if isLoading {
                    ProgressView("加载中…")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 24)
                } else if let errorMessage {
                    VStack(spacing: 8) {
                        Text("加载失败").font(.headline)
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("重试") {
                            Task { await loadRoutes() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                } else if routes.isEmpty {
                    Text("暂无路线")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(routes) { route in
                            NavigationLink {
                                RouteDetailView(route: route, resortName: resortName(for: route.resortId))
                            } label: {
                                RouteCardView(route: route, resortName: resortName(for: route.resortId))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .navigationTitle("路线分享")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showComposer = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showComposer) {
            NavigationStack {
                RouteComposerView(onPublished: {
                    showComposer = false
                    Task { await loadRoutes() }
                })
            }
        }
        .task {
            await loadResorts()
            await loadRoutes()
        }
        .onChange(of: sortOption) { _, _ in
            Task { await loadRoutes() }
        }
        .onChange(of: selectedResortId) { _, _ in
            Task { await loadRoutes() }
        }
    }

    private var filterBar: some View {
        VStack(spacing: 10) {
            Picker("排序", selection: $sortOption) {
                ForEach(RoutesSortOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("雪场")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("雪场", selection: Binding(get: {
                    selectedResortId ?? -1
                }, set: { newValue in
                    selectedResortId = newValue == -1 ? nil : newValue
                })) {
                    Text("全部").tag(-1)
                    ForEach(resorts) { resort in
                        Text(resort.name).tag(resort.id)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func resortName(for id: Int?) -> String? {
        guard let id else { return nil }
        return resorts.first(where: { $0.id == id })?.name
    }

    @MainActor
    private func loadRoutes() async {
        isLoading = true
        errorMessage = nil
        do {
            routes = try await RoutesAPI.shared.fetchRoutes(sort: sortOption, resortId: selectedResortId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func loadResorts() async {
        do {
            struct Row: Decodable {
                let id: Int
                let name_resort: String
            }
            let rows: [Row] = try await DatabaseManager.shared.client
                .from("Resorts_data")
                .select("id,name_resort")
                .order("name_resort", ascending: true)
                .limit(200)
                .execute()
                .value
            resorts = rows.map { ResortOption(id: $0.id, name: $0.name_resort) }
        } catch {
            resorts = []
        }
    }
}

private struct ResortOption: Identifiable, Hashable {
    let id: Int
    let name: String
}

private struct RouteCardView: View {
    let route: RouteRow
    let resortName: String?

    var body: some View {
        RoundedContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text(route.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

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
            }
            .padding(14)
        }
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
        RoutesHomeView()
    }
}
