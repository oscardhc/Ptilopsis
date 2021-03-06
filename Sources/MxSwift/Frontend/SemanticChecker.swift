//
//  SemanticChecker.swift
//  MxSwift
//
//  Created by Haichen Dong on 2020/2/2.
//

import Foundation

// 1. check whether declaration type(class) is declared
// deal with l-value & types of expressions
// 2. array/member accessable
// 3. type-check

class SemanticChecker: ASTBaseVisitor {

    override func visit(node: Program) {
        super.visit(node: node)
        var hasMain = false
        for decl in node.declarations where decl is FunctionD && (decl as! FunctionD).id == "main" {
            hasMain = true
        }
        if !hasMain {
            error.noMainFunction()
        }
    }

    override func visit(node: VariableD) {
        super.visit(node: node)
        let baseType = node.type.dropAllArray()
        if baseType.isBuiltinType() || node.scope.find(name: baseType) != nil {
            if baseType == void {
                error.typeError(name: node.variable.description, type: baseType)
            }
            node.variable.forEach {
                if let e = $0.1 {
                    if node.type === e.type || (e.type == null && (node.type.hasSuffix("[]") || !node.type.isBuiltinType())) {
                        
                    } else {
                        error.binaryOperatorError(op: .assign, type1: node.type, type2: e.type)
                    }
                }
            }
        } else {
            error.notDeclared(id: baseType, scopeName: node.scope.scopeName)
        }
    }

    override func visit(node: FunctionD) {
        super.visit(node: node)
        let type = node.type.dropAllArray()
        if !builtinTypes.contains(type) && node.scope.find(name: type, check: {$0.subScope?.scopeType == .CLASS}) == nil {
            error.typeError(name: node.id, type: node.type)
        }
        if node.id == "main" && (node.type != int || node.parameters.count > 0) {
            error.mainFuncError()
        }
    }

    override func visit(node: ClassD) {
        super.visit(node: node)
    }

    override func visit(node: DeclarationS) {
        super.visit(node: node)
    }

    override func visit(node: CodeblockS) {
        super.visit(node: node)
    }

    override func visit(node: IfS) {
        super.visit(node: node)
        if node.condition.type != bool {
            error.controlConditionError(flow: "If", type: node.condition.type)
        }
    }

    override func visit(node: WhileS) {
        super.visit(node: node)
        if node.condition.type != bool {
            error.controlConditionError(flow: "While", type: node.condition.type)
        }
    }

    override func visit(node: ForS) {
        super.visit(node: node)
        if node.condition != nil && node.condition!.type != bool {
            error.controlConditionError(flow: "For", type: node.condition!.type)
        }
    }

    override func visit(node: ReturnS) {
        super.visit(node: node)
        if let _c = node.scope.currentScope(type: .FUNCTION) {
            let c = _c.correspondingNode as! FunctionD
            c.hasReturn = true
            if c.type == void || c.id == c.type {
                if node.expression?.type ?? void != void {
                    error.returnTypeError(name: c.id, expected: c.type, received: void)
                }
            } else {
                if c.type !== node.expression!.type {
                    error.returnTypeError(name: c.id, expected: c.type, received: node.expression!.type)
                } else {
                    node.expression!.type = c.type
                }
            }
        } else {
            error.statementError(name: node.description, environment: node.scope.scopeName)
        }
    }

    override func visit(node: BreakS) {
        super.visit(node: node)
        if node.scope.currentScope(type: .LOOP) == nil {
            error.statementError(name: node.description, environment: node.scope.scopeName)
        }
    }

    override func visit(node: ContinueS) {
        super.visit(node: node)
        if node.scope.currentScope(type: .LOOP) == nil {
            error.statementError(name: node.description, environment: node.scope.scopeName)
        }
    }

    override func visit(node: ExpressionS) {
        super.visit(node: node)
    }

    override func visit(node: VariableE) {
        super.visit(node: node)
        let sym = node.scope.find(name: node.id)!
        node.type = sym.type
    }

    override func visit(node: ThisLiteralE) {
        super.visit(node: node)
        if let c = node.scope.currentScope(type: .CLASS) {
            node.type = c.scopeName
        } else {
            error.notInClass(key: "this")
        }
    }

    override func visit(node: BoolLiteralE) {
        super.visit(node: node)
        node.type = bool
    }

    override func visit(node: IntLiteralE) {
        super.visit(node: node)
        node.type = int
    }

    override func visit(node: StringLiteralE) {
        super.visit(node: node)
        node.type = string
    }

    override func visit(node: NullLiteralE) {
        super.visit(node: node)
        node.type = null
    }

    override func visit(node: MethodAccessE) {
//        super.visit(node: node)
        node.toAccess.accept(visitor: self)
        let c = node.toAccess.type
        if c.hasSuffix("[]") && node.method.id == "size" {
            node.type = int
            node.method.id = builtinSize
        } else if let sym = node.scope.find(name: c, check: {$0.subScope?.scopeType == .CLASS}) {
            if let m = sym.subScope!.table[node.method.id] {
                node.type = m.type
                node.scope = sym.subScope!
                node.method.needThis = false
                node.method.scope = sym.subScope!
            } else {
                error.noSuchMember(name: node.method.id, c: c)
            }
        } else {
            error.notInClass(key: node.method.id)
        }
        node.method.accept(visitor: self)
    }

