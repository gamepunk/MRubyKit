import Testing
@testable import MRubyKit

// MARK: - VM 生命周期

@Test func testVMInitialization() async throws {
    let vm = try MRubyVM()
    #expect(vm.isGCEnabled)
}

@Test func testVMFullGC() async throws {
    let vm = try MRubyVM()
    vm.performGC()
    #expect(vm.liveObjectCount >= 0)
}

// MARK: - VM GC 控制

@Test func testGCSettings() async throws {
    let vm = try MRubyVM()
    let oldThreshold = vm.gcThreshold
    vm.gcThreshold = 500
    #expect(vm.gcThreshold == 500)
    vm.gcThreshold = oldThreshold
}

@Test func testVMRetainRelease() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let val = try ctx.eval("\"hello\"")
    vm.retain(val)
    vm.release(val)
    #expect(Bool(true))
}

// MARK: - 对象生命周期管理

@Test func testAddRemoveManagedReference() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()

    class OwnerClass {}
    let owner = OwnerClass()
    let val = try ctx.eval("\"managed\"")

    vm.addManagedReference(val, withOwner: owner)
    #expect(vm.managedReferences[ObjectIdentifier(owner)]?.count == 1)

    vm.removeManagedReference(val, withOwner: owner)
    #expect(vm.managedReferences[ObjectIdentifier(owner)] == nil)
}
