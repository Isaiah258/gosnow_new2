//
//  PartyRideController.swift
//  雪兔滑行
//
//  Created by federico Liu on 2026/1/4.
//

import Foundation
import CoreLocation
import MapboxMaps
import Supabase
import UIKit
import Turf

@MainActor
final class PartyRideController: ObservableObject {

    // MARK: - Public models

    struct Member: Identifiable, Equatable {
        let id: UUID
        var coordinate: CLLocationCoordinate2D
        var avatarURL: String? // marker fallback（如果 DB 还没查到）
    }

    struct PartyState: Equatable {
        let joinCode: String
        let hostUserId: UUID
        let isHost: Bool
        let createdAt: Date
        let expiresAt: Date
        let joinToken: UUID
    }

    enum Mode: Equatable {
        case idle
        case joined(code: String, isHost: Bool, createdAt: Date, joinToken: UUID)
    }

    // ✅ DB Profile（纯 DB 方案核心）
    struct MemberProfile: Equatable {
        let id: UUID
        let userName: String?
        let avatarURL: String?
    }

    // MARK: - Published

    @Published private(set) var mode: Mode = .idle
    @Published private(set) var members: [Member] = []              // 不包含自己（只存队友）
    @Published private(set) var profilesById: [UUID: MemberProfile] = [:] // ✅ uid -> profile（缓存）

    @Published var lastErrorMessage: String? = nil
    var lastError: String? { lastErrorMessage }

    // MARK: - Config

    let maxMembers: Int = 5
    private let ttlSeconds: TimeInterval = 6 * 60 * 60

    // MARK: - Dependencies

    private let client: SupabaseClient
    private let myUserId: UUID
    private let myAvatarURL: String?

    // MARK: - Realtime (V2)

    private var channel: RealtimeChannelV2?
    private var listenTask: Task<Void, Never>?
    private var ttlTask: Task<Void, Never>?

    // MARK: - Map

    private weak var mapView: MapView?
    private var annotations: [UUID: ViewAnnotation] = [:]

    // MARK: - Local state

    private var memberById: [UUID: Member] = [:]
    private var lastBroadcastAt: Date = .distantPast

    // ✅ profile 查询防抖 + 批量
    private var pendingProfileIds: Set<UUID> = []
    private var profileFetchTask: Task<Void, Never>?

    // MARK: - Init

    init(client: SupabaseClient, myUserId: UUID, myAvatarURL: String?) {
        self.client = client
        self.myUserId = myUserId
        self.myAvatarURL = myAvatarURL
    }

    convenience init() {
        let client = DatabaseManager.shared.client
        if let u = DatabaseManager.shared.getCurrentUser() {
            self.init(client: client, myUserId: u.id, myAvatarURL: nil)
        } else {
            self.init(client: client, myUserId: UUID(), myAvatarURL: nil)
            self.lastErrorMessage = "未登录，无法组队"
        }
    }

    // MARK: - Derived states (HUD 兼容)

    var party: PartyState? {
        switch mode {
        case .idle:
            return nil
        case .joined(let code, let isHost, let createdAt, let token):
            return PartyState(
                joinCode: code,
                hostUserId: isHost ? myUserId : myUserId, // 你后续做 DB 真 host 再改
                isHost: isHost,
                createdAt: createdAt,
                expiresAt: createdAt.addingTimeInterval(ttlSeconds),
                joinToken: token
            )
        }
    }

    // MARK: - Public helpers for UI

    func displayName(for userId: UUID) -> String {
        if let n = profilesById[userId]?.userName, !n.isEmpty { return n }
        return userId.uuidString.prefix(6) + "…"
    }

    func avatarURL(for userId: UUID) -> String? {
        profilesById[userId]?.avatarURL
    }

    // MARK: - Map attach

    func attach(to mapView: MapView) {
        self.mapView = mapView
        renderAllMembers()
    }

    // MARK: - HUD API

