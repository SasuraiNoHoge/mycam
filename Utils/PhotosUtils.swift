//
//  PhotosUtils.swift
//
//  Created by Shuichi Tsutsumi on 2018/09/12.
//  Copyright © 2018 Shuichi Tsutsumi. All rights reserved.
//

import Photos
import UIKit.UIImage

// カメラロールから写真のリストをフェッチする際に，デプスデータを持つ写真に限定してアセットコレクションを取得することが可能
// subtypeをsmartAlbumDepthEffectに設定する
extension PHAsset {
    class func fetchAssetsWithDepth() -> [PHAsset] {
        let resultCollections = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .smartAlbumDepthEffect,
            options: nil)
        // コレクションからPHAsset を抽出
        var assets: [PHAsset] = []
        resultCollections.enumerateObjects({ collection, index, stop in
            let result = PHAsset.fetchAssets(in: collection, options: nil)
            result.enumerateObjects({ asset, index, stop in
                assets.append(asset)
            })
        })
        return assets
    }
    
    func requestColorImage(handler: @escaping (UIImage?) -> Void) {
        PHImageManager.default().requestImage(for: self, targetSize: PHImageManagerMaximumSize, contentMode: PHImageContentMode.aspectFit, options: nil) { (image, info) in
            handler(image)
        }
    }
    
    func hasPortraitMatte() -> Bool {
        var result: Bool = false
        let semaphore = DispatchSemaphore(value: 0)
        requestContentEditingInput(with: nil) { contentEditingInput, info in
            
            //CGImageSource オブジェクトを作成する
            // CGImageSourceは画像情報
            let imageSource = contentEditingInput?.createImageSource()
            result = imageSource?.getMatteData() != nil
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }
}

extension PHContentEditingInput {
    func createDepthImage() -> CIImage {
        guard let url = fullSizeImageURL else { fatalError() }
        // デプスマップをCIImageとして直接渡す
        return CIImage(contentsOf: url, options: [CIImageOption.auxiliaryDisparity : true])!
    }
    
    func createImageSource() -> CGImageSource {
        guard let url = fullSizeImageURL else { fatalError() }
        return CGImageSourceCreateWithURL(url as CFURL, nil)!
    }
}
