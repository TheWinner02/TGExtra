import Foundation

@main
struct ScheduleTimingTests {
    static func main() {
        typealias Timing = AutomaticScheduleTiming
        let mb: Int64 = 1_048_576
        let cases: [(Timing.Kind, Int, Int64, Int64)] = [
            (.text, 0, 0, 15), (.text, 199, 0, 15),
            (.text, 200, 0, 16), (.text, 1_000, 0, 20),
            (.text, 4_000, 0, 35), (.text, 50_000, 0, 60),
            (.photo, 0, 0, 30), (.photo, 0, 5 * mb, 35),
            (.photo, 0, 1, 31), (.photo, 0, 1_000 * mb, 300),
            (.video, 0, 20 * mb, 105), (.video, 0, 5 * mb, 60),
            (.video, 0, 1_000 * mb, 1_800),
            (.audio, 0, 2 * mb, 34), (.audio, 0, 8 * mb, 46),
            (.file, 0, 10 * mb, 50), (.file, 0, Int64.max, 1_800),
            (.lightweight, 4_000, 10 * mb, 15),
            (.text, -200, 0, 15), (.photo, 0, -1, 30)
        ]
        for (kind, text, size, expected) in cases {
            let actual = Timing.delay(kind: kind, textLength: text, size: size)
            precondition(actual == expected, "\(kind): got \(actual), expected \(expected)")
        }
        print("Schedule timing: \(cases.count) tests passed")
    }
}
