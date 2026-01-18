//
//  RoutesModels.swift
//  GoSnow
//
//  Created by OpenAI on 2025/02/14.
//
import Foundation

struct RouteRow: Identifiable, Codable, Hashable {
    let id: UUID
    let userId: UUID
    let resortId: Int?
    let title: String
    let content: String?
    let trackFilePath: String
    let trackFileUrl: String?
    let likeCount: Int
    let commentCount: Int
    let createdAt: Date?
    let hotScore: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case resortId = "resort_id"
        case title
        case content
        case trackFilePath = "track_file_path"
        case trackFileUrl = "track_file_url"
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case createdAt = "created_at"
        case hotScore = "hot_score"
    }
}

struct RouteInsert: Encodable {
    let userId: UUID
    let resortId: Int?
    let title: String
    let content: String?
    let trackFilePath: String
    let trackFileUrl: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case resortId = "resort_id"
        case title
        case content
        case trackFilePath = "track_file_path"
        case trackFileUrl = "track_file_url"
    }
}

struct RouteComment: Identifiable, Codable, Hashable {
    let id: UUID
    let routeId: UUID
    let userId: UUID
    let content: String
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case routeId = "route_id"
        case userId = "user_id"
        case content
        case createdAt = "created_at"
    }
}

struct RouteLike: Identifiable, Codable, Hashable {
    let id: UUID
    let routeId: UUID
    let userId: UUID
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case routeId = "route_id"
        case userId = "user_id"
        case createdAt = "created_at"
    }
}

enum RoutesSortOption: String, CaseIterable, Identifiable {
    case latest
    case hot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .latest: return "最新"
        case .hot: return "热门"
        }
    }
}
