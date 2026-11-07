import Foundation

@main
struct PhysicalMouseButtonTests {
    static func check(_ condition: Bool, _ message: String) {
        guard condition else { fatalError(message) }
    }

    static func main() {
        // A left-button drag must stay on the same guest button until release.
        var swapped = PhysicalMouseButtons(swapsLeftAndMiddle: true)
        check(swapped.event(0, pressed: true) == 2, "physical left must compensate with guest middle")
        check(swapped.held == [2], "drag must remain held between movement events")
        check(swapped.event(0, pressed: false) == 2, "release must match the swapped press")
        check(swapped.held.isEmpty, "drag release must not stick")
        check(swapped.event(2, pressed: true) == 0, "physical middle must compensate with guest left")
        check(swapped.event(1, pressed: true) == 1, "right-click must remain right-click")
        // Duplicate down notifications must not require extra up notifications.
        check(swapped.event(1, pressed: true) == 1, "repeat down must retain identity")
        check(swapped.releaseAll() == [0, 1], "disconnect/background must release mapped IDs")
        check(swapped.releaseAll().isEmpty, "cleanup must be idempotent")
        check(swapped.event(-1, pressed: true) == nil, "invalid button must be ignored")
        check(swapped.event(3, pressed: true) == nil, "unsupported button must be ignored")
        check(swapped.held.isEmpty, "invalid input must not leave held state")

        // A new session with compatibility off restores the standard VM contract.
        var standard = PhysicalMouseButtons(swapsLeftAndMiddle: false)
        for button in [Int32(0), 1, 2] {
            check(standard.event(button, pressed: true) == button, "opt-out must preserve canonical IDs")
            check(standard.event(button, pressed: false) == button, "opt-out release must match press")
        }
        check(standard.releaseAll().isEmpty, "opt-out must not leave held buttons")
        check(PhysicalMouseButtons.defaultSwap, "mouse-fix build must default to compensation")
        print("PASS: physical mouse mapping, drag pairing, right-click, opt-out and cleanup")
    }
}
