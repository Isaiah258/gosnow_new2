//
//  PartySheetHostView.swift
//  雪兔滑行
//
//  Created by federico Liu on 2026/1/4.
//

import SwiftUI
import UIKit

struct PartySheetHostView: View {

    @ObservedObject var party: PartyRideController
    @State private var joinCodeInput = ""

    var body: some View {
        NavigationStack {
            if let st = party.party {
                PartyInRoomSheet(controller: party, state: st)
                    .navigationTitle("小队")
                    .navigationBarTitleDisplayMode(NavigationBarItem.TitleDisplayMode.inline)
            } else {
                PartyJoinCreateSheet(controller: party, joinCodeInput: $joinCodeInput)
                    .navigationTitle("组队同滑")
                    .navigationBarTitleDisplayMode(NavigationBarItem.TitleDisplayMode.inline)
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 未加入：创建 / 加入

private struct PartyJoinCreateSheet: View {

    @ObservedObject var controller: PartyRideController
    @Binding var joinCodeInput: String

    var body: some View {
        List {
            Section("创建小队（6 小时）") {
                Button {
                    Task { await controller.createParty() }
                } label: {
                    HStack {
                        Text("创建小队")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("加入小队（4 位加入码）") {
                TextField("例如 0427", text: $joinCodeInput)
                    .keyboardType(.numberPad)
                    .onChange(of: joinCodeInput) { _, v in
                        let filtered = v.filter(\.isNumber)
                        joinCodeInput = String(filtered.prefix(4))
                    }

                Button("加入") {
                    let code = joinCodeInput
                    Task { await controller.joinParty(code: code) }
                }
                .disabled(joinCodeInput.count != 4)
            }

            Section {
                Text("加入后将默认共享你的位置给小队成员")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 已加入：加入码 / 成员 / 退出

private struct PartyInRoomSheet: View {

    @ObservedObject var controller: PartyRideController
    let state: PartyRideController.PartyState

    @State private var toastText: String? = nil
    @State private var toastTask: Task<Void, Never>? = nil

    private func showToast(_ text: String) {
        toastTask?.cancel()
        toastText = text
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            toastText = nil
        }
    }

    var body: some View {
        List {
            Section("加入码") {
                HStack {
                    Text(state.joinCode)
                        .font(.system(size: 28, weight: .bold))
                        .monospacedDigit()
                    Spacer()
                    Button("复制") {
                        UIPasteboard.general.string = state.joinCode
                        showToast("已复制加入码")
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
            }

            Section("成员 \(controller.members.count + 1)/5") {
                // 你自己
                HStack {
                    Text(state.isHost ? "你（队长）" : "你")
                    Spacer()
                }

                // ✅ 队友：优先显示 user_name（来自 Users 表缓存）
                ForEach(controller.members) { m in
                    HStack(spacing: 10) {
                        Text(controller.displayName(for: m.id))
                        Spacer()
                    }
                }
            }

            if state.isHost {
                Section("队长操作") {
                    Button("刷新加入码") {
                        Task { await controller.regenJoinCode() }
                    }
                    .foregroundStyle(.orange)

                    Button("结束小队") {
                        Task { await controller.endParty() }
                    }
                    .foregroundStyle(.red)
                }
            }

            Section {
                Button(state.isHost ? "退出（将结束小队）" : "退出小队") {
                    Task { await controller.leaveParty() }
                }
                .foregroundStyle(.red)
            }
        }
        .overlay(alignment: .top) {
            if let t = toastText {
                Text(t)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
                    .padding(.top, 10)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: toastText)
    }
}
