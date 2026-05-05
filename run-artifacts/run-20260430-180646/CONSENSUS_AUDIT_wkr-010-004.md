# Collaboration Consensus Inclusion Audit
**Worker:** wkr-010-004  
**Run:** run-20260430-180646  
**Timestamp:** 2026-05-01T01:30:00Z  
**Scope:** Review-only QA of multi-agent consensus capture and merge mechanisms

---

## Executive Summary

Terminal Stampede implements a **collaboration bus** for metaswarm commanders with a structured consensus workflow (`propose → peer_review → improve → consensus → broadcast → adopt`). However, **consensus data is NOT merged or synthesized** into final outputs for standard worker runs. Critical gaps exist in:

1. **Worker-level consensus**: No mechanism for parallel workers to signal agreement/conflict
2. **Merger consensus integration**: Merger agent ignores collaboration bus entirely
3. **Orchestrator synthesis**: SKILL.md synthesis step does not read or aggregate consensus
4. **Cross-commander consensus adoption**: Commanders write consensus but downstream consumers don't read it

---

## Findings by Component

### 1. Collaboration Bus (Metaswarm Only)

**Location:** `bin/stampede.sh:670-720`, `.stampede/{run_id}/collab/`

**What Works:**
- ✅ Protocol defined with 5 JSONL ledgers: proposals, reviews, improvements, consensus, broadcasts
- ✅ Append-only atomic writes with O_APPEND semantics
- ✅ Commander agents instructed to follow `propose → peer_review → improve → consensus → broadcast → adopt` workflow
- ✅ Monitor displays live counts (`stampede-monitor.sh:57-66`)
- ✅ Real data captured in production runs (verified in `run-20260430-180646/collab/`)

**Example Consensus Record:**
```json
{
  "ts": "2026-05-01T01:12:13Z",
  "run_id": "run-20260430-180646",
  "commander_id": "commander-001",
  "event": "consensus",
  "item_id": "cons-c001-pre-build-blockers",
  "summary": "Pre-build BLOCKERS for metaswarm...",
  "verdict": "blocker",
  "confidence": 0.92,
  "based_on": ["imp-c001-premium-enforcement", ...],
  "source_refs": ["bin/stampede.sh:15", ...]
}
```

**Gaps:**
- ❌ **Commander bundles reference consensus but orchestrator doesn't consume it**
  - Commanders write `adopted_consensus_item_ids` and `broadcasts` fields to bundle.json (verified in `commander-001.json`)
  - Neither `SKILL.md` synthesis (line 568-640) nor merger agent reads these fields
  - **Impact:** Cross-commander agreement/conflict invisible to final report

- ❌ **No validation that broadcasts were adopted**
  - Commanders append to `broadcasts.jsonl` but no reader confirms adoption
  - No merge step aggregates consensus tiers (CONSENSUS/MAJORITY/CONFLICT/UNIQUE)
  - **Impact:** Consensus tier in bundle.json is write-only metadata

- ❌ **Collaboration bus only exists for `--metaswarm` mode**
  - Standard worker runs (`stampede-agent`) have no consensus mechanism
  - Workers write independent bundles with no cross-agent review
  - **Impact:** Parallel workers cannot signal conflicting approaches or converge on best solution

---

### 2. Merger Agent Consensus Handling

**Location:** `agents/stampede-merger.agent.md`, `bin/stampede-merge.sh`

**What the Merger Does:**
- ✅ Merges all worker branches sequentially (smallest first)
- ✅ Detects git conflicts via `git diff --diff-filter=U`
- ✅ Resolves conflicts using AI with task context (lines 89-137 of merger agent)
- ✅ Scores agents on 5 dimensions (Completeness, Scope, Quality, Test, Conflict)
- ✅ Produces `merge-report.json` with per-agent scores and model attribution

**Conflict Resolution Strategy (Priority Order):**
1. Additive changes (both sides added code) → keep both
2. Format vs. content → keep logic change with new formatting
3. Same function, different changes → read task descriptions, apply both if non-overlapping
4. Structural conflicts (reorganization vs. content) → skip as irreconcilable
5. Delete vs. modify → always irreconcilable, skip

**Critical Gaps:**

❌ **No semantic consensus detection**
- Merger resolves git conflicts but doesn't detect **semantic conflicts**
- Example: Two agents implement same feature differently (both valid, no git conflict)
- **Missing:** Compare agent outputs for logical contradictions or duplicate work

