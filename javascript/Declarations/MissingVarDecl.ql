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
 * @name Missing variable declaration
 * @description If a variable is not declared as a local variable, it becomes a global variable
 *              by default, which may be unintentional and could lead to unexpected behavior.
 * @kind problem
 * @problem.severity error
 * @tags reliability
 *       maintainability
 * @precision high
 */

import javascript

/**
 * Gets an undeclared global in `f`, that is, a global variable that is accessed in `f`,
 * but not declared in the same toplevel as `f`.
 */
GlobalVariable undeclaredGlobalIn(Function f) {
  result.getAnAccess().getEnclosingFunction() = f and
  not result.declaredIn(f.getTopLevel())
}

/**
 * Gets an accidental global in `f`, that is, an undeclared global in `f` that is not
 * live at the entry of `f`, meaning that it is always written before being read the
 * first time.
 */
GlobalVariable accidentalGlobalIn(Function f) {
  result = undeclaredGlobalIn(f) and
  not f.getStartBB().isLiveAtEntry(result)
}

/**
 * Gets an accidental global in `f` that is read at least once in reachable code.
 *
 * This prevents duplication of results between this query and 'Useless assignment
 * to global variable'.
 */
GlobalVariable candidateVariable(Function f) {
  result = accidentalGlobalIn(f) and
  f.getStartBB().getASuccessor*().useAt(_, result, _)
}

/**
 * Gets an access to `v` in function `f`.
 */
GlobalVarAccess getAccessIn(GlobalVariable v, Function f) {
  result.getEnclosingFunction() = f and
  result = v.getAnAccess()
}

/**
 * Gets the (lexically) first access to variable `v` in function `f`.
 */
GlobalVarAccess getFirstAccessIn(GlobalVariable v, Function f) {
  result = min(getAccessIn(v, f) as gva
               order by gva.getLocation().getStartLine(), gva.getLocation().getStartColumn())
}

from Function f, GlobalVariable gv
where gv = candidateVariable(f)
select getFirstAccessIn(gv, f), "Variable " + gv.getName() + " is used like a local variable, but is missing a declaration."