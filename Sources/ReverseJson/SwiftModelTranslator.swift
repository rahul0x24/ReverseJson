

public struct SwiftTranslator: ModelTranslator {
    
    private let translators: [ModelTranslator]
    
    public init(args: [String] = []) {
        translators = [
            SwiftModelCreator(args: args),
            SwiftJsonParsingTranslator(args: args)
        ]
    }
    public func translate(_ type: ModelParser.FieldType, name: String) -> String {
        return String(joined: translators.lazy.map { $0.translate(type, name: name) }, separator: "\n\n")
    }
}

private enum ObjectType: String {
    case structType = "struct"
    case classType = "class"
}
extension ObjectType {
    var name: String {
        return self.rawValue
    }
}
private enum ListType: String {
    case array = "Array"
    case contiguousArray = "ContiguousArray"
}

private enum Visibility: String {
    case internalVisibility = "internal"
    case publicVisibility = "public"
}

extension Visibility {
    var visibilityPrefix: String {
        return self == .internalVisibility ? "" : "\(self.rawValue) "
    }
}

struct SwiftModelCreator: ModelTranslator {
    
    private let objectType: ObjectType
    private let listType: ListType
    private let fieldVisibility: Visibility
    private let typeVisibility: Visibility
    private let mutableFields: Bool
    
    init(args: [String] = []) {
        self.objectType = args.contains("-c") || args.contains("--class") ? .classType : .structType
        self.listType = args.contains("-ca") || args.contains("--contiguousarray") ? .contiguousArray : .array
        self.mutableFields = args.contains("-m") || args.contains("--mutable")
        self.fieldVisibility = args.contains("-pf") || args.contains("--publicfields") ? .publicVisibility : .internalVisibility
        self.typeVisibility = args.contains("-pt") || args.contains("--publictypes") ? .publicVisibility : .internalVisibility
    }
    
    func translate(_ type: ModelParser.FieldType, name: String) -> String {
        let (typeName, decl) = makeSubtype(type, name: "", subName: name, level: 0)
        if let decl = decl {
            return decl
        }
        return "\(typeVisibility.visibilityPrefix)typealias \(name) = \(typeName)"
    }
    
    private func makeSubtype(_ type: ModelParser.FieldType, name: String, subName: String, level: Int) -> (name: String, declaration: String?) {
        let fieldType: String
        let declaration: String?
        switch type {
        case let .object(fields):
            fieldType = subName.camelCasedString
            declaration = createStructDeclaration(fieldType, fields: fields, level: level)
        case let .number(numberType):
            fieldType = numberType.rawValue
            declaration = nil
        case .text:
            fieldType = "String"
            declaration = nil
        case let .list(listItemType):
            let newSubName: String
            if case .list = listItemType {
                newSubName = subName
            } else {
                newSubName = "\(subName)Item"
            }
            let (subTypeName, subDeclaration) = makeSubtype(listItemType, name: "\(name)\(subName.camelCasedString)", subName: newSubName, level: level)
            declaration = subDeclaration
            switch listType {
            case .array: fieldType = "[\(subTypeName)]"
            case .contiguousArray: fieldType = "\(listType.className)<\(subTypeName)>"
            }
        case let .enum(enumTypes):
            fieldType = subName.camelCasedString
            declaration = createEnumDeclaration(fieldType, cases: enumTypes, level: level)
        case let .optional(type):
            let (subTypeName, subDeclaration) = makeSubtype(type, name: name, subName: subName, level: level)
            declaration = subDeclaration
            fieldType = "\(subTypeName)?"
        case .unknown:
            fieldType = subName.camelCasedString
            declaration = "\(typeVisibility.visibilityPrefix)typealias \(fieldType) = Void // TODO Specify type here. We couldn't infer it from json".indent(level)
        }
        return (fieldType, declaration)
    }
    
    private func createStructDeclaration(_ name: String, fields: Set<ModelParser.ObjectField>, level: Int = 0) -> String {
        var ret = "\(typeVisibility.visibilityPrefix)\(objectType.name) \(name) {".indent(level)
        let fieldsAndTypes = fields.sorted{$0.0.name < $0.1.name}.map { f -> (field: String, type: String?) in
            var fieldDeclaration = ""
            let (typeName, subTypeDeclaration) = makeSubtype(f.type, name: name, subName: f.name, level: level + 1)
            let varModifier = mutableFields ? "var" : "let"
            fieldDeclaration += ("\(fieldVisibility.visibilityPrefix)\(varModifier) \(f.name.pascalCased().asValidSwiftIdentifier.swiftKeywordEscaped): \(typeName)")
            return (fieldDeclaration, subTypeDeclaration)
        }
        let typeDeclarations = fieldsAndTypes.lazy.flatMap {$0.type}
        ret += String(joined: Set(typeDeclarations.map({ "\n\($0)"})).sorted(by: <), separator: "")
        let fields = fieldsAndTypes.lazy.map { $0.field }.map { $0.indent(level + 1) }.map { "\n\($0)" }
        ret += String(joined: fields.sorted(by: <), separator: "")
        return ret + "\n" + "}".indent(level)
    }
    
