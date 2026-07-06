import Testing
@testable import MRubyKit

// MARK: - MRubyManagedValue

@Test func testManagedValueBasic() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let val = try ctx.eval("\"hello\"")
    let managed = MRubyManagedValue(value: val)
    #expect(managed.rubyValue.toString() == "hello")
    #expect(managed.value.toString() == "hello")  // JSC 兼容别名
    #expect(managed.virtualMachine === vm)
}

@Test func testManagedValueWithOwner() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()

    class Owner {}
    let owner = Owner()
    let val = try ctx.eval("\"world\"")
    let managed = MRubyManagedValue(value: val, owner: owner)
    #expect(managed.rubyValue.toString() == "world")

    managed.dispose()
    #expect(managed.rubyValue.toString() == "world")
}

@Test func testManagedValueValueAlias() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()
    let val = try ctx.eval("\"world\"")
    let managed = MRubyManagedValue(value: val, owner: ctx)
    #expect(managed.value.toString() == managed.rubyValue.toString())
}

@Test func testManagedValueWithOwnerUsesAddManagedReference() async throws {
    let vm = try MRubyVM()
    let ctx = vm.makeContext()

    class OwnerClass {}
    let owner = OwnerClass()
    let val = try ctx.eval("\"owner-test\"")
    let managed = MRubyManagedValue(value: val, owner: owner)

    let key = ObjectIdentifier(owner)
    #expect(vm.managedReferences[key]?.count == 1)

    managed.dispose()
    #expect(vm.managedReferences[key] == nil)
}
