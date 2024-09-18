import UIKit
import AVFoundation

final class ReactionViewController: UIViewController {
    // MARK: - Lifeycle
    
    init() {
        super.init(nibName: nil, bundle: nil)
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Internal
    
    override func loadView() {
        self.view = self.mainView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let url = URL.temporaryDirectory.appending(path: "test.mp4")
        let size = UIScreen.main.bounds.size
        let scale = UIScreen.main.scale
        
        self.recorder = try? ReactionRecorder(
            url: url,
            size: size,
            scale: scale
        )
        
        self.sampleProvider = ReactionSampleProvider()
        
        self.mainView.context = ReactionView.Context(
            buttonTitle: "Start",
            onButtonTap: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, let recorder
                    else { return }
                    
                    if await recorder.isRecording {
                        try await recorder.finish()
                        self.mainView.context?.buttonTitle = "Start"
                        
                        let controller = UIActivityViewController(
                            activityItems: [url],
                            applicationActivities: nil
                        )
                        controller.completionWithItemsHandler = { (
                            activityType: UIActivity.ActivityType?,
                            completed: Bool,
                            returnedItems: [Any]?,
                            activityError: (any Error)?
                        ) in
                            if let activityError {
                                print(activityError.localizedDescription)
                            }
                        }
                        
                        self.recorder = try ReactionRecorder(
                            url: url,
                            size: size,
                            scale: scale
                        )
                        self.present(controller, animated: true)
                    } else {
                        try await recorder.start()
                        self.mainView.context?.buttonTitle = "Stop"
                    }
                }
            },
            onTextureFlush: { [weak self] texture in
                Task { @MainActor [weak self, weak texture] in
                    guard let self, let texture
                    else { return }
                    
                    try await self.recorder?.processFrame(for: texture)
                }
            }
        )
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        Task { @MainActor in
            guard let sampleProvider else {
                return
            }
            
            await sampleProvider.appendConnection(self)
            await sampleProvider.configureSession(
                withVideo: true,
                withAudio: true
            )
        }
    }
    
    // MARK: - Private
    
    private lazy var mainView: ReactionView = .init(
        frame: .zero
    )
    
    private var recorder: ReactionRecorder?
    private var sampleProvider: ReactionSampleProvider?
}

// MARK: - ReactionSampleProvider.Connection

extension ReactionViewController: ReactionSampleProvider.Connection {
    func onAudioSampleReady(_ sampleBuffer: CMSampleBuffer) {
        Task {
            do {
                try await self.recorder?.processAudioSample(sampleBuffer)
            } catch {
                print(error.localizedDescription)
            }
        }
    }
    
    func onVideoSampleReady(_ sampleBuffer: CMSampleBuffer) {
        self.mainView.enqueueCameraSample(sampleBuffer)
    }
}
