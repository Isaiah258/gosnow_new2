//
//  PartyHUDView.swift
//  雪兔滑行
//
//  Created by federico Liu on 2026/1/4.
//

import SwiftUI
import UIKit

struct PartyHUDView: View {

    @ObservedObject var party: PartyRideController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // ✅ 只有加入小队后才显示顶部状态
            if let _ = party.party {
                HStack(spacing: 10) {

                    // 状态胶囊（不负责打开 sheet）
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)

                        Text("小队中 · \(party.members.count + 1)人 · 连接中")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
                    /*
                    // ✅ 退出按钮：单独胶囊
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        print("✅ tapped leave")
                        Task { await party.leaveParty() }
                    } label: {
                        Text("退出")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(.thinMaterial)
                            .clipShape(Capsule())
                    }
                   */
                    
                }
            }

            // ✅ 错误提示（你原来保留）
            if let err = party.lastError {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