    private func createEnumDeclaration(_ name: String, cases: Set<ModelParser.FieldType>, level: Int = 0) -> String {
        var ret = "\(typeVisibility.visibilityPrefix)enum \(name) {".indent(level)
        ret += String(joined: cases.sorted{$0.0.enumCaseName < $0.1.enumCaseName}.map { c -> String in
            var fieldDeclaration = ""
            let (typeName, subTypeDeclaration) = makeSubtype(c, name: name, subName: "\(name)\(c.enumCaseName.firstCapitalized())", level: level + 1)
            if let subTypeDeclaration = subTypeDeclaration {
                fieldDeclaration += subTypeDeclaration + "\n"
            }
            fieldDeclaration += "case \(c.enumCaseName)(\(typeName))".indent(level + 1)
            return fieldDeclaration
        }.map {"\n\($0)"}, separator: "")
        return ret + "\n" + "}".indent(level)
    }

}

private struct Declaration: Hashable {
    let text: String
    let priority: Int
    init(text: String, priority: Int = 100) {
        self.text = text
        self.priority = priority
    }
    var hashValue: Int {
        return text.hashValue
    }
}
private func ==(lhs: Declaration, rhs: Declaration) -> Bool {
    return lhs.text == rhs.text
}

let swiftErrorType = String(lines:
    "enum JsonParsingError: Error {",
    "    case unsupportedTypeError",
    "}"
)

let swiftStringParser = String(lines:
    "extension String {",
    "    init(jsonValue: Any?) throws {",
    "        guard let string = jsonValue as? String else {",
    "            throw JsonParsingError.unsupportedTypeError",
    "        }",
    "        self = string",
    "    }",
    "}"
)

let swiftIntParser = String(lines:
    "extension Int {",
    "    init(jsonValue: Any?) throws {",
    "        if let number = jsonValue as? NSNumber {",
    "            self = number.intValue",
    "        } else if let number = jsonValue as? Int {",
    "            self = number",
    "        } else if let number = jsonValue as? Double {",
    "            self = Int(number)",
    "        } else if let number = jsonValue as? Float {",
    "            self = Int(number)",
    "        } else {",
    "            throw JsonParsingError.unsupportedTypeError",
    "        }",
    "    }",
    "}"
)

let swiftFloatParser = String(lines:
    "extension Float {",
    "    init(jsonValue: Any?) throws {",
    "        if let number = jsonValue as? NSNumber {",
    "            self = number.floatValue",
    "        } else if let number = jsonValue as? Int {",
    "            self = Float(number)",
    "        } else if let number = jsonValue as? Double {",
    "            self = Float(number)",
    "        } else if let number = jsonValue as? Float {",
    "            self = number",
    "        } else {",
    "            throw JsonParsingError.unsupportedTypeError",
    "        }",
    "    }",
    "}"
)

let swiftDoubleParser = String(lines:
    "extension Double {",
    "    init(jsonValue: Any?) throws {",
    "        if let number = jsonValue as? NSNumber {",
    "            self = number.doubleValue",
    "        } else if let number = jsonValue as? Int {",
    "            self = Double(number)",
    "        } else if let number = jsonValue as? Double {",
    "            self = number",
    "        } else if let number = jsonValue as? Float {",
    "            self = Double(number)",
    "        } else {",
    "            throw JsonParsingError.unsupportedTypeError",
    "        }",
    "    }",
    "}"
)

let swiftBoolParser = String(lines:
    "extension Bool {",
    "    init(jsonValue: Any?) throws {",
    "        if let number = jsonValue as? NSNumber {",
    "            guard String(cString: number.objCType) == String(cString: NSNumber(value: true).objCType) else {",
    "                throw JsonParsingError.unsupportedTypeError",
    "            }",
    "            self = number.boolValue",
    "        } else if let number = jsonValue as? Bool {",
    "            self = number",
    "        } else {",
    "            throw JsonParsingError.unsupportedTypeError",
    "        }",
    "    }",
    "}"
)

