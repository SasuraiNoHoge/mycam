//
//  VideoCameraType.swift
//
//  Created by Shuichi Tsutsumi on 4/3/16.
//  Copyright © 2016 Shuichi Tsutsumi. All rights reserved.
//

import AVFoundation

enum CameraType {
    case back(Bool)
    case front(Bool)
    
    // AVCaptureDeviceはカメラなどのデバイスを取得
    func captureDevice() -> AVCaptureDevice {
        let devices: [AVCaptureDevice]
        switch self {
        case .front(let requireDepth):
            // フロントのTrueDepthカメラのAVCaptureDeviceを取得
            var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInTrueDepthCamera]
            if !requireDepth {
                deviceTypes.append(.builtInWideAngleCamera)
            }
            devices = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: .front).devices
        case .back(let requireDepth):
            // リアのデュアルカメラのAVCaptureDevice を取得
            var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInDualCamera]
            if !requireDepth {
                deviceTypes.append(contentsOf: [.builtInWideAngleCamera, .builtInTelephotoCamera])
            }
            devices = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: .back).devices
        }
        guard let device = devices.first else {
            return AVCaptureDevice.default(for: .video)!
        }
        return device
    }
}
