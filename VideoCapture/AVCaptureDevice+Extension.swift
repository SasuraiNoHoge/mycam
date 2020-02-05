//
//  AVCaptureDevice+Extension.swift
//
//  Created by Shuichi Tsutsumi on 4/3/16.
//  Copyright © 2016 Shuichi Tsutsumi. All rights reserved.
//

import AVFoundation

extension AVCaptureDevice {    
    private func formatWithHighestResolution(_ availableFormats: [AVCaptureDevice.Format]) -> AVCaptureDevice.Format?
    {
        //解像度やフレームレートなどのビデオフォーマットを変更
        var maxWidth: Int32 = 0
        var selectedFormat: AVCaptureDevice.Format?
        for format in availableFormats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let width = dimensions.width
            if width >= maxWidth {
                maxWidth = width
                selectedFormat = format
            }
        }
        return selectedFormat
    }
    
    func selectDepthFormat() {
        // supportedDepthDataFormatsがデプスデータフォーマットのリストを取得する
        let availableFormats = formats.filter { format -> Bool in
            let validDepthFormats = format.supportedDepthDataFormats.filter {
                CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_DepthFloat32
            }
            return validDepthFormats.count > 0
        }
        guard let selectedFormat = formatWithHighestResolution(availableFormats) else { fatalError() }
        
        // 利用可能なデプスフォーマットのリストを取得
        let depthFormats = selectedFormat.supportedDepthDataFormats
        
        // Depth タイプでビット深度が32のフォーマットだけに絞り込む
        let depth32formats = depthFormats.filter {
            CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_DepthFloat32
        }
        guard !depth32formats.isEmpty else { fatalError() }
        
        // 解像度が最大のものを選ぶ
        let selectedDepthFormat = depth32formats.max(by: {
            CMVideoFormatDescriptionGetDimensions($0.formatDescription).width
                < CMVideoFormatDescriptionGetDimensions($1.formatDescription).width
        })!

        print("selected format: \(selectedFormat), depth format: \(selectedDepthFormat)")
        // 選択したフォーマットをセットする
        try! lockForConfiguration()
        activeFormat = selectedFormat
        // デプスデータのフォーマット
        activeDepthDataFormat = selectedDepthFormat
        unlockForConfiguration()
    }
}
