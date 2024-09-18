import simd
import Metal
import UIKit
import CoreVideo
import AVFoundation

final class ReactionCanvasView: UIView {
    // MARK: - Lifecycle
    
    override init(frame: CGRect) {
        self.scale = UIScreen.main.scale
        
        super.init(frame: frame)
        self.setup()
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.displayLink?.invalidate()
        
        if let didEnterBakgroundObserver {
            NotificationCenter.default.removeObserver(didEnterBakgroundObserver)
        }
        
        if let willEnterForegroundObserver {
            NotificationCenter.default.removeObserver(willEnterForegroundObserver)
        }
    }
    
    // MARK: - Layer
    
    override class var layerClass: AnyClass {
        return CAMetalLayer.self
    }
    
    // MARK: - Internal
    
    var onTextureFlush: ((MTLTexture) -> Void)?
    
    override var frame: CGRect {
        didSet {
            let size = self.bounds.size
            
            let drawableSize = CGSize(
                width: size.width * self.scale,
                height: size.height * self.scale
            )
            
            self.metalLayer.drawableSize = drawableSize
        }
    }
    
    func enqueueCameraSample(_ sampleBuffer: CMSampleBuffer) {
        guard let imageBuffer = sampleBuffer.imageBuffer
        else { return }
        
        var textureCache: CVMetalTextureCache? = nil
        
        CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            GPU.default.device,
            nil,
            &textureCache
        )
        