let swiftOptionalParser = String(lines:
    "extension Optional {",
    "    init(jsonValue: Any?, map: (Any) throws -> Wrapped) throws {",
    "        if let jsonValue = jsonValue, !(jsonValue is NSNull) {",
    "            self = try map(jsonValue)",
    "        } else {",
    "            self = nil",
    "        }",
    "    }",
    "}"
)

let swiftArrayParser = String(lines:
    "extension Array {",
    "    init(jsonValue: Any?, map: (Any) throws -> Element) throws {",
    "        guard let items = jsonValue as? [Any] else {",
    "            throw JsonParsingError.unsupportedTypeError",
    "        }",
    "        self = try items.map(map)",
    "    }",
    "}"
)

let swiftContiguousArrayParser = String(lines:
    "extension ContiguousArray {",
    "    init(jsonValue: Any?, map: (Any) throws -> Element) throws {",
    "        guard let items = jsonValue as? [Any] else {",
    "            throw JsonParsingError.unsupportedTypeError",
    "        }",
    "        self = ContiguousArray(try items.lazy.map(map))",
    "    }",
    "}"
)

private extension Declaration {
    static let errorType = Declaration(text: swiftErrorType, priority: 1000)
    static let arrayParser = Declaration(text: swiftArrayParser, priority: 500)
    static let contiguousArrayParser = Declaration(text: swiftContiguousArrayParser, priority: 500)
    static let stringParser = Declaration(text: swiftStringParser, priority: 500)
    static let boolParser = Declaration(text: swiftBoolParser, priority: 500)
    static let intParser = Declaration(text: swiftIntParser, priority: 500)
    static let floatParser = Declaration(text: swiftFloatParser, priority: 500)
    static let doubleParser = Declaration(text: swiftDoubleParser, priority: 500)
    static let optionalParser = Declaration(text: swiftOptionalParser, priority:  500)
}

extension ListType {
    var parser: Declaration {
        switch self {
        case .array: return .arrayParser
        case .contiguousArray: return .contiguousArrayParser
        }
    }
    var className: String {
        return self.rawValue
    }
}

extension ModelParser.FieldType {
    
    static fileprivate func orderedBefore(_ type1: ModelParser.FieldType, before type2: ModelParser.FieldType) -> Bool {
        switch (type1, type2) {
        case (.number(.bool), _): return true
        case (_, .number(.bool)): return false
        default: return type1.enumCaseName < type2.enumCaseName
        }
    }
    
}

struct SwiftJsonParsingTranslator: ModelTranslator {
    
    private var listType: ListType = .array
    
    init(args: [String] = []) {
        self.listType = args.contains("-ca") || args.contains("--contiguousarray") ? .contiguousArray : .array
    }
    
    func translate(_ type: ModelParser.FieldType, name: String) -> String {
        let (parsers, instructions, typeName) = createParsers(type, parentTypeNames: [name], valueExpression: "jsonValue")
        
        let declarations = parsers.sorted {
            if $0.0.priority > $0.1.priority {
                return true
            } else if $0.0.priority == $0.1.priority {
                return $0.0.text < $0.1.text
            }
            return false
        }.lazy.map { $0.text }
        let parseFunction = [String(lines:
            "func parse\(name.camelCasedString)(jsonValue: Any?) throws -> \(typeName) {",
            "    return \(instructions)",
            "}"
        )]
        return String(joined: declarations + parseFunction, separator: "\n\n")
    }
    
    
    
    private func createParser(_ numberType: ModelParser.NumberType, valueExpression: String, tryOptional: Bool) -> (parserDeclarations: Set<Declaration>, parsingInstruction: String, typeName: String) {
        let parser: Declaration
        let instruction: String
        let typeName: String
        let tryOptionalModifier = tryOptional ? "?" : ""
        switch numberType {
        case .bool:
            parser = .boolParser
            instruction = "try\(tryOptionalModifier) Bool(jsonValue: \(valueExpression))"
            typeName = "Bool"
        case .int:
            parser = .intParser
            instruction = "try\(tryOptionalModifier) Int(jsonValue: \(valueExpression))"
            typeName = "Int"
        case .float:
            parser = .floatParser
            instruction = "try\(tryOptionalModifier) Float(jsonValue: \(valueExpression))"
            typeName = "Float"
        case .double:
            parser = .doubleParser
            instruction = "try\(tryOptionalModifier) Double(jsonValue: \(valueExpression))"
            typeName = "Double"
        }
        return ([.errorType, parser], instruction, typeName)
    }
    
    
    
