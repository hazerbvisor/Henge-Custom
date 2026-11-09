import Foundation

enum HengeLog { static func log(_ category: String, _ message: String) {} }

@main struct TuningTests {
    static func main() {
        let d = UserDefaults.standard
        let old = d.object(forKey: EngineTuning.statsKey)
        defer {
            if let old { d.set(old, forKey: EngineTuning.statsKey) }
            else { d.removeObject(forKey: EngineTuning.statsKey) }
        }
        let overrideFile = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("henge-env.txt")
        precondition(!FileManager.default.fileExists(atPath: overrideFile.path), "Test needs no environment override file")
        d.removeObject(forKey: EngineTuning.statsKey)
        EngineTuning.apply()
        precondition(String(cString: getenv("HV_STATS")) == "0", "Default must disable detailed statistics")
        d.set(true, forKey: EngineTuning.statsKey)
        EngineTuning.apply()
        precondition(String(cString: getenv("HV_STATS")) == "10", "Diagnostic opt-in must work")
        d.set(false, forKey: EngineTuning.statsKey)
        EngineTuning.apply()
        precondition(String(cString: getenv("HV_STATS")) == "0", "Turning diagnostics off must clear prior value")
        print("PASS: default-off engine stats, opt-in and disabling again")
    }
}
