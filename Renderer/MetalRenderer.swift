//
//  MetalRenderer.swift
//
//  Created by Shuichi Tsutsumi on 2018/08/29.
//  Copyright © 2018 Shuichi Tsutsumi. All rights reserved.
//

import Metal
import MetalKit

// The max number of command buffers in flight
let kMaxBuffersInFlight: Int = 1

// Vertex data for an image plane
// 頂点情報が入っている
// 描画領域を決める
let kImagePlaneVertexData: [Float] = [
    -1.0, -1.0,  0.0, 1.0,
    1.0, -1.0,  1.0, 1.0,
    -1.0,  1.0,  0.0, 0.0,
    1.0,  1.0,  1.0, 0.0,
]

class MetalRenderer {
    // MTLDeviceクラスの変数はMetalを宣言するときに使う
    private let device: MTLDevice
    private let inFlightSemaphore = DispatchSemaphore(value: kMaxBuffersInFlight)
    private var renderDestination: MTKView
    // MTLCommandQueueクラスはGPUによって実行されるコマンドバッファーを編成するキュー
    private var commandQueue: MTLCommandQueue!
    // アプリで定義された形式でデータを保存するリソース。
    private var vertexBuffer: MTLBuffer!
    
    // 初期化
    init(metalDevice device: MTLDevice, renderDestination: MTKView) {
        // 使用するデバイスを決定
        self.device = device
        // MTKViewクラスを設定
        self.renderDestination = renderDestination
        
        // Set the default formats needed to render
        // bgra8Unormでピクセル形式を設定
        self.renderDestination.colorPixelFormat = .bgra8Unorm
        // multisampleColorTextureを設定するデフォルトは1にしておく
        // multisampleColorTextureはテクスチャのこと
        self.renderDestination.sampleCount = 1
        
        // gpuを実行するためのキューを設定
        commandQueue = device.makeCommandQueue()
                
        // prepare vertex buffer(s)
        let imagePlaneVertexDataCount = kImagePlaneVertexData.count * MemoryLayout<Float>.size
        
        // ストレージの確保
        vertexBuffer = device.makeBuffer(bytes: kImagePlaneVertexData, length: imagePlaneVertexDataCount, options: [])
        vertexBuffer.label = "vertexBuffer"
    }
    // CIContextを使えば、ある程度自動でGPU, CPUを適切に選んで処理を効率化してくれる
    private let ciContext = CIContext()
    // 色のグラデーションを生成するために必要
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    
    func update(with ciImage: CIImage) {
        // Wait to ensure only kMaxBuffersInFlight are getting proccessed by any stage in the Metal
        // pipeline (App, Metal, Drivers, GPU, etc)
        let _ = inFlightSemaphore.wait(timeout: .distantFuture)
        
        guard
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let currentDrawable = renderDestination.currentDrawable
            else {
                inFlightSemaphore.signal()
                return
        }
        commandBuffer.label = "MyCommand"
        
        commandBuffer.addCompletedHandler{ [weak self] commandBuffer in
            if let strongSelf = self {
                strongSelf.inFlightSemaphore.signal()
            }
        }
        ciContext.render(ciImage, to: currentDrawable.texture, commandBuffer: commandBuffer, bounds: ciImage.extent, colorSpace: colorSpace)
        
        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }
}
