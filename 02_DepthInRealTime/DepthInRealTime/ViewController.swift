//
//  ViewController.swift
//
//  Created by Shuichi Tsutsumi on 2018/08/20.
//  Copyright © 2018 Shuichi Tsutsumi. All rights reserved.
//

import UIKit
import MetalKit
import AVFoundation

class ViewController: UIViewController {
    // @IBOutletとはInterfaceBuilderOutletの略称
    // storyboardと繋がってることを意味しfてる
    // weakはnilになり得ることを許してる
    // UIViewは画面
    @IBOutlet weak var previewView: UIView!
    // MTKViewとはMetalKitViewの略称
    // MTKViewはCAMetalLayerのラッパークラス
    @IBOutlet weak var mtkView: MTKView!
    @IBOutlet weak var filterSwitch: UISwitch!
    @IBOutlet weak var disparitySwitch: UISwitch!
    @IBOutlet weak var equalizeSwitch: UISwitch!

    private var videoCapture: VideoCapture!
    
    // 最初はフロントカメラに設定
    var currentCameraType: CameraType = .front(true)
    private let serialQueue = DispatchQueue(label: "com.shu223.DepthBook.queue")

    // MetalはGPU描画をするために用いる
    private var renderer: MetalRenderer!
    private var depthImage: CIImage?
    //CGSizeは対象オブジェクトのサイズを設定
    private var currentDrawableSize: CGSize!

    private var videoImage: CIImage?
    
    // キャプチャーの出力データを受け付けるオブジェクト
    var photoOutput : AVCapturePhotoOutput?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Metalを処理するための初期化
        let device = MTLCreateSystemDefaultDevice()!
        // 使うデバイスを設定
        mtkView.device = device
        // 背景の設定
        mtkView.backgroundColor = UIColor.clear
        // falseにすることでframebufferへの書き込みが可能になる
        mtkView.framebufferOnly = false
        // デリゲートに設定
        // ViewControllerのextensionでMTKViewDelegateを継承
        mtkView.delegate = self
        
        // Metalを扱う
        renderer = MetalRenderer(metalDevice: device, renderDestination: mtkView)
        // 描画可能サイズを設定
        currentDrawableSize = mtkView.currentDrawable!.layer.drawableSize
        
        // VideoCaptureクラスを設定
        videoCapture = VideoCapture(cameraType: currentCameraType,
                                    preferredSpec: nil,
                                    previewContainer: previewView.layer)
        
        // 同期のためのBufferHandloerを設定
        videoCapture.syncedDataBufferHandler = { [weak self] videoPixelBuffer, depthData, face in
            guard let self = self else { return }
            
            self.videoImage = CIImage(cvPixelBuffer: videoPixelBuffer)

            var useDisparity: Bool = false
            var applyHistoEq: Bool = false
            DispatchQueue.main.sync(execute: {
                useDisparity = self.disparitySwitch.isOn
                applyHistoEq = self.equalizeSwitch.isOn
            })
            
            self.serialQueue.async {
                guard let depthData = useDisparity ? depthData?.convertToDisparity() : depthData else { return }
                // ciImageにdepthDataを設定
                guard let ciImage = depthData.depthDataMap.transformedImage(targetSize: self.currentDrawableSize, rotationAngle: 0) else { return }
                self.depthImage = applyHistoEq ? ciImage.applyingFilter("YUCIHistogramEqualization") : ciImage
            }
        }
        // falseにすると超近接でも扱える
        videoCapture.setDepthFilterEnabled(filterSwitch.isOn)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard let videoCapture = videoCapture else {return}
        // カメラの描画開始
        videoCapture.startCapture()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let videoCapture = videoCapture else {return}
        videoCapture.resizePreview()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        guard let videoCapture = videoCapture else {return}
        videoCapture.imageBufferHandler = nil
        videoCapture.stopCapture()
        mtkView.delegate = nil
        super.viewWillDisappear(animated)
    }
    
    // MARK: - Actions
    
    // ＿は未使用の時の警告を消す
    //cameraSwitchBtnがタップされたら呼ばれる
    @IBAction func cameraSwitchBtnTapped(_ sender: UIButton) {
        //カメラの向きを切り替える
        switch currentCameraType {
        case .back:
            currentCameraType = .front(true)
        case .front:
            currentCameraType = .back(true)
        }
        // withの意味はわからん
        videoCapture.changeCamera(with: currentCameraType)
    }
    
    @IBAction func filterSwitched(_ sender: UISwitch) {
        videoCapture.setDepthFilterEnabled(sender.isOn)
    }
    
    @IBAction func saveButton(_ sender: UIButton) {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        // カメラの手ぶれ補正
        settings.isAutoStillImageStabilizationEnabled = true
        // photoOutputにどうにかして，深度画像を含んだ情報を送りたい
        // AVCaptureDepthDataOutputは深度情報を取得できるが写真としては保存できない
        
        photoOutput = videoCapture.getphotoOutput()
        
        if photoOutput?.isDepthDataDeliverySupported == true{
            settings.isDepthDataDeliveryEnabled = true
            // print("通った") 通りはしたが深度情報が残っているか不明
        }
        
        // 撮影された画像をdelegateメソッドで処理
        // 画像をカメラロールに保存
        // Thread 1: signal SIGABRT
        photoOutput?.capturePhoto(with: settings, delegate: self as! AVCapturePhotoCaptureDelegate)
        
    }
}

extension ViewController: MTKViewDelegate,
AVCapturePhotoCaptureDelegate{
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        currentDrawableSize = size
    }
    
    func draw(in view: MTKView) {
        if let image = depthImage {
            renderer.update(with: image)
        }
    }
    
    // 撮影した画像データが生成されたときに呼び出されるデリゲートメソッド
      func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
          if let imageData = photo.fileDataRepresentation() {
              // Data型をUIImageオブジェクトに変換
              // UIImageに変換するとexif情報が失われる
              let uiImage = UIImage(data: imageData)
              // 写真ライブラリに画像を保存
              UIImageWriteToSavedPhotosAlbum(uiImage!, nil,nil,nil)
          }
      }
}
