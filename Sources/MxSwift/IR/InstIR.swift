//
//  Inst.swift
//  MxSwift
//
//  Created by Haichen Dong on 2020/2/5.
//

import Foundation

class InstIR: User {
    
    enum OP {
        case add, sub, mul, sdiv, srem, shl, ashr, and, or, xor, icmp, ret, alloca, call, load, store, getelementptr, br, bitcast, sext, phi
        static let map: [OP: ((Int, Int) -> Int)] = [
            .add: (+), .sub: (-), .mul: (*), .sdiv: (/), .srem: (%), .shl: (<<), .ashr: (>>), .and: (&), .or: {($0|$1) & 4294967295}, .xor: (^)
        ]
    }
    let operation: OP
    var inBlock: BlockIR
    
    private var nodeInBlock: List<InstIR>.Node? = nil
    
    func disconnect(delUsee: Bool, delUser: Bool) {
        nodeInBlock?.remove()
        if delUsee {
            for usee in usees {
                usee.disconnect()
            }
        }
        if delUser {
            for user in users {
                user.disconnect()
            }
        }
    }
    
    func replaced(by value: Value) {
        for use in users {
            use.reconnect(fromValue: value)
        }
        disconnect(delUsee: true, delUser: false)
    }
    
    func changeAppend(to b: BlockIR) {
        nodeInBlock?.remove()
        nodeInBlock = b.added(self)
        inBlock = b
    }
    
    init(name: String, type: TypeIR, operation: OP, in block: BlockIR, at index: Int = -1) {
        self.operation = operation
        self.inBlock = block
        super.init(name: name, type: type)
        if index == -1 {
            self.nodeInBlock = inBlock.added(self)
        } else {
            self.nodeInBlock = inBlock.inserted(self, at: index)
        }
    }
    
    var isCritical: Bool {
        self is AllocaInst || self is CallInst || self is StoreInst || self is LoadInst || self is BrInst || self is ReturnInst
    }
    
    var blockIndexBF: Int {
        nodeInBlock!.list.getNodeIndexBF(from: nodeInBlock!)
    }
    
    var nextInst: InstIR? {
        nodeInBlock?.next?.next == nil ? nil : (nodeInBlock?.next?.value)!
    }
    var prevInst: InstIR? {
        nodeInBlock?.prev?.prev == nil ? nil : (nodeInBlock?.prev?.value)!
    }
    
    var isTerminate: Bool {
        self is ReturnInst || self is BrInst
    }
    
}

class PhiInst: InstIR {
    init (name: String = "", type: TypeIR, in block: BlockIR, at index: Int = -1) {
        super.init(name: name, type: type, operation: .phi, in: block, at: index)
    }
    override var toPrint: String {
        var ret = "\(name) = \(operation) \(type) ", idx = 0
        while idx < operands.count {
            if idx != 0 {
                ret += ", "
            }
            ret += "[\(operands[idx].name), \(operands[idx + 1].name)]"
            idx += 2
        }
        return ret
    }
    override func accept(visitor: IRVisitor) {visitor.visit(v: self)}
    override func propogate() {
        ccpInfo = CCPInfo()
        for i in 0..<operands.count / 2 where (operands[i * 2 + 1] as! BlockIR).reachable {
            ccpInfo = ccpInfo.add(rhs: operands[i * 2].ccpInfo) {
                $0.int! == $1.int! ? $0 : nil
            }
        }
    }
}

class SExtInst: InstIR {
    init (name: String = "", val: Value, toType: TypeIR, in block: BlockIR) {
        super.init(name: name, type: toType, operation: .sext, in: block)
        added(operand: val)
    }
    override var toPrint: String {"\(name) = \(operation) \(operands[0]) to \(type)"}
    override func accept(visitor: IRVisitor) {visitor.visit(v: self)}
    override func propogate() {
        ccpInfo = operands[0].ccpInfo
    }
}

class CastInst: InstIR {
    init (name: String = "", val: Value, toType: TypeIR, in block: BlockIR) {
        super.init(name: name, type: toType, operation: .bitcast, in: block)
        added(operand: val)
    }
    override var toPrint: String {"\(name) = \(operation) \(operands[0]) to \(type)"}
    override func accept(visitor: IRVisitor) {visitor.visit(v: self)}
    override func propogate() {
        ccpInfo = operands[0].ccpInfo
    }
}

class BrInst: InstIR {
    @discardableResult init(name: String = "", des: Value, in block: BlockIR) {
        super.init(name: name, type: TypeIR(), operation: .br, in: block)
        added(operand: des)
    }
    @discardableResult init(name: String = "", condition: Value, accept: Value, reject: Value, in block: BlockIR) {
        super.init(name: name, type: TypeIR(), operation: .br, in: block)
        added(operand: condition)
        added(operand: accept)
        added(operand: reject)
    }
    override func initName() {}
    override var toPrint: String {"\(operation) " + operands.joined()}
    override func accept(visitor: IRVisitor) {visitor.visit(v: self)}
}