    func createParty() async {
        let code = String(format: "%04d", Int.random(in: 0...9999))
        let token = UUID()
        let createdAt = Date()

        mode = .joined(code: code, isHost: true, createdAt: createdAt, joinToken: token)
        await join(code: code, isHost: true, createdAt: createdAt, joinToken: token)
    }

    func joinParty(code: String) async {
        guard code.count == 4 else {
            lastErrorMessage = "加入码必须是 4 位数字"
            return
        }

        let token = UUID()
        let createdAt = Date()

        mode = .joined(code: code, isHost: false, createdAt: createdAt, joinToken: token)
        await join(code: code, isHost: false, createdAt: createdAt, joinToken: token)
    }

    func leaveParty() async {
        await leave()
    }

    func endParty() async {
        await leave()
    }

    func regenJoinCode() async {
        guard case .joined(_, let isHost, _, _) = mode, isHost else {
            lastErrorMessage = "只有队长可以刷新加入码"
            return
        }
        await endParty()
        await createParty()
    }

    // MARK: - Join / Leave (internal)

    private func cleanupConnectionOnly() async {
        ttlTask?.cancel()
        ttlTask = nil

        listenTask?.cancel()
        listenTask = nil

        if let ch = channel {
            await client.removeChannel(ch)
        }
        channel = nil

        for ann in annotations.values { ann.remove() }
        annotations.removeAll()
    }

    private func join(code: String, isHost: Bool, createdAt: Date, joinToken: UUID) async {
        // ✅ 不要 leave()，避免 mode 闪回
        await cleanupConnectionOnly()

        let ch: RealtimeChannelV2 = client.channel("party:\(code)")
        self.channel = ch

        let stream = ch.broadcastStream(event: "loc")

        listenTask?.cancel()
        listenTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await payload in stream {
                self.handleIncoming(payload: payload)
            }
        }

        await ch.subscribe()

