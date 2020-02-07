//
//  Const.swift
//  MxSwift
//
//  Created by Haichen Dong on 2020/2/6.
//

import Foundation

class Const: User {
    
}

class Global: Const {
    
    var currentModule: Module?
    
    init(name: String, type: Type, module: Module?) {
        self.currentModule = module
        super.init(name: name, type: type)
    }
    
}

class Parameter: Value {
    
}

class Function: Global {
    
    var blocks = List<BasicBlock>()
    var parameters = List<Parameter>()
    
    override func accept(visitor: IRVisitor) {visitor.visit(v: self)}
    
    override var description: String {return "\(type) @\(name)(\(parameters))"}
    
}

class GlobalVariable: Global {
    
}
