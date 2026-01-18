//
//  PartyService.swift
//  雪兔滑行
//
//  Created by federico Liu on 2026/1/4.
//

import Foundation
import Supabase

final class PartyService {

    private let client: SupabaseClient

    init(client: SupabaseClient = DatabaseManager.shared.client) {
        self.client = client
    }

    func currentUserId() throws -> UUID {
        guard let u = DatabaseManager.shared.getCurrentUser() else {
            throw NSError(domain: "Party", code: -1, userInfo: [NSLocalizedDescriptionKey: "未登录"])
        }
        return u.id
    }

    // MARK: - RPC

    func createParty() async throws -> PartyRPCRow {
        let rows: [PartyRPCRow] = try await client
            .rpc("party_create")
            .execute()
            .value
        guard let first = rows.first else { throw NSError(domain: "Party", code: -2) }
        return first
    }

    func joinParty(code: String) async throws -> PartyRPCRow {
        let rows: [PartyRPCRow] = try await client
            .rpc("party_join_by_code", params: ["p_code": code])
            .execute()
            .value
        guard let first = rows.first else { throw NSError(domain: "Party", code: -3) }
        return first
    }

    func joinParty(token: UUID) async throws -> PartyRPCRow {
        let rows: [PartyRPCRow] = try await client
            .rpc("party_join_by_token", params: ["p_token": token.uuidString])
            .execute()
            .value
        guard let first = rows.first else { throw NSError(domain: "Party", code: -4) }
        return first
    }

    func leaveParty(partyId: UUID) async throws {
        _ = try await client
            .rpc("party_leave", params: ["p_party_id": partyId.uuidString])
            .execute()
    }

    func endParty(partyId: UUID) async throws {
        _ = try await client
            .rpc("party_end", params: ["p_party_id": partyId.uuidString])
            .execute()
    }

    func regenCode(partyId: UUID) async throws -> String {
        // 这个 RPC returns text（单值），Supabase Swift 会把它当成数组行
        let rows: [String] = try await client
            .rpc("party_regen_code", params: ["p_party_id": partyId.uuidString])
            .execute()
            .value
        return rows.first ?? "0000"
    }

    // MARK: - Queries

    struct MemberRow: Decodable {
        let user_id: UUID
        let Users: UserRow?

        struct UserRow: Decodable {
            let user_name: String?
            let avatar_url: String?
        }
    }

    func fetchMembers(partyId: UUID) async throws -> [PartyMemberProfile] {
        // 依赖你 Users 表字段：user_name / avatar_url
        let rows: [MemberRow] = try await client
            .from("party_member")
            .select("user_id, Users(user_name, avatar_url)")
            .eq("party_id", value: partyId.uuidString)
            .is("left_at", value: nil)
            .execute()
            .value

        return rows.map {
            PartyMemberProfile(
                id: $0.user_id,
                userName: $0.Users?.user_name,
                avatarURL: $0.Users?.avatar_url
            )
        }
    }

    func fetchLastLocations(partyId: UUID) async throws -> [PartyLastLocation] {
        let rows: [PartyLastLocation] = try await client
            .from("party_location_last")
            .select("party_id, user_id, lat, lon, updated_at")
            .eq("party_id", value: partyId.uuidString)
            .execute()
            .value
        return rows
    }

    func upsertMyLastLocation(partyId: UUID, userId: UUID, lat: Double, lon: Double) async throws {
        struct UpsertRow: Encodable {
            let party_id: String
            let user_id: String
            let lat: Double
            let lon: Double
            let updated_at: String
        }

        let iso = ISO8601DateFormatter()
        let row = UpsertRow(
            party_id: partyId.uuidString,
            user_id: userId.uuidString,
            lat: lat,
            lon: lon,
            updated_at: iso.string(from: Date())
        )

        _ = try await client
            .from("party_location_last")
            .upsert(row)
            .execute()
    }
}

