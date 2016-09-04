import Foundation

extension NSNumber {
    private static let trueNumber = NSNumber(value: true)
    private static let falseNumber = NSNumber(value: false)
    private static let trueObjCType = String(cString: NSNumber.trueNumber.objCType)
    private static let falseObjCType = String(cString: NSNumber.falseNumber.objCType)
    
    var isBool:Bool {
        get {
            let objCType = String(cString: self.objCType)
            if (self.compare(NSNumber.trueNumber) == .orderedSame && objCType == NSNumber.trueObjCType)
                || (self.compare(NSNumber.falseNumber) == ComparisonResult.orderedSame && objCType == NSNumber.falseObjCType){
                return true
            }
            return false
        }
    }
    var numberType: ModelParser.NumberType {
        if isBool {
            return .bool
        }
        let mappings: [String: ModelParser.NumberType] = ["b": .bool, "c": .bool, "i": .int, "l": .int, "q": .int, "f": .float, "d": .double]
        let objcType = String(validatingUTF8: self.objCType)?.lowercased()
        return objcType.flatMap { mappings[$0] } ?? .double
    }
}

protocol OptionalType {
    var isNil: Bool { get }
}

extension Optional: OptionalType {
    var isNil: Bool {
        if case .none = self {
            return true
        }
        return false
    }
}

extension NSNull: OptionalType {
    var isNil: Bool {
        return true
    }
}

public class ModelParser {
    
    public struct ObjectField {
        public let name: String
        public let type: FieldType
        
        init(name: String, type: FieldType) {
            self.name = name
            self.type = type
        }
    }
    public enum NumberType: String {
        case bool = "Bool"
        case int = "Int"
        case float = "Float"
        case double = "Double"
    }
    
    public indirect enum FieldType {
        case object(Set<ObjectField>)
        case list(FieldType)
        case text
        case number(NumberType)
        case `enum`(Set<FieldType>)
        case unknown
        case optional(FieldType)
    }
    
    public enum Error: Swift.Error {
        case unsupportedValueType(Any, Any.Type)
    }
    
    public init() {
        
    }
    
    public func decode(_ value: Any) throws -> FieldType {
        switch value {
        case is String:
            return .text
        case let number as NSNumber where value is Double: // Only on ios/osx we can bridge numbers to double and NSNumber
            return .number(number.numberType)
        case is Double:
            return .number(.double)
        case is Float:
            return .number(.float)
        case is Integer:
            return .number(.int)
        case is Bool:
            return .number(.bool)
        case let optional as OptionalType where optional.isNil:
            return .optional(.unknown)
        case let subObj as [String: Any]:
            return try decodeDict(subObj)
        case let subObj as [Any]:
            if let subType = try decodeList(subObj) {
                return .list(subType)
            } else {
                return .list(.unknown)
            }
        default:
            throw Error.unsupportedValueType(value, type(of: value))
        }
    }
    
    private func decodeDict(_ dict: [String: Any]) throws -> FieldType {
        let fields = try dict.map { (name: String, value: Any) in
            return ObjectField(name: name, type: try decode(value))
        }
        return .object(Set(fields))
    }
    
    private func decodeList(_ list: [Any]) throws -> FieldType? {
        let types = try list.flatMap { try decode($0)}
        return types.reduce(nil) { (type1, type2) -> FieldType? in
            if let type1 = type1 {
                return type1.mergeWith(type2)
            }
            return type2
        }
    }
    
    private class func transformAllFieldsToOptionalImpl(_ rootField: ModelParser.FieldType) -> ModelParser.FieldType {
        switch rootField {
        case let .object(fields):
            let mappedFields = fields.map {
                ModelParser.ObjectField(name: $0.name, type: transformAllFieldsToOptionalImpl($0.type))
            }
            return .optional(.object(Set(mappedFields)))
        case let .list(fieldType):
            return .optional(.list(transformAllFieldsToOptional(fieldType)))
        case .text:
            return .optional(.text)
        case let .number(numberType):
            return .optional(.number(numberType))
        case let .enum(fields):
            let mappedFields = fields.map {
                transformAllFieldsToOptional($0)
            }
            return .optional(.enum(Set(mappedFields)))
        case .unknown:
            return .optional(.unknown)
        case let .optional(fieldType):
            return .optional(transformAllFieldsToOptional(fieldType))
        }
    }
    
    public class func transformAllFieldsToOptional(_ rootField: ModelParser.FieldType) -> ModelParser.FieldType {
        switch rootField {
        case let .object(fields):
            let mappedFields = fields.map {
                ModelParser.ObjectField(name: $0.name, type: transformAllFieldsToOptionalImpl($0.type))
            }
            return .object(Set(mappedFields))
        case let .list(fieldType):
            return .list(transformAllFieldsToOptional(fieldType))
        case let .enum(fields):
            let mappedFields = fields.map { transformAllFieldsToOptional($0) }
            return .enum(Set(mappedFields))
        default:
            return rootField
        }
    }
    
}

