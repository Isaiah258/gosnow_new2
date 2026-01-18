//
//  RouteTrackCache.swift
//  GoSnow
//
//  Created by OpenAI on 2025/02/14.
//
import Foundation

struct RouteTrackCache {
    static func load(routeId: UUID) -> Data? {
        let url = cacheURL(for: routeId)
        return try? Data(contentsOf: url)
    }

    static func save(_ data: Data, routeId: UUID) {
        let url = cacheURL(for: routeId)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            print("❌ route track cache save failed: \(error)")
        }
    }

    static func remove(routeId: UUID) {
        let url = cacheURL(for: routeId)
        try? FileManager.default.removeItem(at: url)
    }

    private static func cacheURL(for routeId: UUID) -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("routes", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("\(routeId.uuidString).json")
    }
}
