import Foundation
import AVFoundation

final class ReactionSampleProvider: NSObject {
    // MARK: - Lifecycle
    
    override init() {
        self.queue = DispatchQueue(
            label: "ReactionSampleProvider.serial",
            qos: .userInitiated
        )
        self.delegateQueue = DispatchQueue(
            label: "ReactionSampleProvider.delegate.serial",
            qos: .userInitiated
        )
        self.session = AVCaptureSession()
        
        super.init()
    }
    
    deinit {
        self.videoDataOutput?.setSampleBufferDelegate(nil, queue: nil)
        self.audioDataOutput?.setSampleBufferDelegate(nil, queue: nil)
    }
    
    // MARK: - Internal
    
    protocol Connection: AnyObject {
        func onAudioSampleReady(_ sampleBuffer: CMSampleBuffer)
        func onVideoSampleReady(_ sampleBuffer: CMSampleBuffer)
    }
    
    func configureSession(withVideo: Bool, withAudio: Bool) async {
        await withUnsafeContinuation { continuation in
            self.queue.async {
                self.reset()
                continuation.resume()
            }
        }
        
        var types: [AVMediaType] = []
        
        if withVideo {
            types.append(.video)
        }
        
        if withAudio {
            types.append(.audio)
        }
        
        await self.requestPermissionIfNeeded(for: types)
        
        await withUnsafeContinuation { continuation in
            self.queue.async {
                self.configureSession()
                continuation.resume()
            }
        }
    }
    
    public func appendConnection(_ connection: Connection) async {
        await withUnsafeContinuation { continuation in
            self.queue.async {
                self.connections.append(WeakConnection(connection: connection))
                continuation.resume()
            }
        }
    }
    
    public func removeConnections() async {
        await withUnsafeContinuation { continuation in
            self.queue.async {
                self.connections.removeAll()
                continuation.resume()
            }
        }
    }
    
    // MARK: - Private
    
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
        case unused
    }
    
    private struct WeakConnection {
        weak var connection: Connection?
        
        init(connection: Connection?) {
            self.connection = connection
        }
    }
    
    private let queue: DispatchQueue
    private let delegateQueue: DispatchQueue
    private let session: AVCaptureSession
    
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private var audioDataOutput: AVCaptureAudioDataOutput?
    private var videoSetupResult: SessionSetupResult = .unused
    private var audioSetupResult: SessionSetupResult = .unused
    
    private var connections: [WeakConnection] = []
    
    private func requestPermissionIfNeeded(for types: [AVMediaType]) async {
        @inline(__always)
        func requestPermission(for mediaType: AVMediaType) async -> SessionSetupResult {
            let status = AVCaptureDevice.authorizationStatus(for: mediaType)
            
            switch status {
            case .authorized:
                return .success
            
            case .notDetermined:
                let result: SessionSetupResult
                
                self.queue.suspend()
                
                if await AVCaptureDevice.requestAccess(for: mediaType) {
                    result = .success
                } else {
                    result = .notAuthorized
                }
                
                self.queue.resume()
                
                return result
                
            default:
                return .notAuthorized
            }
        }
        
        for type in types {
            let result = await requestPermission(for: type)
            
            switch type {
            case .video:
                self.videoSetupResult = result
            case .audio:
                self.audioSetupResult = result
            default:
                continue
            }
        }
    }
    
    private func configureSession() {
        let videoDevice = self.videoSetupResult == .success
        ? AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                AVCaptureDevice.DeviceType.builtInWideAngleCamera,
                AVCaptureDevice.DeviceType.builtInUltraWideCamera,
                AVCaptureDevice.DeviceType.builtInTelephotoCamera,
                AVCaptureDevice.DeviceType.builtInDualCamera,
                AVCaptureDevice.DeviceType.builtInDualWideCamera,
                AVCaptureDevice.DeviceType.builtInTripleCamera
            ],
            mediaType: .video,
            position: .front
        ).devices.first
        : nil
        
        let audioDevice = self.audioSetupResult == .success
        ? AVCaptureDevice.default(for: .audio)
        : nil
        
        guard videoDevice != nil || audioDevice != nil
        else { return }
        
        self.session.beginConfiguration()
        
        if let videoDevice,
           let input = try? AVCaptureDeviceInput(device: videoDevice),
           self.session.canAddInput(input)
        {
            self.session.addInput(input)
            self.videoInput = input
        }
        
        if let audioDevice,
           let input = try? AVCaptureDeviceInput(device: audioDevice),
           self.session.canAddInput(input)
        {
            self.session.addInput(input)
            self.audioInput = input
        }
        
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [
          kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ] as [String : Any]
        
        let audioDataOutput = AVCaptureAudioDataOutput()
        
        if self.session.canAddOutput(videoDataOutput) {
            self.session.addOutput(videoDataOutput)
        }
        
        if self.session.canAddOutput(audioDataOutput) {
            self.session.addOutput(audioDataOutput)
        }
        
        self.session.sessionPreset = .high
        
        if let connection = videoDataOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }
        
        videoDataOutput.setSampleBufferDelegate(self, queue: self.delegateQueue)
        audioDataOutput.setSampleBufferDelegate(self, queue: self.delegateQueue)
        
        self.videoDataOutput = videoDataOutput
        self.audioDataOutput = audioDataOutput
        
        self.session.commitConfiguration()
        self.session.startRunning()
    }
    
    private func reset() {
        self.videoSetupResult = .unused
        self.audioSetupResult = .unused
        
        if self.session.isRunning {
            self.session.stopRunning()
        }
        
        self.session.beginConfiguration()
        
        self.session.inputs.forEach {
            self.session.removeInput($0)
        }
        
        self.session.outputs.forEach {
            self.session.removeOutput($0)
        }
        
        self.videoInput = nil
        self.audioInput = nil
        
        self.videoDataOutput = nil
        self.audioDataOutput = nil
        
        self.session.commitConfiguration()
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate + AVCaptureAudioDataOutputSampleBufferDelegate

extension ReactionSampleProvider: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard CMSampleBufferDataIsReady(sampleBuffer)
        else { return }
        
        self.connections.forEach {
            if output == self.videoDataOutput {
                $0.connection?.onVideoSampleReady(sampleBuffer)
            } else if output == self.audioDataOutput {
                $0.connection?.onAudioSampleReady(sampleBuffer)
            }
        }
    }
}
