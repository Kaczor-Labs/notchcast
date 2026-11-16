import Foundation

/// v1's all-or-nothing assertion handling: a half-acquired set is released before the error surfaces.
enum KeepAwakeAssertionPlan {
    static func acquire(
        types: [String], create: (String) throws -> UInt32, release: (UInt32) throws -> Void
    ) throws -> [UInt32] {
        var ids: [UInt32] = []
        do {
            for type in types { ids.append(try create(type)) }
            return ids
        } catch {
            let original = error
            try Self.release(ids, run: release)
            throw original
        }
    }

    /// Every release is attempted even when an earlier one fails; the first failure is rethrown.
    static func release(_ ids: [UInt32], run: (UInt32) throws -> Void) throws {
        let results = ids.map { id in Result { try run(id) } }
        for result in results { try result.get() }
    }
}