    private func createParsers(_ type: ModelParser.FieldType, parentTypeNames: [String], valueExpression: String, tryOptional: Bool = false) -> (parserDeclarations: Set<Declaration>, parsingInstruction: String, typeName: String) {
        let tryOptionalModifier = tryOptional ? "?" : ""
        switch type {
        case let .number(numberType):
            return createParser(numberType, valueExpression: valueExpression, tryOptional: tryOptional)
        case .text:
            return ([.errorType, .stringParser], "try\(tryOptionalModifier) String(jsonValue: \(valueExpression))", "String")
        case .list(.unknown):
            return ([], "[]", String(joined: parentTypeNames, separator: "."))
        case let .list(listType):
            let childTypeNames: [String]
            if case .list = listType {
                childTypeNames = parentTypeNames
            } else {
                var names = parentTypeNames
                if let last = names.last {
                    names.removeLast()
                    names.append("\(last)Item")
                }
                childTypeNames = names
            }
            let (subDeclarations, instruction, typeName) = createParsers(listType, parentTypeNames: childTypeNames, valueExpression: "$0")
            let declarations = subDeclarations.union([.errorType, self.listType.parser])
            return (declarations, "try\(tryOptionalModifier) \(self.listType.className)(jsonValue: \(valueExpression)) { \(instruction) }", "[\(typeName)]")
        case .optional(.unknown):
            return ([], "nil", String(joined: parentTypeNames, separator: "."))
        case let .optional(optionalType):
            let (subDeclarations, instruction, typeName) = createParsers(optionalType, parentTypeNames: parentTypeNames, valueExpression: "$0")
            return (subDeclarations.union([.errorType, .optionalParser]), "try\(tryOptionalModifier) Optional(jsonValue: \(valueExpression)) { \(instruction) }", "\(typeName)?")
        case let .object(fields):
            var declarations = Set<Declaration>()
            let typeName = String(joined: parentTypeNames, separator: ".")
            var parser = String(lines:
                "extension \(typeName) {",
                "    init(jsonValue: Any?) throws {",
                "        guard let dict = jsonValue as? [String: Any] else {",
                "            throw JsonParsingError.unsupportedTypeError",
                "        }\n"
            )
            parser += String(joined: fields.map { field in
                let (subDeclarations, instruction, _) = createParsers(field.type, parentTypeNames: parentTypeNames + [field.name.camelCasedString], valueExpression: "dict[\"\(field.name)\"]")
                declarations.formUnion(subDeclarations)
                return "self.\(field.name.pascalCased().asValidSwiftIdentifier.swiftKeywordEscaped) = \(instruction)".indent(2)
                }) + "\n"
            parser += String(lines:
                "    }",
                "}"
            )
            declarations.insert(.errorType)
            declarations.insert(.init(text: parser))
            return (declarations, "try\(tryOptionalModifier) \(typeName)(jsonValue: \(valueExpression))", typeName)
        case let .enum(types):
            var declarations = Set<Declaration>()
            let typeName = String(joined: parentTypeNames, separator: ".")
            var parser = String(lines:
                "extension \(typeName) {",
                "    init(jsonValue: Any?) throws {",
                "        "
            )
            let sortedTypes = types.sorted(by: ModelParser.FieldType.orderedBefore)
            parser += String(joined: sortedTypes.map { (type: ModelParser.FieldType) -> String in
                let (subDeclarations, instruction, _) = createParsers(type, parentTypeNames: parentTypeNames + ["\(parentTypeNames.last!)\(type.enumCaseName.firstCapitalized())"], valueExpression: "jsonValue", tryOptional: true)
                declarations.formUnion(subDeclarations)
                return String(lines:
                    "if let value = \(instruction) {",
                    "            self = .\(type.enumCaseName)(value)",
                    "        }"
                )
            }, separator: " else ")
            parser += String(lines:
                          " else {",
                "            throw JsonParsingError.unsupportedTypeError",
                "        }",
                "    }",
                "}"
            )
            declarations.insert(.errorType)
            declarations.insert(.init(text: parser))
            return (declarations, "try\(tryOptionalModifier) \(typeName)(jsonValue: \(valueExpression))", typeName)
        case .unknown:
            return ([], "nil", String(joined: parentTypeNames, separator: "."))
        }
        
    }

}
