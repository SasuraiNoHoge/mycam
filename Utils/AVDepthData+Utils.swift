//
//  AVDepthData+Utils.swift
//
//  Created by Shuichi Tsutsumi on 2018/09/12.
//  Copyright © 2018 Shuichi Tsutsumi. All rights reserved.
//

import AVFoundation

extension AVDepthData {
    
    // Depth に変換するメソッド
    func convertToDepth() -> AVDepthData {
        // OSTypeは次のいずれかのタイプが得られる
        // kCVPixelFormatType_DisparityFloat16
        // kCVPixelFormatType_DisparityFloat32
        // kCVPixelFormatType_DepthFloat16
        // kCVPixelFormatType_DepthFloat32
        let targetType: OSType
        switch depthDataType {
        case kCVPixelFormatType_DisparityFloat16:
            targetType = kCVPixelFormatType_DepthFloat16
        case kCVPixelFormatType_DisparityFloat32:
            targetType = kCVPixelFormatType_DepthFloat32
        default:
            // もともと Depth
            return self
        }
        // DisparityをDepthへ
        return converting(toDepthDataType: targetType)
    }
    
    // Disparity に変換するメソッド
    func convertToDisparity() -> AVDepthData {
        let targetType: OSType
        switch depthDataType {
        case kCVPixelFormatType_DepthFloat16:
            targetType = kCVPixelFormatType_DisparityFloat16
        case kCVPixelFormatType_DepthFloat32:
            targetType = kCVPixelFormatType_DisparityFloat32
        default:
            // もともと Disparity
            return self
        }
        // DepthをDisparityへ
        return converting(toDepthDataType: targetType)
    }
}