class GEPInst: InstIR {
    let needZero: Bool
    init(name: String = "", type: TypeIR, base: Value, needZero: Bool, val: Value, in block: BlockIR, at: Int = -1, doNotLoad: Bool = false) {
        self.needZero = needZero
        super.init(name: name, type: type, operation: .getelementptr, in: block, at: at)
        added(operand: base)
        added(operand: val)
        self.forceDoNotLoad = doNotLoad
//        print("init GEP", operands.count, operands[0].type)
    }
    override var toPrint: String {"\(name) = \(operation) \((operands[0].type as! PointerT).baseType), \(operands[0]),\(needZero ? " i32 0," : "") \(operands[1])"}
    override func accept(visitor: IRVisitor) {visitor.visit(v: self)}
}

class ReturnInst: InstIR {
    @discardableResult init(name: String = "", val: Value, in block: BlockIR) {
        super.init(name: name, type: VoidT(), operation: .ret, in: block)
        added(operand: val)
    }
    override func initName() {}
    override var toPrint: String {"\(operation) \(operands[0])"}
    override func accept(visitor: IRVisitor) {visitor.visit(v: self)}
}

class LoadInst: InstIR {
    init(name: String = "", alloc: Value, in block: BlockIR, at: Int = -1) {
        super.init(name: name, type: (alloc.type as! PointerT).baseType, operation: .load, in: block, at: at)
        added(operand: alloc)
    }
    override var toPrint: String {"\(name) = \(operation) \(type), \(operands[0]), align \((operands[0].type as! PointerT).baseType.space)"}
    override func accept(visitor: IRVisitor) {visitor.visit(v: self)}
    override func propogate() {
        ccpInfo = CCPInfo(type: .variable)
    }
}

class StoreInst: InstIR {
    @discardableResult init(name: String = "", alloc: Value, val: Value, in block: BlockIR, at: Int = -1) {
        super.init(name: name, type: TypeIR(), operation: .store, in: block, at: at)
        added(operand: val)
        added(operand: alloc)
    }
    override func initName() {}
    override var toPrint: String {"\(operation) " + operands.joined() + ", align \((operands[1].type as! PointerT).baseType.space)"}
    override func accept(visitor: IRVisitor) {visitor.visit(v: self)}
}

class CallInst: InstIR {
    var function: FunctionIR
    init(name: String = "", function: FunctionIR, arguments: [Value] = [], in block: BlockIR, at idx: Int = -1) {
        self.function = function
        super.init(name: name, type: function.type, operation: .call, in: block, at: idx)
        arguments.forEach {self.added(operand: $0)}
    }
    override func initName() {
        if !(type is VoidT) {
            super.initName()
        }
    }
    override var toPrint: String {"\(type is VoidT ? "" : "\(name) = ")\(operation) \(type) \(function.name)(\(operands))"}
    override func accept(visitor: IRVisitor) {visitor.visit(v: self)}
    override func propogate() {
        ccpInfo = CCPInfo(type: .variable)
    }
}

class AllocaInst: InstIR {
    init(name: String = "", forType: TypeIR, in block: BlockIR, at: Int = -1) {
        super.init(name: name, type: forType.pointer, operation: .alloca, in: block, at: at)
    }
    override var toPrint: String {"\(name) = \(operation) \(type.getBase.withAlign)"}
    override func accept(visitor: IRVisitor) {visitor.visit(v: self)}
    override func propogate() {
        ccpInfo = CCPInfo(type: .variable)
    }
}

class BinaryInst: InstIR {
    init(name: String = "", type: TypeIR, operation: InstIR.OP, lhs: Value, rhs: Value, in block: BlockIR) {
        super.init(name: name, type: type, operation: operation, in: block)
        added(operand: lhs)
        added(operand: rhs)
    }
    override var toPrint: String {return "\(name) = \(operation) \(type) " + operands.joined() {"\($0.name)"}}
    override func accept(visitor: IRVisitor) {visitor.visit(v: self)}
    
    override func propogate() {
        ccpInfo = operands[0].ccpInfo.add(rhs: operands[1].ccpInfo) {
            CCPInfo(type: .int, int: OP.map[operation]!($0.int!, $1.int!))
        }
    }
}

class CompareInst: BinaryInst {
    enum CMP {
        case eq, ne, sgt, sge, slt, sle
        static let map: [CMP: (Int, Int) -> Bool] = [
            .eq: (==), .ne: (!=), .sgt: (>), .sge: (>=), .slt: (<), .sle: (<=)
        ]
    }
    let cmp: CMP
    
    init(name: String = "", lhs: Value, rhs: Value, cmp: CMP, in block: BlockIR) {
        self.cmp = cmp
        super.init(name: name, type: IntT.bool, operation: .icmp, lhs: lhs, rhs: rhs, in: block)
    }
    override var toPrint: String {return "\(name) = \(operation) \(cmp) \(operands[0].type) " + operands.joined() {"\($0.name)"}}
    override func accept(visitor: IRVisitor) {visitor.visit(v: self)}
    
    override func propogate() {
        ccpInfo = operands[0].ccpInfo.add(rhs: operands[1].ccpInfo) {
            CCPInfo(type: .int, int: CMP.map[cmp]!($0.int!, $1.int!) ? 1 : 0)
        }
    }
}