        ttlTask?.cancel()
        ttlTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.ttlSeconds * 1_000_000_000))
            await self.leave()
        }
    }

    private func leave() async {
        await cleanupConnectionOnly()

        profileFetchTask?.cancel()
        profileFetchTask = nil
        pendingProfileIds.removeAll()

        mode = .idle
        memberById.removeAll()
        members.removeAll()

        profilesById.removeAll()
    }

    // MARK: - Send my location

    func onMyLocation(_ coord: CLLocationCoordinate2D) {
        guard party != nil else { return }
        let now = Date()
        guard now.timeIntervalSince(lastBroadcastAt) >= 1.0 else { return }
        lastBroadcastAt = now

        Task { await sendMyLocation(coord) }
    }

    private func sendMyLocation(_ coord: CLLocationCoordinate2D) async {
        guard let ch = channel else { return }

        var msg: [String: AnyJSON] = [
            "user_id": .string(myUserId.uuidString),
            "lat": .double(coord.latitude),
            "lon": .double(coord.longitude)
        ]
        if let a = myAvatarURL, !a.isEmpty {
            msg["avatar_url"] = .string(a)
        }

        await ch.broadcast(event: "loc", message: msg)
    }

    // MARK: - Handle incoming

    private func handleIncoming(payload: [String: AnyJSON]) {
        guard let uidStr = payload["user_id"]?.stringValue,
              let uid = UUID(uuidString: uidStr) else { return }
        if uid == myUserId { return }

        guard let lat = payload["lat"]?.doubleValue,
              let lon = payload["lon"]?.doubleValue else { return }

        let fallbackAvatar = payload["avatar_url"]?.stringValue
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)

        memberById[uid] = Member(id: uid, coordinate: coord, avatarURL: fallbackAvatar)

        // ✅ 总人数上限 5（含自己）→ 队友最多 4
        let maxRemote = max(0, maxMembers - 1)

        let keptIds = memberById.keys
            .sorted { $0.uuidString < $1.uuidString }
            .prefix(maxRemote)

        let keepSet = Set(keptIds)

        for id in memberById.keys where !keepSet.contains(id) {
            memberById[id] = nil
            if let ann = annotations[id] {
                ann.remove()
                annotations[id] = nil
            }
            profilesById[id] = nil // ✅ 被挤掉了，profile 也清掉
        }

        members = keptIds.compactMap { memberById[$0] }

        // ✅ 纯 DB：只在首次看到 uid 时查 Users（防抖批量）
        ensureProfilesLoaded(for: Array(keptIds))

        // marker：优先用 DB 头像（如果已经有），否则用 payload fallback
        let avatarToUse = profilesById[uid]?.avatarURL ?? fallbackAvatar
        upsertMarker(userId: uid, coordinate: coord, avatarURL: avatarToUse)
    }

    // MARK: - DB Profiles (方案 A 核心)

    private struct UsersRow: Decodable {
        let id: UUID
        let user_name: String?
        let avatar_url: String?
    }

    private func ensureProfilesLoaded(for userIds: [UUID]) {
        let missing = userIds.filter { profilesById[$0] == nil }
        guard !missing.isEmpty else { return }

        for id in missing { pendingProfileIds.insert(id) }
        scheduleProfileFetch()
    }

    private func scheduleProfileFetch() {
        profileFetchTask?.cancel()

        profileFetchTask = Task { [weak self] in
            guard let self else { return }

            // ✅ 防抖：短时间内多次进来只查一次
            try? await Task.sleep(nanoseconds: 300_000_000)

            // 取出待查 id
            let ids = await MainActor.run { () -> [UUID] in
                let arr = Array(self.pendingProfileIds)
                self.pendingProfileIds.removeAll()
                return arr
            }
            guard !ids.isEmpty else { return }

            do {
                // ✅ 关键：用 in() 批量查 Users
                let rows: [UsersRow] = try await self.client
                    .from("Users")
                    .select("id, user_name, avatar_url")
                    .in("id", values: ids.map { $0.uuidString })
                    .execute()
                    .value

                await MainActor.run {
                    for r in rows {
                        self.profilesById[r.id] = MemberProfile(
                            id: r.id,
                            userName: r.user_name,
                            avatarURL: r.avatar_url
                        )

                        // 如果 marker 已经在图上，顺便把头像换成 DB 的
                        if let ann = self.annotations[r.id],
                           let v = ann.view as? PartyAvatarMarkerView {
                            v.configure(avatarURL: r.avatar_url)
                        }
                    }
                }
            } catch {
                // 不要太吵：只在调试阶段你可以打开
                // await MainActor.run { self.lastErrorMessage = "获取成员信息失败：\(error.localizedDescription)" }
            }
        }
    }

    // MARK: - ViewAnnotation rendering

    private func renderAllMembers() {
        for m in members {
            let avatarToUse = profilesById[m.id]?.avatarURL ?? m.avatarURL
            upsertMarker(userId: m.id, coordinate: m.coordinate, avatarURL: avatarToUse)
        }
    }

    private func upsertMarker(userId: UUID, coordinate: CLLocationCoordinate2D, avatarURL: String?) {
        guard let mapView else { return }

        if let ann = annotations[userId] {
            ann.annotatedFeature = .geometry(Point(coordinate))
            if let v = ann.view as? PartyAvatarMarkerView {
                v.configure(avatarURL: avatarURL)
            }
            return
        }

        let v = PartyAvatarMarkerView(frame: CGRect(x: 0, y: 0, width: 36, height: 36))
        v.configure(avatarURL: avatarURL)

        let ann = ViewAnnotation(coordinate: coordinate, view: v)
        ann.priority = 10
        ann.variableAnchors = [ViewAnnotationAnchorConfig(anchor: .center)]

        mapView.viewAnnotations.add(ann)
        annotations[userId] = ann
    }
}

// MARK: - AnyJSON helpers

private extension AnyJSON {
    var stringValue: String? {
        if case let .string(v) = self { return v }
        return nil
    }

    var doubleValue: Double? {
        switch self {
        case let .double(v): return v
        case let .integer(v): return Double(v)
        case let .string(s): return Double(s)
        default: return nil
        }
    }
}
