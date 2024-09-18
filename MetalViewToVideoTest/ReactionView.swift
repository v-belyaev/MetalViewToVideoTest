import UIKit
import Metal
import AVFoundation

final class ReactionView: UIView {
    // MARK: - Lifecycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setup()
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Internal
    
    struct Context {
        var buttonTitle: String
        var onButtonTap: () -> Void
        var onTextureFlush: (MTLTexture) -> Void
    }
    
    var context: Context? {
        didSet {
            self.button.setTitle(self.context?.buttonTitle, for: .normal)
            self.canvasView.onTextureFlush = self.context?.onTextureFlush
        }
    }
    
    func enqueueCameraSample(_ sampleBuffer: CMSampleBuffer) {
        self.canvasView.enqueueCameraSample(sampleBuffer)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.canvasView.frame = self.bounds
        
        self.button.frame = CGRect(
            x: self.safeAreaLayoutGuide.layoutFrame.minX,
            y: self.safeAreaLayoutGuide.layoutFrame.maxY - 44,
            width: self.safeAreaLayoutGuide.layoutFrame.width,
            height: 44
        )
    }
    
    // MARK: - Private
    
    private let button: UIButton = .init(
        type: .system
    )
    
    private let canvasView: ReactionCanvasView = .init(
        frame: .zero
    )
    
    private func setup() {
        self.backgroundColor = UIColor.white
        self.addSubview(self.canvasView)
        self.addSubview(self.button)
        
        self.button.addTarget(
            self,
            action: #selector(ReactionView.onButtonTap(_:)),
            for: .touchUpInside
        )
    }
    
    @objc private func onButtonTap(_ sender: UIButton) {
        self.context?.onButtonTap()
    }
}
