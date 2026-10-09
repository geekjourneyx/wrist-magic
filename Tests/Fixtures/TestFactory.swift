import WristMagicCore
/// Shared fixture compiled into both platform smoke-test bundles.
enum TestFactory {
    static var expectedProtocolVersion: Int { 1 }
    static var linkedProtocolVersion: Int { CoreBaseline.protocolVersion }
}
