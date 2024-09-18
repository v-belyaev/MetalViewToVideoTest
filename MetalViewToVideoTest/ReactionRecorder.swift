import os
import Metal
import CoreVideo
import ReplayKit
import Foundation
import AVFoundation

final class ReactionRecorder {
    // MARK: - Lifecycle
    
    init(url: URL, size: CGSize, scale: CGFloat) throws {
        self.writer = try AVAssetWriter(
            outputURL: url,
            fileType: .mp4
        )
        
        let videoWidth = size.width * scale
        let videoHeight = size.height * scale
        
        let sampleRate = AVAudioSession.sharedInstance().sampleRate
        
        // videoInput
        do {
            let compressionProperties: [String: Any] = [
                AVVideoExpectedSourceFrameRateKey: NSNumber(value: 60),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
            
            let outputSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: NSNumber(value: videoWidth.native),
                AVVideoHeightKey: NSNumber(value: videoHeight.native),
                AVVideoCompressionPropertiesKey: compressionProperties
            ]
            
            let input = AVAssetWriterInput(
                mediaType: AVMediaType.video,
                outputSettings: outputSettings
            )
            input.expectsMediaDataInRealTime = true
            
            self.videoInput = input
        }
        
        // audioInput
        do {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: sampleRate
            ]
            let input: AVAssetWriterInput = .init(
                mediaType: .audio,
                outputSettings: audioSettings
            )
            input.expectsMediaDataInRealTime = true
            
            self.audioInput = input
        }
        
        // pixelBufferAdaptor
        do {
            let sourcePixelBufferAttributes: [String: Any] = [
                (kCVPixelBufferWidthKey as String): NSNumber(value: videoWidth.native),
                (kCVPixelBufferHeightKey as String): NSNumber(value: videoHeight.native),
                (kCVPixelBufferPixelFormatTypeKey as String): kCVPixelFormatType_32BGRA,
            ]
            
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: self.videoInput,
                sourcePixelBufferAttributes: sourcePixelBufferAttributes
            )
            
