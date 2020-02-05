//
//  VideoCapture.swift
//
//  Created by Shuichi Tsutsumi on 4/3/16.
//  Copyright © 2016 Shuichi Tsutsumi. All rights reserved.
//

import AVFoundation
import Foundation


struct VideoSpec {
    var fps: Int32?
    var size: CGSize?
}
// CMTimeは時間を扱う際に使う
// 最初はとりあえずVoidで空にする
typealias ImageBufferHandler = (CVPixelBuffer, CMTime, CVPixelBuffer?) -> Void

// AVMetadataObjectでメタデータの種類を規定
// AVMetadataObjectはCMTimeと関係してる?
typealias SynchronizedDataBufferHandler = (CVPixelBuffer, AVDepthData?, AVMetadataObject?) -> Void

// オーディオやビデオを扱うために必要
extension AVCaptureDevice {
    // formatsにdepthデータが含まれるかを確認する
    func printDepthFormats() {
        formats.forEach { (format) in
            let depthFormats = format.supportedDepthDataFormats
            if depthFormats.count > 0 {
                print("format: \(format), supported depth formats: \(depthFormats)")
            }
        }
    }
}

class VideoCapture: NSObject {
    // 動画を撮影するためにまずはAVCaptureSessionをインスタンス化する必要がある
    private let captureSession = AVCaptureSession()
    // AVCaptureDeviceはカメラなどのデバイスを取得
    private var videoDevice: AVCaptureDevice!
    // カメラの入力と出力を繋げる
    private var videoConnection: AVCaptureConnection!
    
    // ビデオの表示に必要
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    // 処理するキューを取得
    private let dataOutputQueue = DispatchQueue(label: "com.shu223.dataOutputQueue")

    // ハンドラを設定
    var imageBufferHandler: ImageBufferHandler?
    var syncedDataBufferHandler: SynchronizedDataBufferHandler?

    // プロパティで保持しておかないとdelegate呼ばれない
    // AVCaptureDepthDataOutputはプロパティで保持しなくても大丈夫（CaptureSessionにaddOutputするからだと思う）
    private var dataOutputSynchronizer: AVCaptureDataOutputSynchronizer!
    
    // プロパティに保持しておかなくてもOKだが、AVCaptureSynchronizedDataCollectionからデータを取り出す際にあると便利
    // ビデオ出力
    private let videoDataOutput = AVCaptureVideoDataOutput()
    // デプスデータを出力するクラス
    // これを受け取りたり
    private let depthDataOutput = AVCaptureDepthDataOutput()
    // メタデータを出力するクラス
    private let metadataOutput = AVCaptureMetadataOutput()
    
    // 写真を保存するための出力
    private let photoOutput = AVCapturePhotoOutput()
    
    // デプスデータを取得したい
    func getphotoOutput() -> AVCapturePhotoOutput{
        return photoOutput
    }
    
