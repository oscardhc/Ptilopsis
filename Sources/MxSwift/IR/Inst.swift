//
//  Inst.swift
//  MxSwift
//
//  Created by Haichen Dong on 2020/2/5.
//

import Foundation

class Inst: User {
    
    enum OP {
        case add, sub, mul, sdiv, srem, shl, ashr, and, or, xor, icmp, ret, alloca, call, load, store, getelementptr, br, bitcast, sext, phi
        static let map: [OP: ((Int, Int) -> Int)] = [
            .add: (+), .sub: (-), .mul: (*), .sdiv: (/), .srem: (%), .shl: (<<), .ashr: (>>), .and: (&), .or: (|), .xor: (^)
        ]
    }
    let operation: OP
    var inBlock: BasicBlock
    
    private var nodeInBlock: List<Inst>.Node? = nil
    
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
    
    func changeAppend(to b: BasicBlock) {
        nodeInBlock?.remove()
        nodeInBlock = b.added(self)
        inBlock = b
    }
    
    init(name: String, type: Type, operation: OP, in block: BasicBlock, at index: Int = -1) {
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
    
    var nextInst: Inst? {
        nodeInBlock?.next?.next == nil ? nil : (nodeInBlock?.next?.value)!
    }
    var prevInst: Inst? {
        nodeInBlock?.prev?.prev == nil ? nil : (nodeInBlock?.prev?.value)!
    }
    
    var isTerminate: Bool {
        self is ReturnInst || self is BrInst
    }
    
}

class PhiInst: Inst {
    init (name: String = "", type: Type, in block: BasicBlock, at index: Int = -1) {
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
        for i in 0..<operands.count / 2 where (operands[i * 2 + 1] as! BasicBlock).reachable {
            ccpInfo = ccpInfo.add(rhs: operands[i * 2].ccpInfo) {
                $0.int! == $1.int! ? $0 : nil
            }
        }
    }
}

class SExtInst: Inst {
    init (name: String = "", val: Value, toType: Type, in block: BasicBlock) {
        super.init(name: name, type: toType, operation: .sext, in: block)
        added(operand: val)
    }
    override var toPrint: String {"\(name) = \(operation) \(operands[0]) to \(type)"}
    override func accept(visitor: IRVisitor) {visitor.visit(v: self)}
    override func propogate() {
        ccpInfo = operands[0].ccpInfo
    }
}

class CastInst: Inst {
    init (name: String = "", val: Value, toType: Type, in block: BasicBlock) {
        super.init(name: name, type: toType, operation: .bitcast, in: block)
        added(operand: val)
    }
    override var toPrint: String {"\(name) = \(operation) \(operands[0]) to \(type)"}
    override func accept(visitor: IRVisitor) {visitor.visit(v: self)}
    override func propogate() {
        ccpInfo = operands[0].ccpInfo
    }
}

class BrInst: Inst {
    @discardableResult init(name: String = "", des: Value, in block: BasicBlock) {
        super.init(name: name, type: Type(), operation: .br, in: block)
        added(operand: des)
    }
    @discardableResult init(name: String = "", condition: Value, accept: Value, reject: Value, in block: BasicBlock) {
        super.init(name: name, type: Type(), operation: .br, in: block)
        added(operand: condition)
        added(operand: accept)
        added(operand: reject)
    }
    override func initName() {}
    override var toPrint: String {"\(operation) " + operands.joined()}
    override func accept(visitor: IRVisitor) {visitor.visit(v: self)}
}

class GEPInst: Inst {
    let needZero: Bool
    init(name: String = "", type: Type, base: Value, needZero: Bool, val: Value, in block: BasicBlock, at: Int = -1) {
        self.needZero = needZero
        super.init(name: name, type: type, operation: .getelementptr, in: block, at: at)
        added(operand: base)
        added(operand: val)
        print("init GEP", operands.count, operands[0].type)
    }
    override var toPrint: String {"\(name) = \(operation) \((operands[0].type as! PointerT).baseType), \(operands[0]),\(needZero ? " i32 0," : "") \(operands[1])"}
    override func accept(visitor: IRVisitor) {visitor.visit(v: self)}
}

class ReturnInst: Inst {
    @discardableResult init(name: String = "", val: Value, in block: BasicBlock) {
        super.init(name: name, type: VoidT(), operation: .ret, in: block)
        added(operand: val)
    }
    override func initName() {}
    override var toPrint: String {"\(operation) \(operands[0])"}
    override func accept(visitor: IRVisitor) {visitor.visit(v: self)}
}

class LoadInst: Inst {
    init(name: String = "", alloc: Value, in block: BasicBlock) {
        super.init(name: name, type: (alloc.type as! PointerT).baseType, operation: .load, in: block)
        added(operand: alloc)
    }
    override var toPrint: String {"\(name) = \(operation) \(type), \(operands[0]), align \((operands[0].type as! PointerT).baseType.space)"}
    override func accept(visitor: IRVisitor) {visitor.visit(v: self)}
    override func propogate() {
        ccpInfo = CCPInfo(type: .variable)
    }
}

class StoreInst: Inst {
    @discardableResult init(name: String = "", alloc: Value, val: Value, in block: BasicBlock, at: Int = -1) {
        super.init(name: name, type: Type(), operation: .store, in: block, at: at)
        added(operand: val)
        added(operand: alloc)
    }
    override func initName() {}
    override var toPrint: String {"\(operation) " + operands.joined() + ", align \((operands[1].type as! PointerT).baseType.space)"}
    override func accept(visitor: IRVisitor) {visitor.visit(v: self)}
}

class CallInst: Inst {
    var function: Function
    init(name: String = "", function: Function, arguments: [Value] = [], in block: BasicBlock) {
        self.function = function
        super.init(name: name, type: function.type, operation: .call, in: block)
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

class AllocaInst: Inst {
    init(name: String = "", forType: Type, in block: BasicBlock, at: Int = -1) {
        super.init(name: name, type: forType.pointer, operation: .alloca, in: block, at: at)
    }
    override var toPrint: String {"\(name) = \(operation) \((type as! PointerT).baseType.withAlign)"}
    override func accept(visitor: IRVisitor) {visitor.visit(v: self)}
    override func propogate() {
        ccpInfo = CCPInfo(type: .variable)
    }
}

class BinaryInst: Inst {
    init(name: String = "", type: Type, operation: Inst.OP, lhs: Value, rhs: Value, in block: BasicBlock) {
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
    
    init(name: String = "", lhs: Value, rhs: Value, cmp: CMP, in block: BasicBlock) {
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

