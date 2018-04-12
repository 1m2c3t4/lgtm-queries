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
 * Provides support for intra-procedural tracking of a customizable
 * set of data flow nodes.
 *
 * Note that unlike `TrackedNodes`, this library only performs
 * local tracking within a function.
 */

import javascript

/**
 * A source node for local data flow, that is, a node for which local
 * data flow cannot provide any information about its inputs.
 *
 * By default, functions, object and array expressions and JSX nodes
 * are considered sources, as well as expressions that have non-local
 * flow (such as calls and property accesses). Additional sources
 * can be modelled by extending this class with additional subclasses.
 */
abstract class SourceNode extends DataFlow::Node {
  /**
   * Holds if this node flows into `sink` in zero or more local (that is,
   * intra-procedural) steps.
   */
  cached
  predicate flowsTo(DataFlow::Node sink) {
    sink = this or
    flowsTo(sink.getAPredecessor())
  }

  /**
   * Holds if this node flows into `sink` in zero or more local (that is,
   * intra-procedural) steps.
   */
  predicate flowsToExpr(Expr sink) {
    flowsTo(DataFlow::valueNode(sink))
  }

  /**
   * Gets a read of property `propName` on this node.
   */
  SourceNode getAPropertyRead(string propName) {
    exists (PropReadNode prn | result = DataFlow::valueNode(prn) |
      flowsToExpr(prn.getBase()) and
      prn.getPropertyName() = propName
    )
  }

  /**
   * Gets an access to property `propName` on this node, either through
   * a dot expression (as in `x.propName`) or through an index expression
   * (as in `x["propName"]`).
   */
  SourceNode getAPropertyAccess(string propName) {
    exists (PropAccess pacc | result = DataFlow::valueNode(pacc) |
      flowsToExpr(pacc.getBase()) and
      pacc.getPropertyName() = propName
    )
  }

  /**
   * Holds if there is an assignment to property `propName` on this node,
   * and the right hand side of the assignment is `rhs`.
   */
  predicate hasPropertyWrite(string propName, Expr rhs) {
    exists (PropWriteNode pwn |
      flowsToExpr(pwn.getBase()) and
      pwn.getPropertyName() = propName and
      rhs = pwn.getRhs()
    )
  }

  /**
   * Gets an invocation of the method or constructor named `memberName` on this node.
   */
  DataFlow::InvokeNode getAMemberInvocation(string memberName) {
    result = getAPropertyAccess(memberName).getAnInvocation()
  }

  /**
   * Gets a function call that invokes method `memberName` on this node.
   *
   * This includes both calls that have the syntactic shape of a method call
   * (as in `o.m(...)`), and calls where the callee undergoes some additional
   * data flow (as in `tmp = o.m; tmp(...)`).
   */
  DataFlow::CallNode getAMemberCall(string memberName) {
    result = getAMemberInvocation(memberName)
  }

  /**
   * Gets a method call that invokes method `methodName` on this node.
   *
   * This includes only calls that have the syntactic shape of a method call,
   * that is, `o.m(...)` or `o[p](...)`.
   */
  DataFlow::CallNode getAMethodCall(string methodName) {
    exists (PropAccess pacc |
      pacc = result.getCallee().asExpr().stripParens() and
      flowsToExpr(pacc.getBase()) and
      pacc.getPropertyName() = methodName
    )
  }

  /**
   * Gets a `new` call that invokes constructor `constructorName` on this node.
   */
  DataFlow::NewNode getAConstructorInvocation(string constructorName) {
    result = getAMemberInvocation(constructorName)
  }

  /**
   * Gets an invocation (with our without `new`) of this node.
   */
  DataFlow::InvokeNode getAnInvocation() {
    flowsTo(result.getCallee())
  }

  /**
   * Gets a function call to this node.
   */
  DataFlow::CallNode getACall() {
    result = getAnInvocation()
  }

  /**
   * Gets a `new` call to this node.
   */
  DataFlow::NewNode getAnInstantiation() {
    result = getAnInvocation()
  }
}

/**
 * A data flow node that is considered a source node by default.
 *
 * Currently, the following nodes are source nodes:
 *   - import specifiers
 *   - non-destructuring function parameters
 *   - property accesses
 *   - function invocations
 *   - `this` expressions
 *   - global variable accesses
 *   - function definitions
 *   - class definitions
 *   - object expressions
 *   - array expressions
 *   - JSX literals.
 */
class DefaultSourceNode extends SourceNode {
  DefaultSourceNode() {
    not exists(getAPredecessor()) and
    (
      exists (ASTNode astNode | this = DataFlow::valueNode(astNode) |
        astNode instanceof PropAccess or
        astNode instanceof Function or
        astNode instanceof ClassDefinition or
        astNode instanceof InvokeExpr or
        astNode instanceof ObjectExpr or
        astNode instanceof ArrayExpr or
        astNode instanceof JSXNode or
        astNode instanceof ThisExpr or
        astNode instanceof GlobalVarAccess
      )
      or
      exists (SsaExplicitDefinition ssa, VarDef def |
        this = DataFlow::ssaDefinitionNode(ssa) and def = ssa.getDef() |
        def instanceof SimpleParameter or
        def instanceof ImportSpecifier
      )
    )
  }
}
