import Foundation

runSchedulerTests()
runDiskStoreTests()
MainActor.assumeIsolated { runProviderTests() }

if failureCount > 0 {
    print("\(failureCount) failure(s)")
    exit(1)
}
print("all tests passed")
