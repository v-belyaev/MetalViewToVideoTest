import UIKit

final class ReactionPipView: UIView {
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
    
    let contentView: UIView = .init(
        frame: .zero
    ).apply {
        $0.backgroundColor = UIColor.clear
        $0.isUserInteractionEnabled = true
        $0.translatesAutoresizingMaskIntoConstraints = false
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        
        if view === self {
            return nil
        }
        
        return view
    }
    
    // MARK: - Private
    
    private let panGesture = UIPanGestureRecognizer()
    private let paddings: CGFloat = 16
    private let sizePercent: CGFloat = 0.3
    
    private var initialOffset: CGPoint = .zero
    private var pipPositionViews: [UIView] = []
    
    private var pipPositions: [CGPoint] {
        return self.pipPositionViews.map { $0.center }
    }
    
    private func pipPositionView() -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = UIColor.clear
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        
        self.addSubview(view)
        self.pipPositionViews.append(view)
        
        view.widthAnchor.constraint(
            equalTo: self.safeAreaLayoutGuide.widthAnchor,
            multiplier: self.sizePercent
        ).isActive = true
        view.heightAnchor.constraint(
            equalTo: self.safeAreaLayoutGuide.widthAnchor,
            multiplier: self.sizePercent
        ).isActive = true
        
        return view
    }
    
    private func setup() {
        self.backgroundColor = UIColor.clear
        
        let topLeadingView = self.pipPositionView()
        topLeadingView.topAnchor.constraint(
            equalTo: self.safeAreaLayoutGuide.topAnchor,
            constant: self.paddings
        ).isActive = true
        topLeadingView.leadingAnchor.constraint(
            equalTo: self.safeAreaLayoutGuide.leadingAnchor,
            constant: self.paddings
        ).isActive = true
        
        let topTrailingView = self.pipPositionView()
        topTrailingView.topAnchor.constraint(
            equalTo: self.safeAreaLayoutGuide.topAnchor,
            constant: self.paddings
        ).isActive = true
        topTrailingView.trailingAnchor.constraint(
            equalTo: self.safeAreaLayoutGuide.trailingAnchor,
            constant: -self.paddings
        ).isActive = true
        
        let bottomLeadingView = self.pipPositionView()
        bottomLeadingView.bottomAnchor.constraint(
            equalTo: self.safeAreaLayoutGuide.bottomAnchor,
            constant: -self.paddings
        ).isActive = true
        bottomLeadingView.leadingAnchor.constraint(
            equalTo: self.safeAreaLayoutGuide.leadingAnchor,
            constant: self.paddings
        ).isActive = true
        
        let bottomTrailingView = self.pipPositionView()
        bottomTrailingView.bottomAnchor.constraint(
            equalTo: self.safeAreaLayoutGuide.bottomAnchor,
            constant: -self.paddings
        ).isActive = true
        bottomTrailingView.trailingAnchor.constraint(
            equalTo: self.safeAreaLayoutGuide.trailingAnchor,
            constant: -self.paddings
        ).isActive = true
        
        self.addSubview(self.contentView)
        
        self.contentView.widthAnchor.constraint(
            equalTo: self.safeAreaLayoutGuide.widthAnchor,
            multiplier: self.sizePercent
        ).isActive = true
        self.contentView.heightAnchor.constraint(
            equalTo: self.safeAreaLayoutGuide.widthAnchor,
            multiplier: self.sizePercent
        ).isActive = true
        
        self.contentView.centerXAnchor.constraint(
            equalTo: topLeadingView.centerXAnchor
        ).isActive = true
        self.contentView.centerYAnchor.constraint(
            equalTo: topLeadingView.centerYAnchor
        ).isActive = true
        
        self.panGesture.addTarget(
            self,
            action: #selector(ReactionPipView.handleGesture(_:))
        )
        self.contentView.addGestureRecognizer(self.panGesture)
    }
    
    @objc private func handleGesture(_ sender: UIPanGestureRecognizer) {
        guard let pipView = sender.view
        else { return }
        
        let touchPoint = sender.location(in: self)
        
        switch sender.state {
        case .began:
            self.initialOffset = CGPoint(
                x: touchPoint.x - pipView.center.x,
                y: touchPoint.y - pipView.center.y
            )
        case .changed:
            pipView.center = CGPoint(
                x: touchPoint.x - self.initialOffset.x,
                y: touchPoint.y - self.initialOffset.y
            )
        case .ended, .cancelled:
            let decelerationRate = UIScrollView.DecelerationRate.fast.rawValue
            let velocity = sender.velocity(in: self)
            
            let projectedPosition = CGPoint(
                x: pipView.center.x + self.project(
                    initialVelocity: velocity.x,
                    decelerationRate: decelerationRate
                ),
                y: pipView.center.y + self.project(
                    initialVelocity: velocity.y,
                    decelerationRate: decelerationRate
                )
            )
            let nearestCornerPosition = self.nearestCorner(to: projectedPosition)
            
            let relativeInitialVelocity = CGVector(
                dx: self.relativeVelocity(
                    forVelocity: velocity.x,
                    from: pipView.center.x,
                    to: nearestCornerPosition.x
                ),
                dy: self.relativeVelocity(
                    forVelocity: velocity.y,
                    from: pipView.center.y,
                    to: nearestCornerPosition.y
                )
            )
            
            let timingParameters = UISpringTimingParameters(
                damping: 1,
                response: 0.4,
                initialVelocity: relativeInitialVelocity
            )
            
            let animator = UIViewPropertyAnimator(duration: 0, timingParameters: timingParameters)
            animator.addAnimations {
                pipView.center = nearestCornerPosition
            }
            animator.startAnimation()
        default:
            break
        }
    }
    
    private func project(
        initialVelocity: CGFloat,
        decelerationRate: CGFloat
    ) -> CGFloat {
        return (initialVelocity / 1000) * decelerationRate / (1 - decelerationRate)
    }
    
    private func nearestCorner(to point: CGPoint) -> CGPoint {
        var minDistance = CGFloat.greatestFiniteMagnitude
        var closestPosition = CGPoint.zero
        
        for position in self.pipPositions {
            let distance = point.distance(to: position)
            
            if distance < minDistance {
                closestPosition = position
                minDistance = distance
            }
        }
        return closestPosition
    }
    
    private func relativeVelocity(
        forVelocity velocity: CGFloat,
        from currentValue: CGFloat,
        to targetValue: CGFloat
    ) -> CGFloat {
        guard currentValue - targetValue != 0
        else { return 0 }
        
        return velocity / (targetValue - currentValue)
    }
}


// MARK: - CGPoint+

private extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat {
        return sqrt(pow(point.x - self.x, 2) + pow(point.y - self.y, 2))
    }
}

// MARK: - UISpringTimingParameters+

private extension UISpringTimingParameters {
    convenience init(damping: CGFloat, response: CGFloat, initialVelocity: CGVector = .zero) {
        let stiffness = pow(2 * .pi / response, 2)
        let damp = 4 * .pi * damping / response
        self.init(mass: 1, stiffness: stiffness, damping: damp, initialVelocity: initialVelocity)
    }
}
