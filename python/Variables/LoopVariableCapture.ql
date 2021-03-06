// Copyright 2017 Semmle Ltd.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software distributed under
// the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the specific language governing
// permissions and limitations under the License.

/**
 * @name Loop variable capture
 * @description Capture of a loop variable is not the same as capturing the value of a loop variable, and may be erroneous.
 * @kind problem
 * @tags correctness
 * @problem.severity error
 * @sub-severity low
 * @precision high
 */

import python

// Gets the scope of the iteration variable of the looping scope
Scope iteration_variable_scope(AstNode loop) {
    result = loop.(For).getScope()
    or
    result = loop.(Comp).getFunction()
}

predicate capturing_looping_construct(CallableExpr capturing, AstNode loop, Variable var) {
    var.getScope() = iteration_variable_scope(loop) and
    var.getAnAccess().getScope() = capturing.getInnerScope() and
    capturing.getParentNode+() = loop and
    (
        loop.(For).getTarget() = var.getAnAccess()
        or
        var = loop.(Comp).getAnIterationVariable()
    )
}

predicate escaping_capturing_looping_construct(CallableExpr capturing, AstNode loop, Variable var) {
    capturing_looping_construct(capturing, loop, var) 
    and
    // Escapes if used out side of for loop or is a lambda in a comprehension
    (
        exists(Expr e, For forloop | forloop = loop and e.refersTo(_, _, capturing) | not forloop.contains(e))
        or
        loop.(Comp).getElt() = capturing
        or
        loop.(Comp).getElt().(Tuple).getAnElt() = capturing
    )
}

from CallableExpr capturing, AstNode loop, Variable var
where escaping_capturing_looping_construct(capturing, loop, var)
select capturing, "Capture of loop variable '$@'", loop, var.getId()
