//
//  SessionSummaryScreen.swift
//  雪兔滑行
//
//  Created by federico Liu on 2025/10/30.
//

import SwiftUI

struct SessionSummaryScreen: View {
    let summary: SessionSummary
    let routeImage: UIImage?
    let isGeneratingRoute: Bool
    var onClose: () -> Void

    init(
        summary: SessionSummary,
        routeImage: UIImage?,
        isGeneratingRoute: Bool = false,
        onClose: @escaping () -> Void
    ) {
        self.summary = summary
        self.routeImage = routeImage
        self.isGeneratingRoute = isGeneratingRoute
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            SessionSummarySheet(
                summary: summary,
                routeImage: routeImage,
                isGeneratingRoute: isGeneratingRoute
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { onClose() }
                }
            }
        }
        .interactiveDismissDisabled(true)
    }
}