    override func visit(node: PropertyAccessE) {
        super.visit(node: node)
        if let c = node.scope.find(name: node.toAccess.type, check: {$0.subScope?.scopeType == .CLASS}) {
            if let t = c.subScope!.table[node.property] {
                node.scope = c.subScope!
                node.type = t.type
            } else {
                error.noSuchMember(name: node.property, c: c.subScope!.scopeName)
            }
        } else {
            error.notInClass(key: node.property)
        }
    }

    override func visit(node: ArrayE) {
        super.visit(node: node)
        if node.array.type.hasSuffix("[]") {
            if node.index.type == int {
                node.type = node.array.type.dropArray()
            } else {
                error.indexError(type: node.index.type)
            }
        } else {
            error.subscriptError(id: node.array.description)
        }
    }

    override func visit(node: FunctionCallE) {
        super.visit(node: node)
        if let t = node.scope.find(name: node.id, check: {[.CLASS, .FUNCTION].contains($0.subScope?.scopeType)}) {
            if let scp = t.subScope {
                let decl = (scp.scopeType == .CLASS ? scp.table[node.id]!.subScope!.correspondingNode! : scp.correspondingNode!) as! FunctionD
                if scp.scopeType == .CLASS {
                    node.scope = scp
                }
                var exp: [String] = [], rec: [String] = []
                decl.parameters.forEach{exp.append($0.type)}
                node.arguments.forEach{rec.append($0.type)}
                node.type = decl.type
                if exp !== rec {
                    error.argumentError(name: node.id, expected: exp, received: rec)
                }
            } else {
                error.notCallable(name: node.id)
            }
        } else if node.id == builtinSize {
            node.type = int
        } else {
            error.notDeclared(id: node.id, scopeName: node.scope.scopeName)
        }
    }

    override func visit(node: SuffixE) {
        let unaryError = {error.unaryOperatorError(op: node.op, type1: node.expression.type)}
        super.visit(node: node)
        switch node.op {
        case .doubleAdd, .doubleSub:
            if node.expression.type == int {
                node.type = int
                if !node.expression.lValuable {
                    error.notAssignable(id: node.expression.description)
                }
            } else {unaryError()}
        default:
            break
        }
    }

    override func visit(node: PrefixE) {
        let unaryError = {error.unaryOperatorError(op: node.op, type1: node.expression.type)}
        super.visit(node: node)
        switch node.op {
        case .doubleAdd, .doubleSub, .add, .sub, .bitwise:
            if [.doubleAdd, .doubleSub].contains(node.op) && !node.expression.lValuable {
                error.notAssignable(id: node.expression.description)
            }
            if node.expression.type == int {
                node.type = int
            } else {unaryError()}
        case .negation:
            if node.expression.type == bool {
                node.type = bool
            } else {unaryError()}
        }
    }

    override func visit(node: NewE) {
        super.visit(node: node)
        if node.baseType.isBuiltinType() || node.scope.find(name: node.baseType) != nil {
            for exp in node.expressions where exp.type != int {
                error.indexError(name: exp.description, type: exp.type)
            }
            node.type = node.baseType
            for _ in 0 ..< (node.expressions.count + node.empty) {node.type += "[]"}
        }
    }
    
    override func visit(node: BinaryE) {
        super.visit(node: node)
        let binaryError = {error.binaryOperatorError(op: node.op, type1: node.lhs.type, type2: node.rhs.type)}
        switch node.op {
        case .assign:
            if node.lhs.lValuable == false {
                error.notAssignable(id: node.lhs.description)
            } else if node.lhs.type == node.rhs.type || (node.rhs.type == null && (node.lhs.type.hasSuffix("[]") || !node.lhs.type.isBuiltinType())) {
            } else {binaryError()}
        case .add:
            if node.lhs.type === node.rhs.type && [int, string].contains(node.lhs.type) {
                node.type = node.lhs.type
            } else {binaryError()}
        case .sub, .mul, .mod, .div, .bitAnd, .bitOr, .bitXor, .lShift, .rShift:
            if node.lhs.type === node.rhs.type && [int].contains(node.lhs.type) {
                node.type = node.lhs.type
            } else {binaryError()}
        case .gt, .geq, .lt, .leq:
            if node.lhs.type === node.rhs.type && [int, string].contains(node.lhs.type) {
                node.type = bool
            } else {binaryError()}
        case .eq, .neq:
            if node.lhs.type === node.rhs.type {
                node.type = bool
            } else {binaryError()}
        case .logAnd, .logOr:
            if node.lhs.type === node.rhs.type && [bool].contains(node.lhs.type) {
                node.type = bool
            } else {binaryError()}
        }
    }

}