            self.pixelBufferAdaptor = adaptor
        }
        
        self.queue = DispatchQueue(
            label: "MetalVideoRecorder.serial",
            qos: .userInitiated
        )
    }
    
    // MARK: - Internal
    
    var isRecording: Bool {
        get async {
            await withUnsafeContinuation { continuation in
                self.queue.async { [isProcessing] in
                    continuation.resume(returning: isProcessing)
                }
            }
        }
    }
    
    func start() async throws {
        try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Void, any Swift.Error>) in
            self.start { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    func start(completion: @escaping (ReactionRecorder.Error?) -> Void) {
        self.queue.async { [weak self] in
            guard let self else {
                completion(ReactionRecorder.Error.deallocated)
                return
            }
            
            let status = self.writer.status
            
            guard status == .unknown else {
                completion(ReactionRecorder.Error.wrongAssetWriterStatus(status))
                return
            }
            
            if let error = self.writer.error {
                completion(ReactionRecorder.Error.system(error))
                return
            }
            
            self.inputs.lazy
                .filter({ self.writer.canAdd($0) })
                .forEach({ self.writer.add($0) })
            
            if let error = self.writer.error {
                completion(ReactionRecorder.Error.system(error))
                return
            }
            
            let url = self.writer.outputURL
            let path = url.path(percentEncoded: false)
            
            if FileManager.default.fileExists(atPath: path) {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    completion(ReactionRecorder.Error.system(error))
                    return
                }
            }
            
            self.writer.startWriting()
            self.isProcessing = true
            
            completion(nil)
        }
    }
    
    func finish() async throws {
        try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Void, any Swift.Error>) in
            self.finish { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    func finish(completion: @escaping (ReactionRecorder.Error?) -> Void) {
        self.queue.async { [weak self] in
            guard let self else {
                completion(ReactionRecorder.Error.deallocated)
                return
            }
            
            let group = DispatchGroup()
            
            self.inputs.lazy
                .filter({ $0.isReadyForMoreMediaData })
                .forEach({ $0.markAsFinished() })
            
            let status = self.writer.status
            
            guard status == .writing else {
                completion(ReactionRecorder.Error.wrongAssetWriterStatus(status))
                return
            }
            
            group.enter()
            
            var error: ReactionRecorder.Error?
            self.writer.finishWriting { [weak self] in
                defer {
                    group.leave()
                }
                
                guard let self else {
                    error = ReactionRecorder.Error.deallocated
                    return
                }
                
                if let e = self.writer.error {
                    error = ReactionRecorder.Error.system(e)
                    return
                }
                
                let status = self.writer.status
                
                guard status == .completed else {
                    error = ReactionRecorder.Error.wrongAssetWriterStatus(status)
                    return
                }
            }
            
            group.wait()
            
            if let error {
                completion(ReactionRecorder.Error.system(error))
                return
            }
            
            self.isProcessing = false
            completion(nil)
        }
    }
    
    func processFrame(for texture: MTLTexture) async throws {
        try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Void, any Swift.Error>) in
            self.processFrame(for: texture) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    func processFrame(
        for texture: MTLTexture,
        completion: @escaping (ReactionRecorder.Error?) -> Void
    ) {
        self.queue.async { [weak self] in
            guard let self else {
                completion(ReactionRecorder.Error.deallocated)
                return
            }
            
            let isWriting = self.writer.status == .writing
            let isReadyForMoreMediaData = self.videoInput.isReadyForMoreMediaData
            
            guard isWriting, isReadyForMoreMediaData else {
                completion(nil)
                return
            }
            
            guard let pixelBufferPool = self.pixelBufferAdaptor.pixelBufferPool else {
                completion(ReactionRecorder.Error.pixelBufferAvailableProblem)
                return
            }
            
            var pixelBuffer: CVPixelBuffer?
            
            let status = CVPixelBufferPoolCreatePixelBuffer(
                kCFAllocatorDefault,
                pixelBufferPool,
                &pixelBuffer
            )
            
            guard status == kCVReturnSuccess, let pixelBuffer = pixelBuffer else {
                completion(ReactionRecorder.Error.pixelBufferAvailableProblem)
                return
            }
            
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            
            let pixelBufferBytes = CVPixelBufferGetBaseAddress(pixelBuffer)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let region = MTLRegionMake2D(0, 0, texture.width, texture.height)
            
            guard let pixelBufferBytes = pixelBufferBytes else {
                completion(ReactionRecorder.Error.pixelBufferAvailableProblem)
                return
            }
            
            texture.getBytes(
                pixelBufferBytes,
                bytesPerRow: bytesPerRow,
                from: region,
                mipmapLevel: 0
            )
            
            let frameTime = CACurrentMediaTime() - self.recordingStartTime
            let presentationTime = CMTimeMakeWithSeconds(frameTime, preferredTimescale: 1000)
            
            self.startSessionIfNeeded(with: presentationTime)
            self.pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)
            
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            completion(nil)
        }
    }
    
    func processAudioSample(_ sampleBuffer: CMSampleBuffer) async throws {
        try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Void, any Swift.Error>) in
            self.processAudioSample(sampleBuffer) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    func processAudioSample(
        _ sampleBuffer: CMSampleBuffer,
        completion: @escaping (ReactionRecorder.Error?) -> Void
    ) {
        self.queue.async { [weak self] in
            guard let self else {
                completion(ReactionRecorder.Error.deallocated)
                return
            }
            
            let isWriting = self.writer.status == .writing
            let isReadyForMoreMediaData = self.audioInput.isReadyForMoreMediaData
            
            guard isWriting, isReadyForMoreMediaData, self.isSessionStarted else {
                completion(nil)
                return
            }
            
            self.audioInput.append(sampleBuffer)
            
            completion(nil)
        }
    }
    
    // MARK: - Private
    
    private let queue: DispatchQueue
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput
    private let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor
    
    private var isProcessing: Bool = false
    private var isSessionStarted: Bool = false
    private var recordingStartTime: TimeInterval = 0
    
    private var inputs: [AVAssetWriterInput] {
        return [
            self.videoInput,
            self.audioInput
        ]
    }
    
    private func startSessionIfNeeded(with sourceTime: CMTime) {
        guard self.isSessionStarted == false
        else { return }
        
        self.isSessionStarted = true
        self.writer.startSession(atSourceTime: sourceTime)
    }
}

// MARK: - Error

extension ReactionRecorder {
    enum Error: Swift.Error {
        case wrongAssetWriterStatus(AVAssetWriter.Status)
        case system(Swift.Error)
        case pixelBufferAvailableProblem
        case deallocated
    }
}
