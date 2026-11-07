import Foundation

@main
struct PhysicalMouseButtonTests {
    static func check(_ condition: Bool, _ message: String) {
        guard condition else { fatalError(message) }
    }

    static func main() {
        // A left-button drag must stay on the same guest button until release.
        var swapped = PhysicalMouseButtons(swapsRightAndMiddle: true)
        check(swapped.event(0, pressed: true) == 0, "physical left must remain left")
        check(swapped.held == [0], "drag must remain held between movement events")
        check(swapped.event(0, pressed: false) == 0, "left release must match its press")
        check(swapped.held.isEmpty, "drag release must not stick")
        check(swapped.event(1, pressed: true) == 2, "physical right must send guest middle")
        check(swapped.event(1, pressed: false) == 2, "right release must match its swapped press")
        check(swapped.held.isEmpty, "swapped right release must not stick")
        check(swapped.event(2, pressed: true) == 1, "physical middle must send guest right")
        check(swapped.event(2, pressed: false) == 1, "middle release must match its swapped press")
        check(swapped.held.isEmpty, "swapped middle release must not stick")
        check(swapped.event(1, pressed: true) == 2, "right hold must use guest middle")
        check(swapped.event(2, pressed: true) == 1, "middle hold must use guest right")
        // Duplicate down notifications must not require extra up notifications.
        check(swapped.event(1, pressed: true) == 2, "repeat down must retain identity")
        check(swapped.releaseAll() == [1, 2], "disconnect/background must release mapped IDs")
        check(swapped.releaseAll().isEmpty, "cleanup must be idempotent")
        check(swapped.event(-1, pressed: true) == nil, "invalid button must be ignored")
        check(swapped.event(3, pressed: true) == nil, "unsupported button must be ignored")
        check(swapped.held.isEmpty, "invalid input must not leave held state")

        // A new session with compatibility off restores the standard VM contract.
        var standard = PhysicalMouseButtons(swapsRightAndMiddle: false)
        for button in [Int32(0), 1, 2] {
            check(standard.event(button, pressed: true) == button, "opt-out must preserve canonical IDs")
            check(standard.event(button, pressed: false) == button, "opt-out release must match press")
        }
        check(standard.releaseAll().isEmpty, "opt-out must not leave held buttons")
        check(PhysicalMouseButtons.defaultSwap, "mouse-fix build must default to compensation")
        print("PASS: physical right/middle swap, unchanged left drag, paired releases, opt-out and cleanup")
    }
}
