//
//  RoutesAPI.swift
//  GoSnow
//
//  Created by OpenAI on 2025/02/14.
//
import Foundation
import Supabase
import CoreLocation

final class RoutesAPI {
    static let shared = RoutesAPI()

    private let client: SupabaseClient

    init(client: SupabaseClient = DatabaseManager.shared.client) {
        self.client = client
    }

    func fetchRoutes(sort: RoutesSortOption, resortId: Int? = nil, limit: Int = 50) async throws -> [RouteRow] {
        var query = client
            .from("routes")
            .select("id,user_id,resort_id,title,content,track_file_path,track_file_url,like_count,comment_count,created_at,hot_score")

        if let resortId {
            query = query.eq("resort_id", value: resortId)
        }

        switch sort {
        case .latest:
            query = query.order("created_at", ascending: false)
        case .hot:
            query = query.order("hot_score", ascending: false)
        }

        let rows: [RouteRow] = try await query.limit(limit).execute().value
        return rows
    }

    func fetchRouteDetail(routeId: UUID) async throws -> RouteRow? {
        let rows: [RouteRow] = try await client
            .from("routes")
            .select("id,user_id,resort_id,title,content,track_file_path,track_file_url,like_count,comment_count,created_at,hot_score")
            .eq("id", value: routeId.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    func insertRoute(_ payload: RouteInsert) async throws -> RouteRow {
        let rows: [RouteRow] = try await client
            .from("routes")
            .insert(payload)
            .select("id,user_id,resort_id,title,content,track_file_path,track_file_url,like_count,comment_count,created_at,hot_score")
            .limit(1)
            .execute()
            .value
        guard let row = rows.first else {
            throw NSError(domain: "RoutesAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "insert routes returned empty"])
        }
        return row
    }

    func downloadTrackData(trackFileUrl: String) async throws -> Data {
        guard let url = URL(string: trackFileUrl) else {
            throw NSError(domain: "RoutesAPI", code: -2, userInfo: [NSLocalizedDescriptionKey: "invalid track url"])
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "RoutesAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "track download failed"])
        }
        return data
    }

    func decodeTrackCoordinates(from data: Data) throws -> [CLLocationCoordinate2D] {
        let raw = try JSONDecoder().decode([[Double]].self, from: data)
        return raw.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
        }
    }
}
