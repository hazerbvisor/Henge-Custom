import Foundation

/// Compatibility at the GameController boundary only. The VM and touch controls use
/// canonical IDs: 0 = left, 1 = right, 2 = middle. Some physical setups are reported
/// to exchange left and middle in the guest; do not change the shared virtio mapping.
struct PhysicalMouseButtons {
    static let swapKey = "henge.mouse.swapLeftAndMiddle"
    // This fork targets the reported reversed-button setup. Other mice can opt out.
    static let defaultSwap = true

    // Fixed for a session so a preference change cannot remap a held button's release.
    let swapsLeftAndMiddle: Bool
    private(set) var held: Set<Int32> = []

    mutating func event(_ physicalButton: Int32, pressed: Bool) -> Int32? {
        guard (0...2).contains(physicalButton) else { return nil }
        let guestButton = swapsLeftAndMiddle && physicalButton != 1 ? 2 - physicalButton : physicalButton
        if pressed {
            held.insert(guestButton)
        } else {
            held.remove(guestButton)
        }
        return guestButton
    }

    /// Return canonical IDs, including swapped buttons, for disconnect/background cleanup.
    mutating func releaseAll() -> [Int32] {
        let releases = held.sorted()
        held.removeAll()
        return releases
    }
}
