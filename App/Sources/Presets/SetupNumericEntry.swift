/// Text precision is independent of the slider's coarse increments.
enum SetupNumericEntry {
    static func parse<Value: Numeric & LosslessStringConvertible>(_ text: String, integerOnly: Bool) -> Value? {
        guard !integerOnly || Int(text) != nil, let value = Value(text) else { return nil }
        guard (value as? Double)?.isFinite != false else { return nil }
        return value
    }

    static func formatted<Value: Numeric & LosslessStringConvertible>(_ value: Value) -> String {
        if let number = value as? Double, let integer = Int(exactly: number) {
            return String(integer)
        }
        return value.description
    }
}
