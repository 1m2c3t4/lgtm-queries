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

import java
private import semmle.code.java.controlflow.Dominance

/**
 * A basic block that terminates in a condition, splitting the subsequent control flow.
 */
class ConditionBlock extends BasicBlock {
  ConditionBlock() {
    this.getLastNode() instanceof ConditionNode
  }

  /** The last node of this basic block. */
  ConditionNode getConditionNode() {
    result = this.getLastNode()
  }

  /** The condition of the last node of this basic block. */
  Expr getCondition() {
    result = this.getConditionNode().getCondition()
  }

  /** A `true`- or `false`-successor of the last node of this basic block. */
  BasicBlock getTestSuccessor(boolean testIsTrue) {
    result = this.getConditionNode().getABranchSuccessor(testIsTrue)
  }

  /** Basic blocks controlled by this condition, that is, those basic blocks for which the condition is `testIsTrue`. */
  predicate controls(BasicBlock controlled, boolean testIsTrue) {
    /*
     * For this block to control the block `controlled` with `testIsTrue` the following must be true:
     * Execution must have passed through the test i.e. `this` must strictly dominate `controlled`.
     * Execution must have passed through the `testIsTrue` edge leaving `this`.
     *
     * Although "passed through the true edge" implies that `this.getATrueSuccessor()` dominates `controlled`,
     * the reverse is not true, as flow may have passed through another edge to get to `this.getATrueSuccessor()`
     * so we need to assert that `this.getATrueSuccessor()` dominates `controlled` *and* that
     * all predecessors of `this.getATrueSuccessor()` are either `this` or dominated by `this.getATrueSuccessor()`.
     *
     * For example, in the following java snippet:
     * ```
     * if (x)
     *   controlled;
     * false_successor;
     * uncontrolled;
     * ```
     * `false_successor` dominates `uncontrolled`, but not all of its predecessors are `this` (`if (x)`)
     *  or dominated by itself. Whereas in the following code:
     * ```
     * if (x)
     *   while (controlled)
     *     also_controlled;
     * false_successor;
     * uncontrolled;
     * ```
     * the block `while controlled` is controlled because all of its predecessors are `this` (`if (x)`)
     * or (in the case of `also_controlled`) dominated by itself.
     *
     * The additional constraint on the predecessors of the test successor implies
     * that `this` strictly dominates `controlled` so that isn't necessary to check
     * directly.
     */
    exists(BasicBlock succ |
      succ = this.getTestSuccessor(testIsTrue) and
      succ.bbDominates(controlled) and
      forall(BasicBlock pred | pred = succ.getABBPredecessor() and pred != this |
        succ.bbDominates(pred)
      )
    )
  }
}