❌ **No cross-agent voting or agreement scoring**
- If 3 agents modify the same function differently, merger picks merge order (size-based)
- No mechanism to identify "2 agents used approach A, 1 used approach B"
- **Missing:** Majority/minority voting when multiple agents address same concern

❌ **Merger doesn't read collaboration bus**
- In metaswarm runs, commanders produce consensus.jsonl but merger ignores it
- **Missing:** `stampede-merge.sh` and `stampede-merger.agent.md` have no references to:
  - `collab/consensus.jsonl`
  - `adopted_consensus_item_ids`
  - `broadcasts.jsonl`
- **Impact:** Commander-level consensus doesn't influence merge decisions

❌ **Consensus tier not propagated**
- Commander bundles include `consensus.tier` (CONSENSUS/MAJORITY/CONFLICT/UNIQUE)
- Merger writes `merge-report.json` but doesn't aggregate consensus tiers
- **Missing:** Final report should indicate if multiple commanders converged or conflicted

---

### 3. Orchestrator Synthesis

**Location:** `skills/SKILL.md:568-640` (STEP 8 synthesis)

**What Synthesis Does:**
- ✅ Reads all result JSONs from `.stampede/{run_id}/results/`
- ✅ Detects file-level conflicts (multiple agents modified same file)
- ✅ Presents branches and conflict summary to user
- ✅ Offers auto-merge with shadow scoring

**Critical Gaps:**

❌ **Synthesis doesn't read consensus fields**
```python
# Current code (line 584-590):
result = json.load(f)
all_results.append(result)
for fp in result.get("files_changed", result.get("files_modified", [])):
    file_owners[fp].append(result.get("task_id", rf))
```
- Reads `files_changed` but ignores:
  - `consensus.tier`
  - `adopted_consensus_item_ids`
  - `broadcasts`
  - `confidence`

❌ **No cross-agent consensus aggregation**
- Synthesis prints per-task summaries but no meta-analysis of agreement
- **Missing:** Detect if multiple agents reached same conclusion vs. conflicting conclusions
- **Example use case:** 3 agents audit security, 2 say "safe", 1 says "vulnerable" → should flag disagreement

❌ **Conflict detection is file-based only**
- Current: "file X modified by task-001 and task-003" (line 593)
- **Missing:** Semantic conflict detection:
  - Same requirement implemented differently
  - Contradictory recommendations (agent A says "add feature", agent B says "remove feature")
  - Overlapping work (both agents added same function with different names)

---

### 4. Worker Agent Output Schema

**Location:** `agents/stampede-agent.agent.md:192-243`

**What Workers Write:**
```json
{
  "task_id": "...",
  "status": "done",
  "branch": "...",
  "files_changed": [...],
  "summary": "...",
  "confidence": 0.0  // ← Present but unused downstream
}
```

**Critical Gap:**

❌ **Workers have no consensus mechanism**
- Standard workers (`stampede-agent`) don't write:
  - `consensus` field
  - `votes` or agreement signals
  - References to other agents' work
- Workers are **hermetically sealed** — they don't read other workers' results
- **Impact:** No mechanism for workers to:
  - Signal agreement with another agent's approach
  - Flag conflicts with another agent's work
  - Propose synthesis across their work and others

---

### 5. Commander Bundle Schema

**Location:** `agents/stampede-commander.agent.md:240-267`

**What Commanders Write:**
```json
{
  "consensus": {
    "tier": "CONSENSUS | MAJORITY | CONFLICT | UNIQUE",
    "notes": []
  },
  "adopted_consensus_item_ids": [...],
  "broadcasts": [...],
  "source_refs": [...]
}
```

**What Works:**
- ✅ Commanders write rich consensus metadata
- ✅ Schema supports 4 consensus tiers
- ✅ Real data captured (verified in `commander-001.json`)

**Gap:**

❌ **No downstream consumer of commander consensus**
- Orchestrator synthesis (STEP 8) doesn't read these fields
- Merger agent doesn't aggregate consensus across commanders
- **Impact:** Commander consensus is documentation only, not actionable

---

## Gap Summary Table

