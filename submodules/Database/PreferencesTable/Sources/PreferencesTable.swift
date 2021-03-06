import Foundation
import ValueBox
import Table
import PostboxCoding

public enum PreferencesOperation {
    case update(ValueBoxKey, PreferencesEntry?)
}

private struct CachedEntry {
    let entry: PreferencesEntry?
}

public final class PreferencesTable: Table {
    private var cachedEntries: [ValueBoxKey: CachedEntry] = [:]
    private var updatedEntryKeys = Set<ValueBoxKey>()
    
    public static func tableSpec(_ id: Int32) -> ValueBoxTable {
        return ValueBoxTable(id: id, keyType: .binary, compactValuesOnCreation: false)
    }
    
    public func enumerateEntries(_ f: (PreferencesEntry) -> Bool) {
        self.valueBox.scan(self.table, values: { _, value in
            if let object = PostboxDecoder(buffer: value).decodeRootObject() as? PreferencesEntry {
                return f(object)
            } else {
                return true
            }
        })
    }
    
    public func get(key: ValueBoxKey) -> PreferencesEntry? {
        if let cached = self.cachedEntries[key] {
            return cached.entry
        } else {
            if let value = self.valueBox.get(self.table, key: key), let object = PostboxDecoder(buffer: value).decodeRootObject() as? PreferencesEntry {
                self.cachedEntries[key] = CachedEntry(entry: object)
                return object
            } else {
                self.cachedEntries[key] = CachedEntry(entry: nil)
                return nil
            }
        }
    }
    
    public func set(key: ValueBoxKey, value: PreferencesEntry?, operations: inout [PreferencesOperation]) {
        self.cachedEntries[key] = CachedEntry(entry: value)
        updatedEntryKeys.insert(key)
        operations.append(.update(key, value))
    }
    
    override public func clearMemoryCache() {
        assert(self.updatedEntryKeys.isEmpty)
    }
    
    override public func beforeCommit() {
        if !self.updatedEntryKeys.isEmpty {
            for key in self.updatedEntryKeys {
                if let value = self.cachedEntries[key]?.entry {
                    let encoder = PostboxEncoder()
                    encoder.encodeRootObject(value)
                    withExtendedLifetime(encoder, {
                        self.valueBox.set(self.table, key: key, value: encoder.readBufferNoCopy())
                    })
                } else {
                    self.valueBox.remove(self.table, key: key, secure: false)
                }
            }
            
            self.updatedEntryKeys.removeAll()
        }
    }
}