    // 諸々初期化
    // VideoSpecはビデオのサイズとか
    // CALayerは画像ベースのコンテンツを管理し，そのコンテンツでアニメーションを実行できるようにするオブジェクト
    // CameraTypeはVideoCameraType.swiftから指定される
    init(cameraType: CameraType, preferredSpec: VideoSpec?, previewContainer: CALayer?)
    {
        // 初期化
        super.init()
        
        // 初期化が完了したことをcaptureSessionに知らせる
        captureSession.beginConfiguration()
        
        // inputPriorityだと深度とれない
        // sessionPresetは出力の品質レベルまたはビットレートを示す定数値。
        captureSession.sessionPreset = AVCaptureSession.Preset.photo
        // cameraTypeからビデオデバイスを設定
        setupCaptureVideoDevice(with: cameraType)
        
        // setup preview
        if let previewContainer = previewContainer {
            let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.frame = previewContainer.bounds
            previewLayer.contentsGravity = CALayerContentsGravity.resizeAspectFill
            previewLayer.videoGravity = .resizeAspectFill
            previewContainer.insertSublayer(previewLayer, at: 0)
            self.previewLayer = previewLayer
        }
        
        // setup outputs
        do {
            // video output
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
            guard captureSession.canAddOutput(videoDataOutput) else { fatalError() }
            captureSession.addOutput(videoDataOutput)
            videoConnection = videoDataOutput.connection(with: .video)

            // depth output
            guard captureSession.canAddOutput(depthDataOutput) else { fatalError() }
            captureSession.addOutput(depthDataOutput)
            depthDataOutput.setDelegate(self, callbackQueue: dataOutputQueue)
            depthDataOutput.isFilteringEnabled = false
            guard let connection = depthDataOutput.connection(with: .depthData) else { fatalError() }
            connection.isEnabled = true
            
            // metadata output
            guard captureSession.canAddOutput(metadataOutput) else { fatalError() }
            captureSession.addOutput(metadataOutput)
            if metadataOutput.availableMetadataObjectTypes.contains(.face) {
                metadataOutput.metadataObjectTypes = [.face]
            }
            
            // 写真を保存するためのoutputを取得
            guard captureSession.canAddOutput(photoOutput)
                else { fatalError() }
            captureSession.addOutput(photoOutput)
            // 深度情報を渡せるように設定
            photoOutput.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported
            
            // synchronize outputs
            // ビデオとデプスを同期して出力される
            dataOutputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoDataOutput, depthDataOutput, metadataOutput])
            dataOutputSynchronizer.setDelegate(self, queue: dataOutputQueue)
        }
        // 接続設定(カメラの向きとかを決める)
        setupConnections(with: cameraType)
        
        // 一連の構成変更をコミットしてcaptureSessionを更新
        captureSession.commitConfiguration()
    }
    
    // withは引数にcameraTypeを持ってることを意味する?
    // VideoDeviceをセットアップする
    private func setupCaptureVideoDevice(with cameraType: CameraType) {
        // captureDevice()はカメラがバックかリアかを指定する
        videoDevice = cameraType.captureDevice()
        print("selected video device: \(String(describing: videoDevice))")
        
        // デプスフォーマットを設定
        videoDevice.selectDepthFormat()

        // captureSession.inputsはキャプチャセッションの入力
        captureSession.inputs.forEach { (captureInput) in
            captureSession.removeInput(captureInput)
        }
        // deviceから入力画像を取得
        let videoDeviceInput = try! AVCaptureDeviceInput(device: videoDevice)
        guard captureSession.canAddInput(videoDeviceInput) else { fatalError() }
        // captureSessionに入力画像を追加
        captureSession.addInput(videoDeviceInput)
    }
    
    // 接続設定(カメラの向きとかを決める)
    private func setupConnections(with cameraType: CameraType) {
        videoConnection = videoDataOutput.connection(with: .video)!
        let depthConnection = depthDataOutput.connection(with: .depthData)
        switch cameraType {
        case .front:
            videoConnection.isVideoMirrored = true
            depthConnection?.isVideoMirrored = true
        default:
            break
        }
        videoConnection.videoOrientation = .portrait
        depthConnection?.videoOrientation = .portrait
    }
    
    func startCapture() {
        print("\(self.classForCoder)/" + #function)
        if captureSession.isRunning {
            print("already running")
            return
        }
        // ここからカメラを描画し始める
        captureSession.startRunning()
    }
    
    func stopCapture() {
        print("\(self.classForCoder)/" + #function)
        if !captureSession.isRunning {
            print("already stopped")
            return
        }
        captureSession.stopRunning()
    }
    
    func resizePreview() {
        if let previewLayer = previewLayer {
            guard let superlayer = previewLayer.superlayer else {return}
            previewLayer.frame = superlayer.bounds
        }
    }
    
    // 使用するカメラの変更
    // CameraTypeはデプスカメラかどうかを取得してる
    func changeCamera(with cameraType: CameraType) {
        
        let wasRunning = captureSession.isRunning
        if wasRunning {
            captureSession.stopRunning()
        }
        captureSession.beginConfiguration()

        setupCaptureVideoDevice(with: cameraType)
        setupConnections(with: cameraType)
        
        captureSession.commitConfiguration()
        
        if wasRunning {
            captureSession.startRunning()
        }
    }

    func setDepthFilterEnabled(_ enabled: Bool) {
        depthDataOutput.isFilteringEnabled = enabled
    }
}

extension VideoCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    // AVCaptureSynchronizedSampleBufferDataクラスのsampleBufferプロパティよりCMSampleBuffer型で当該フレームのビデオのサンプルバッファが得られる
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
//        print("\(self.classForCoder)/" + #function)
    }
    
    // synchronizer使ってる場合は呼ばれない
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if let imageBufferHandler = imageBufferHandler, connection == videoConnection
        {
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { fatalError() }

            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            imageBufferHandler(imageBuffer, timestamp, nil)
        }
    }
}

extension VideoCapture: AVCaptureDepthDataOutputDelegate {
    
    // デプスデータがドロップされると呼ばれる(didDrop)
    // AVCaptureSynchronizedDepthDataクラスのdepthDataプロパティよりAVDepthData型で当該フレームのデプスデータが得られる
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didDrop depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection, reason: AVCaptureOutput.DataDroppedReason) {
        print("\(self.classForCoder)/\(#function)")
    }
    
    // synchronizer使ってる場合は呼ばれない
    // AVCaptureDepthDataOutputからの出力を得ると呼ばれる(didOutput)
    // didOutputメソッドの第二引数にはAVDepthDataオブジェクトが得られる
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        print("\(self.classForCoder)/\(#function)")
    }
}

extension VideoCapture: AVCaptureDataOutputSynchronizerDelegate {
    // 同期した出力をdidOutputメソッドの第二引数よりAVCaptureSynchronizedDataCollectionオブジェクト
    //として受け取れる
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer, didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        
        // AVCaptureVideoDataOutputを指定した場合は，AVCaptureSynchronizedSampleBufferDataオブジェクトが得られる．
        
        guard let syncedVideoData = synchronizedDataCollection.synchronizedData(for: videoDataOutput) as? AVCaptureSynchronizedSampleBufferData else { return }
        guard !syncedVideoData.sampleBufferWasDropped else {
            print("dropped video:\(syncedVideoData)")
            return
        }
        let videoSampleBuffer = syncedVideoData.sampleBuffer

        // AVCaptureDepthDataOutputを指定した場合は，AVCaptureSynchronizedDepthDataオブジェクトが得られる
        let syncedDepthData = synchronizedDataCollection.synchronizedData(for: depthDataOutput) as? AVCaptureSynchronizedDepthData
        var depthData = syncedDepthData?.depthData
        if let syncedDepthData = syncedDepthData, syncedDepthData.depthDataWasDropped {
            print("dropped depth:\(syncedDepthData)")
            depthData = nil
        }

        // 顔のある位置のしきい値を求める
        let syncedMetaData = synchronizedDataCollection.synchronizedData(for: metadataOutput) as? AVCaptureSynchronizedMetadataObjectData
        var face: AVMetadataObject? = nil
        if let firstFace = syncedMetaData?.metadataObjects.first {
            face = videoDataOutput.transformedMetadataObject(for: firstFace, connection: videoConnection)
        }
        guard let imagePixelBuffer = CMSampleBufferGetImageBuffer(videoSampleBuffer) else { fatalError() }

        syncedDataBufferHandler?(imagePixelBuffer, depthData, face)
    }
}
