//
//  UIImage+Extension.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/11/8.
//

import Foundation
#if canImport(UIKit)
import UIKit
extension UIImage {
    convenience init?(contentsOf url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        self.init(data: data)
    }
    
    
    ///  Copies the current image and resizes it to the size of the given NSSize, while
    ///  maintaining the aspect ratio of the original image.
    ///
    ///  - parameter size: The size of the new image.
    ///
    ///  - returns: The resized copy of the given image.
    func resizeWhileMaintainingAspectRatioToSize(size: CGSize) -> UIImage? {
//        let widthRatio = size.width / self.size.width
//        let heightRatio = size.height / self.size.height
//        let scaleFactor = min(widthRatio, heightRatio) // Use the smaller ratio to fit within the size
//
//        let newSize = CGSize(width: self.size.width * scaleFactor, height: self.size.height * scaleFactor)
//
//        let resizedImage = UIImage(size: newSize)
//
//        resizedImage.lockFocus()
//        self.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: self.size), operation: .copy, fraction: 1.0)
//        resizedImage.unlockFocus()
//        
//        return resizedImage
        
        return self
    }
}
#endif