extension ModelParser.ObjectField: Hashable {
    public var hashValue: Int {
        return (31 &* name.hashValue) &+ type.hashValue
    }
}
public func ==(lhs: ModelParser.ObjectField, rhs: ModelParser.ObjectField) -> Bool {
    return lhs.name == rhs.name && lhs.type == rhs.type
}

extension ModelParser.FieldType: Hashable {
    public var hashValue: Int {
        switch self {
        case .unknown:
            return 0
        case .text:
            return 31
        case let .optional(type):
            return 31 &+ type.hashValue
        case let .object(fields):
            return 31 &* 2 &+ fields.hashValue
        case let .list(type):
            return 31 &* 3 &+ type.hashValue
        case let .enum(types):
            return 31 &* 4 &+ types.hashValue
        case let .number(numberType):
            return 31 &* 5 &+ numberType.hashValue
        }
    }
}
public func ==(lhs: ModelParser.FieldType, rhs: ModelParser.FieldType) -> Bool {
    switch (lhs, rhs) {
    case let (.object(fields1), .object(fields2)):
        return fields1 == fields2
    case let (.list(type1), .list(type2)):
        return type1 == type2
    case (.text, .text):
        return true
    case let (.number(numberType1), .number(numberType2)):
        return numberType1 == numberType2
    case (.unknown, .unknown):
        return true
    case let (.optional(type1), .optional(type2)):
        return type1 == type2
    case let (.enum(types1), .enum(types2)):
        return types1 == types2
    default:
        return false
    }
}

extension ModelParser.NumberType {
    fileprivate func mergeWith(_ numberType: ModelParser.NumberType) -> ModelParser.NumberType? {
        switch (self, numberType) {
        case let (numberType1, numberType2) where numberType1 == numberType2: return numberType1
        case (.bool, _), (_, .bool): return nil
        case (.double, _), (_, .double): return .double
        case (.float, _), (_, .float): return .float
        default: return self // Can't be reached
        }
    }
}

extension ModelParser.FieldType {
    fileprivate func mergeWith(_ type: ModelParser.FieldType) -> ModelParser.FieldType {
        func mergeEnumTypes(_ enumTypes: Set<ModelParser.FieldType>, otherType: ModelParser.FieldType) -> Set<ModelParser.FieldType> {
            if enumTypes.contains(otherType) {
                return enumTypes
            }
            var merged = false
            let newEnumTypes: [ModelParser.FieldType] = enumTypes.map { enumType in
                switch (enumType, otherType) {
                case let (.optional(type1), type2), let (type2, .optional(type1)):
                    merged = true
                    if case let .optional(type2) = type2 {
                        return .optional(type1.mergeWith(type2))
                    } else {
                        return .optional(type1.mergeWith(type2))
                    }
                case let (.unknown, knownType), let (knownType, .unknown):
                    merged = true
                    return knownType
                case (.object, .object):
                    merged = true
                    return enumType.mergeWith(otherType)
                case let (.number(numberType1), .number(numberType2)) where numberType1.mergeWith(numberType2) != nil:
                    merged = true
                    let mergedNumberType = numberType1.mergeWith(numberType2)!
                    return .number(mergedNumberType)
                case let (.list(listType1), .list(listType2)):
                    merged = true
                    return .list(listType1.mergeWith(listType2))
                default:
                    return enumType
                }
            }
            return Set(newEnumTypes + (merged ? [] : [otherType]))
        }
        
        switch (self, type) {
        case let (type1, type2) where type1 == type2:
            return type1
        case let (.optional(type1), type2), let (type2, .optional(type1)):
            return .optional(type1.mergeWith(type2))
        case let (.unknown, knownType), let (knownType, .unknown):
            return knownType
        case let (.number(numberType1), .number(numberType2)) where numberType1.mergeWith(numberType2) != nil:
            let mergedNumberType = numberType1.mergeWith(numberType2)!
            return .number(mergedNumberType)
        case let (.object(fields1), .object(fields2)):
            var resultFields: Set<ModelParser.ObjectField> = []
            var remainingFields = fields2
            for f1 in fields1 {
                let foundItemIndex = remainingFields.index { f -> Bool in
                    return f1.name == f.name
                }
                let field: ModelParser.ObjectField
                if let foundItemIndex = foundItemIndex {
                    let foundItem = remainingFields.remove(at: foundItemIndex)
                    let mergedType = f1.type.mergeWith(foundItem.type)
                    field = ModelParser.ObjectField(name: f1.name, type: mergedType)
                } else if case .optional = f1.type {
                    field = f1
                } else {
                    field = ModelParser.ObjectField(name: f1.name, type: .optional(f1.type))
                }
                resultFields.insert(field)
            }
            for field in remainingFields {
                if case .optional = field.type {
                    resultFields.insert(field)
                } else {
                    resultFields.insert(ModelParser.ObjectField(name: field.name, type: .optional(field.type)))
                }
            }
            return .object(resultFields)
        case let (.list(listType1), .list(listType2)):
            return .list(listType1.mergeWith(listType2))
        case let (.enum(enumTypes), type), let (type, .enum(enumTypes)):
            return .enum(mergeEnumTypes(enumTypes, otherType: type))
        default:
            return .enum([self, type])
        }
    }
}


