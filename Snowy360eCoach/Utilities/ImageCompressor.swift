import Foundation
import UIKit

// MARK: - Image Compressor
// Aggressive compression for minimum upload size & latency.
// Design target: 512×256 JPEG Q60 → ~30-50 KB → uploads in ~100ms on 4G.

enum ImageCompressor {

    /// Compress a UIImage for upload to the AI API.
    /// Returns a base64-encoded JPEG string.
    static func compressForUpload(_ image: UIImage, quality: CGFloat = 0.6) -> String {
        let resized = resize(image, maxWidth: 512)
        let data = resized.jpegData(compressionQuality: quality) ?? Data()
        return data.base64EncodedString()
    }

    /// Resize image to a max width while preserving aspect ratio.
    static func resize(_ image: UIImage, maxWidth: CGFloat) -> UIImage {
        let scale = maxWidth / image.size.width
        if scale >= 1.0 { return image }

        let newSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Create a composite image from multiple 360° reframe views.
    /// Used to send multiple viewpoints from a single 360° frame.
    static func createCompositeImage(views: [UIImage], layout: CompositeLayout = .horizontal) -> UIImage {
        guard !views.isEmpty else { return UIImage() }
        if views.count == 1 { return views[0] }

        let singleSize = CGSize(width: 256, height: 256)

        let totalSize: CGSize
        switch layout {
        case .horizontal:
            totalSize = CGSize(width: singleSize.width * CGFloat(views.count), height: singleSize.height)
        case .grid:
            let cols = Int(ceil(sqrt(Double(views.count))))
            let rows = Int(ceil(Double(views.count) / Double(cols)))
            totalSize = CGSize(width: singleSize.width * CGFloat(cols), height: singleSize.height * CGFloat(rows))
        }

        let renderer = UIGraphicsImageRenderer(size: totalSize)
        return renderer.image { _ in
            for (index, view) in views.enumerated() {
                let rect: CGRect
                switch layout {
                case .horizontal:
                    rect = CGRect(
                        x: singleSize.width * CGFloat(index),
                        y: 0,
                        width: singleSize.width,
                        height: singleSize.height
                    )
                case .grid:
                    let cols = Int(ceil(sqrt(Double(views.count))))
                    let col = index % cols
                    let row = index / cols
                    rect = CGRect(
                        x: singleSize.width * CGFloat(col),
                        y: singleSize.height * CGFloat(row),
                        width: singleSize.width,
                        height: singleSize.height
                    )
                }
                view.draw(in: rect)
            }
        }
    }

    enum CompositeLayout {
        case horizontal  // Side by side
        case grid        // Grid layout
    }
}
