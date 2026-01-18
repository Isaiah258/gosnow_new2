//
//  PartyAvatarMarkerView.swift
//  雪兔滑行
//
//  Created by federico Liu on 2026/1/4.
//

import UIKit

@MainActor
final class PartyAvatarMarkerView: UIView {

    private let imageView = UIImageView()
    private static let cache = NSCache<NSString, UIImage>()
    private var currentURL: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.image = UIImage(systemName: "person.circle.fill")

        addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        layer.cornerRadius = 18
        layer.masksToBounds = true
        layer.borderWidth = 2
        layer.borderColor = UIColor.white.withAlphaComponent(0.95).cgColor
    }

    func configure(avatarURL: String?) {
        currentURL = avatarURL

        guard let urlStr = avatarURL, let url = URL(string: urlStr) else {
            imageView.image = UIImage(systemName: "person.circle.fill")
            return
        }

        if let cached = Self.cache.object(forKey: urlStr as NSString) {
            imageView.image = cached
            return
        }

        // ✅ 不用 detached，避免 Swift 6 并发/Sendable 警告
        Task { [weak self] in
            guard let self else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let img = UIImage(data: data) else { return }

                // 如果期间 url 变了，丢弃旧回包
                guard self.currentURL == urlStr else { return }

                Self.cache.setObject(img, forKey: urlStr as NSString)
                self.imageView.image = img
            } catch {
                // 静默失败
            }
        }
    }
}
