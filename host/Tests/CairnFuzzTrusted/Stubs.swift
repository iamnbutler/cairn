import Foundation
final class InputClientSuite: Suite {
    let name = "inputclient"; let crashCheck = "text.input-client"; let checks: [String: CheckInfo] = [:]
    func cases(for n: Int) -> Int { 0 }
    func setUp() {}
    func run(_ g: inout SplitMix, _ r: Recorder) {}
    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String { "" }
}
final class MetricsSuite: Suite {
    let name = "metrics"; let crashCheck = "text.metrics"; let checks: [String: CheckInfo] = [:]
    func cases(for n: Int) -> Int { 0 }
    func setUp() {}
    func run(_ g: inout SplitMix, _ r: Recorder) {}
    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String { "" }
}