        guard let textureCache else {
            return
        }
        
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)

        var imageTexture: CVMetalTexture?
        
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            imageBuffer,
            [kCVPixelBufferMetalCompatibilityKey: true] as? CFDictionary,
            self.pixelFormat,
            width,
            height,
            0,
            &imageTexture
        )
        
        guard let imageTexture, result == kCVReturnSuccess else {
            return
        }
        
        let texture = CVMetalTextureGetTexture(imageTexture)
        
        self.cameraTexture = texture
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.pipView.frame = self.bounds
    }
    
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        
        if let _ = self.superview {
            self.startDisplayLink()
        } else {
            self.stopDisplayLink()
        }
    }
    
    // MARK: - Private
    
    private let scale: CGFloat
    
    private let pipView: ReactionPipView = .init(
        frame: .zero
    )
    
    private let verticies: [Vertex] = [
        Vertex(position: SIMD4<Float>(-1, 1, 0, 1)),
        Vertex(position: SIMD4<Float>(1, 1, 0, 1)),
        Vertex(position: SIMD4<Float>(-1, -1, 0, 1)),
        Vertex(position: SIMD4<Float>(1, 1, 0, 1)),
        Vertex(position: SIMD4<Float>(-1, -1, 0, 1)),
        Vertex(position: SIMD4<Float>(1, -1, 0, 1)),
    ]
    
    private var displayLink: CADisplayLink?
    private var samplerState: (any MTLSamplerState)?
    private var pipelineState: (any MTLRenderPipelineState)?
    private var cameraTexture: (any MTLTexture)?
    private var didEnterBakgroundObserver: (any NSObjectProtocol)?
    private var willEnterForegroundObserver: (any NSObjectProtocol)?
    
    private var metalLayer: CAMetalLayer {
        return self.layer as! CAMetalLayer
    }
    
    private var pixelFormat: MTLPixelFormat {
        return MTLPixelFormat.bgra8Unorm
    }
    
    private func setup() {
        self.metalLayer.device = GPU.default.device
        self.metalLayer.pixelFormat = self.pixelFormat
        self.metalLayer.isOpaque = true
        self.metalLayer.framebufferOnly = false
        
        self.addSubview(self.pipView)
        
        guard let library = try? GPU.default.device.makeDefaultLibrary(
            bundle: Bundle.main
        ) else { return }
        
        guard let vertexFunc = library.makeFunction(name: "vertex_main"),
              let fragmentFunc = library.makeFunction(name: "fragment_main")
        else { return }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunc
        pipelineDescriptor.fragmentFunction = fragmentFunc
        pipelineDescriptor.colorAttachments[0].pixelFormat = self.pixelFormat
        
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.mipFilter = MTLSamplerMipFilter.notMipmapped
        samplerDescriptor.magFilter = MTLSamplerMinMagFilter.nearest
        samplerDescriptor.minFilter = MTLSamplerMinMagFilter.nearest
        samplerDescriptor.sAddressMode = MTLSamplerAddressMode.clampToZero
        samplerDescriptor.tAddressMode = MTLSamplerAddressMode.clampToZero
        samplerDescriptor.normalizedCoordinates = false
        
        let pipelineState = try? GPU.default.device.makeRenderPipelineState(
            descriptor: pipelineDescriptor
        )
        
        let samplerState = GPU.default.device.makeSamplerState(
            descriptor: samplerDescriptor
        )
        
        guard let pipelineState,
              let samplerState
        else { return }
        
        self.pipelineState = pipelineState
        self.samplerState = samplerState
        
        self.didEnterBakgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] _ in
            guard let self
            else { return }
            
            self.stopDisplayLink()
        }
        
        self.willEnterForegroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] _ in
            guard let self
            else { return }
            
            self.startDisplayLink()
        }
    }
    
    private func uniforms(_ timestamp: CFTimeInterval) -> [Uniforms] {
        let size = Float(self.pipView.contentView.bounds.size.width * self.scale)
        let midX: Float
        let midY: Float
        
        if let presentationLayer = self.pipView.contentView.layer.presentation() {
            midX = Float(presentationLayer.position.x * self.scale) - size * 0.5
            midY = Float(presentationLayer.position.y * self.scale) - size * 0.5
        } else {
            midX = Float(self.pipView.contentView.center.x * self.scale) - size * 0.5
            midY = Float(self.pipView.contentView.center.y * self.scale) - size * 0.5
        }
        let cornerRadius = size * 0.35
        let time = Float(timestamp)
        
        return [
            Uniforms(
                position: SIMD2<Float>(midX, midY),
                size: SIMD2<Float>(size, size),
                cornerRadius: cornerRadius,
                time: time
            )
        ]
    }
    
    private func redraw(_ displayLink: CADisplayLink) {
        guard let drawable = self.metalLayer.nextDrawable()
        else { return }
        
        let texture = drawable.texture
        
        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = texture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].storeAction = .store
        
        guard let pipelineState = self.pipelineState,
              let commandBuffer = GPU.default.commandQueue.makeCommandBuffer(),
              let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else { return }
        
        let verticies = self.verticies
        let uniforms = self.uniforms(displayLink.timestamp)
        
        commandEncoder.setRenderPipelineState(pipelineState)
        commandEncoder.setVertexBytes(
            verticies,
            length: MemoryLayout<Vertex>.stride * verticies.count,
            index: 0
        )
        commandEncoder.setFragmentBytes(
            uniforms,
            length: MemoryLayout<Uniforms>.stride * uniforms.count,
            index: 0
        )
        commandEncoder.setFragmentTexture(
            self.cameraTexture,
            index: 0
        )
        commandEncoder.setFragmentSamplerState(
            self.samplerState,
            index: 0
        )
        
        commandEncoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: 6
        )
        commandEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { [weak self, weak texture] _ in
            guard let self,
                  let texture
            else { return }
            
            self.onTextureFlush?(texture)
        }
        commandBuffer.commit()
    }
    
    private func startDisplayLink() {
        if let _ = self.displayLink {
            self.displayLink?.invalidate()
        }
        
        self.displayLink = CADisplayLink(
            target: self,
            selector: #selector(ReactionCanvasView.tick(_:))
        )
        self.displayLink?.add(to: RunLoop.main, forMode: RunLoop.Mode.common)
    }
    
    private func stopDisplayLink() {
        guard let _ = self.displayLink
        else { return }
        
        self.displayLink?.invalidate()
        self.displayLink = nil
    }
    
    @objc private func tick(_ displayLink: CADisplayLink) {
        self.redraw(displayLink)
    }
}

// MARK: - GPU uniforms

private struct Vertex {
    let position: SIMD4<Float>
}

private struct Uniforms {
    let position: SIMD2<Float>
    let size: SIMD2<Float>
    let cornerRadius: Float
    let time: Float
}
