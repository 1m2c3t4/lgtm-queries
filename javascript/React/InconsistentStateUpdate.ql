// Copyright 2018 Semmle Ltd.
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
 * @name Potentially inconsistent state update
 * @description Updating the state of a component based on the current value of
 *              'this.state' or 'this.props' may lead to inconsistent component
 *              state.
 * @kind problem
 * @problem.severity warning
 * @id js/react/inconsistent-state-update
 * @tags reliability
 *       frameworks/react
 * @precision very-high
 */

import semmle.javascript.frameworks.React

/**
 * Gets an unsafe property access, that is, an expression that reads (a property of)
 * `this.state` or `this.prop` on component `c`.
 */
DataFlow::PropRead getAnUnsafeAccess(ReactComponent c) {
  result = c.getAPropRead() or
  result = c.getAStateAccess()
}

/**
 * Gets at unsafe property access that is not the base of another unsafe property
 * access.
 */
DataFlow::PropRead getAnOutermostUnsafeAccess(ReactComponent c) {
  result = getAnUnsafeAccess(c)
  and
  not exists (DataFlow::PropRead outer | outer = getAnUnsafeAccess(c) |
    result = outer.getBase()
  )
}

/**
 * Gets a property write through `setState` for state property `name` of `c`.
 */
DataFlow::PropWrite getAStateUpdate(ReactComponent c, string name) {
  exists (DataFlow::ObjectExprNode newState |
    newState.flowsToExpr(c.getAMethodCall("setState").getArgument(0)) and
    result = newState.getAPropertyWrite(name)
  )
}

/**
 * Gets a property write through `setState` for a state property of `c` that is only written at this property write.
 */
DataFlow::PropWrite getAUniqueStateUpdate(ReactComponent c) {
  exists (string name |
    count(getAStateUpdate(c, name)) = 1 and
    result = getAStateUpdate(c, name)
  )
}

/**
 * Holds for "self dependent" component state updates. E.g. `this.setState({toggled: !this.state.toggled})`.
 */
predicate isAStateUpdateFromSelf(ReactComponent c, DataFlow::PropWrite pwn, DataFlow::PropRead prn) {
  exists (string name |
    pwn = getAStateUpdate(c, name) and
    c.getAStateSource().flowsTo(prn.getBase()) and
    prn.getPropertyName() = name and
    pwn.getRhs().asExpr() = prn.asExpr().getParentExpr*() and
    pwn.getContainer() = prn.getContainer()
  )
}

from ReactComponent c, MethodCallExpr setState, Expr getState
where setState = c.getAMethodCall("setState") and
      getState = getAnOutermostUnsafeAccess(c).asExpr() and
      getState.getParentExpr*() = setState.getArgument(0) and
      getState.getEnclosingFunction() = setState.getEnclosingFunction() and
      // ignore self-updates that only occur in one location: `setState({toggled: !this.state.toggled})`, they are most likely safe in practice
      not exists (DataFlow::PropWrite pwn |
        pwn = getAUniqueStateUpdate(c) and
        isAStateUpdateFromSelf(c, pwn, DataFlow::valueNode(getState))
      )
select setState, "Component state update uses $@.", getState, "potentially inconsistent value"