| Component | Consensus Captured? | Consensus Merged? | Vote/Agreement? | Cross-Agent Review? |
|-----------|---------------------|-------------------|-----------------|---------------------|
| **Worker Agent** | ❌ No consensus field | N/A | ❌ No | ❌ No |
| **Commander Agent** | ✅ Yes (tier + items) | ❌ Not consumed | ⚠️ Via collab bus only | ✅ Via peer_review ledger |
| **Collaboration Bus** | ✅ Yes (5 ledgers) | ❌ Not consumed | ⚠️ Implicit via reviews | ✅ Yes (commander-only) |
| **Merger Agent** | ❌ Doesn't read consensus | ❌ No aggregation | ❌ No | ❌ No |
| **Orchestrator Synthesis** | ❌ Doesn't read consensus | ❌ No aggregation | ❌ No | ❌ No |
| **Final Output** | N/A | ❌ Consensus invisible | ❌ No | ❌ No |

---

## Recommended Remediation (Priority Order)

### P0: Critical (Required for consensus inclusion to work)

1. **Orchestrator synthesis must read commander consensus**
   - Location: `skills/SKILL.md:568-640`
   - Change: Parse `consensus`, `adopted_consensus_item_ids`, `broadcasts` from result JSONs
   - Output: Print consensus tier summary (e.g., "3 commanders reached CONSENSUS, 1 CONFLICT")

2. **Merger must aggregate consensus across branches**
   - Location: `bin/stampede-merge.sh:257-500`, `agents/stampede-merger.agent.md`
   - Change: Read consensus fields from each result JSON during scoring phase
   - Output: `merge-report.json` includes:
     - `consensus_summary`: Map of tiers (how many CONSENSUS/MAJORITY/CONFLICT/UNIQUE)
     - `adopted_items`: List of all adopted_consensus_item_ids across commanders
     - `conflicts_flagged`: Branches with conflicting consensus tiers

3. **Worker agents need lightweight consensus output**
   - Location: `agents/stampede-agent.agent.md:192-243`
   - Change: Add optional `agreement_signals` field:
     ```json
     {
       "agreement_signals": {
         "approach": "brief description of implementation strategy",
         "alternatives_considered": ["alt 1", "alt 2"],
         "confidence_in_approach": 0.85
       }
     }
     ```
   - Rationale: Allows post-hoc consensus detection without live coordination

### P1: High (Enables semantic consensus)

4. **Merger semantic conflict detection**
   - Location: `agents/stampede-merger.agent.md:138-173`
   - Change: After Phase 1 merge, add Phase 1.5:
     - Compare summaries and files_changed across agents
     - Detect overlapping objectives (same feature implemented twice)
     - Detect contradictory changes (one adds, another removes same concept)
   - Output: Flag semantic conflicts in merge-report.json

5. **Cross-agent diff analysis**
   - Location: `bin/stampede-merge.sh:257+`
   - Change: Before scoring, compare each branch pair for semantic overlap:
     ```python
     for i, branch_a in enumerate(branches):
         for branch_b in branches[i+1:]:
             overlap = detect_semantic_overlap(branch_a, branch_b)
             if overlap > 0.7:  # >70% similar intent
                 flag_for_deduplication(branch_a, branch_b)
     ```

6. **Orchestrator consensus voting**
   - Location: `skills/SKILL.md:568-640`
   - Change: After conflict detection, add consensus analysis:
     - Group agents by approach (cluster similar summaries)
     - Report majority/minority splits
     - Flag if agents reached contradictory conclusions

### P2: Medium (Improves observability)

7. **Live consensus dashboard**
   - Location: `bin/stampede-monitor.sh:57-66`
   - Change: In metaswarm runs, show consensus convergence:
     - % of proposals that reached consensus vs. conflict
     - Cross-commander agreement rate
   - Current: Only shows counts (proposals: 5, consensus: 3)
   - Desired: Show convergence (3/5 proposals → consensus, 0 conflicts)

8. **Collaboration bus reader utility**
   - New file: `bin/stampede-consensus-report.sh`
   - Purpose: Read all 5 ledgers, produce summary:
     - Consensus items by tier
     - Cross-references (which proposals led to which consensus)
     - Adoption status (which broadcasts were included in bundles)

### P3: Low (Nice to have)

