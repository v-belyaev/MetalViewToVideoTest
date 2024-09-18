import Metal

final class GPU {
    // MARK: - Lifecycle
    
    init(commandQueue: MTLCommandQueue) {
        self.commandQueue = commandQueue
    }
    
    convenience init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue()
        else { return nil }
        
        self.init(commandQueue: commandQueue)
    }
    
    // MARK: - Internal
    
    static let `default` = GPU()!
    
    let commandQueue: MTLCommandQueue
    
    var device: MTLDevice {
        return self.commandQueue.device
    }
}
