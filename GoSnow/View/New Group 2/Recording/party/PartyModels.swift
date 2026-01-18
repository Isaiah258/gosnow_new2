//
//  PartyModels.swift
//  雪兔滑行
//
//  Created by federico Liu on 2026/1/4.
//

import Foundation
import CoreLocation

struct PartyState: Equatable {
    let partyId: UUID
    let joinCode: String
    let joinToken: UUID
    let expiresAt: Date
    let hostUserId: UUID
    let myUserId: UUID

    var isHost: Bool { hostUserId == myUserId }
    var channelTopic: String { "party:\(joinToken.uuidString)" } // ✅ 用 token 当频道名
}

struct PartyMemberProfile: Identifiable, Equatable {
    let id: UUID           // user_id
    let userName: String?
    let avatarURL: String?
}

struct PartyLastLocation: Decodable {
    let party_id: UUID
    let user_id: UUID
    let lat: Double
    let lon: Double
    let updated_at: Date?
}

struct PartyRPCRow: Decodable {
    let party_id: UUID
    let join_code: String
    let join_token: UUID
    let expires_at: Date
    let host_user_id: UUID
}