9. **Worker result cross-references**
   - Location: `agents/stampede-agent.agent.md:192-243`
   - Change: After writing result, optionally read other completed results and append:
     ```json
     {
       "cross_references": {
         "similar_to": ["task-005"],
         "conflicts_with": ["task-003"],
         "builds_on": ["task-001"]
       }
     }
     ```
   - Rationale: Enables post-hoc graph of agent dependencies

10. **Merger consensus-aware conflict resolution**
    - Location: `agents/stampede-merger.agent.md:326-335`
    - Change: When resolving conflicts, if both branches reference same consensus item, prefer the approach that matches adopted consensus
    - Example: Both branches implement auth, one matches `cons-001-auth-strategy` → prefer that branch

---

## Code References

### Files with consensus writes:
- `bin/stampede.sh:670-720` — Creates collab bus and protocol.json
- `bin/stampede.sh:910` — Injects collab bus path into commander prompt
- `agents/stampede-commander.agent.md:254-256` — Bundle schema with consensus tier
- `.stampede/run-*/collab/*.jsonl` — Actual consensus data

### Files that should read consensus but don't:
- `skills/SKILL.md:568-640` — Synthesis step (STEP 8)
- `agents/stampede-merger.agent.md` — Entire agent (no collab/ references)
- `bin/stampede-merge.sh` — Merge script (no collab/ references)

### Search patterns to verify gaps:
```bash
# No references to collab in merger:
grep -i "collab\|consensus\|adopted" agents/stampede-merger.agent.md
# → 0 results (verified)

# No references to collab in merge script:
grep -i "collab\|consensus\|adopted" bin/stampede-merge.sh  
# → 0 results (verified)

# Synthesis doesn't parse consensus:
grep -n "consensus\|adopted" skills/SKILL.md
# → 0 results in STEP 8 synthesis code (verified)
```

---

## Verification Examples

### Metaswarm Run: run-20260430-180646

**Consensus Data Captured:**
- 5 proposals written to `collab/proposals.jsonl`
- 11 peer reviews written to `collab/reviews.jsonl`
- 7 improvements written to `collab/improvements.jsonl`
- 5 consensus items written to `collab/consensus.jsonl`
- 3 broadcasts written to `collab/broadcasts.jsonl`

**Commander Bundle Includes:**
```json
{
  "consensus": {
    "tier": "MAJORITY",
    "notes": ["3 blockers, 6 majors, 5 minors identified..."]
  },
  "adopted_consensus_item_ids": [
    "cons-c001-pre-build-blockers",
    "cons-c001-pre-build-majors",
    "cons-c001-pre-build-minors"
  ],
  "broadcasts": [
    "bcast-c001-adopt-blockers",
    "bcast-c001-adopt-majors"
  ]
}
```

**But:**
- ❌ No merger reads this data (no `merge-report.json` generated yet for this run)
- ❌ Orchestrator synthesis would print task summaries but not aggregate consensus
- ❌ User cannot easily answer: "Did all commanders agree on the findings?"

---

## Recommendations Summary

**Immediate action (P0):**
1. Add consensus parsing to `skills/SKILL.md` STEP 8 synthesis
2. Add consensus aggregation to `bin/stampede-merge.sh` scoring phase
3. Add lightweight consensus fields to worker agent schema

**High-value enhancements (P1):**
4. Semantic conflict detection in merger (beyond git conflicts)
5. Cross-agent diff analysis for duplicate work detection
6. Consensus voting/clustering in orchestrator

**Lower priority (P2-P3):**
7. Live consensus dashboard in monitor
8. Standalone consensus report utility
9. Worker cross-references
10. Consensus-aware conflict resolution

---

## Conclusion

Terminal Stampede has **excellent consensus capture infrastructure** (collaboration bus, structured ledgers, commander bundles with consensus tiers) but **zero consensus consumption**. The data is written but never read by downstream components.

**Impact:** Multi-agent agreement/conflict is invisible in final outputs. Users cannot answer:
- "Did all agents agree on the approach?"
- "Is there a minority opinion I should consider?"
- "Did agents do duplicate work?"

**Root cause:** Consensus was designed for metaswarm commanders but not integrated into merger/synthesis pipeline. Workers have no consensus mechanism at all.

**Fix effort:** ~2-3 days to add consensus reading to orchestrator + merger. Additional 5-7 days for semantic conflict detection and cross-agent voting.

---

**Audit complete.** No source modifications made per task constraints.
