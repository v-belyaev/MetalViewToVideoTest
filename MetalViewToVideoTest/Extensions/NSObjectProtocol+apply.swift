import Foundation

extension NSObjectProtocol {
    @inlinable
    public func apply(_ closure: (Self) -> Void) -> Self {
        closure(self)
        return self
    }
}
