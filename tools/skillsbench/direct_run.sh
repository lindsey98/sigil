#!/usr/bin/env bash
# direct_run.sh — score ONE compiled Sigil artifact on ONE SkillsBench task by
# the direct-run method (docs/skillsbench-compiler-bugs.md): run the artifact
# inside the task's own image, then run the task's real verifier and read reward.
#
#   ./direct_run.sh <task-dir> <ejected-agent.jac>
#
# Prereqs: Docker; an ejected agent  (sigil compile ./SKILL.md -e agent.jac).
#
# TEMPLATE: SkillsBench has no official hook for a custom/compiled agent, so the
# task-specific step — how the agent is invoked on the task and WHERE it must
# write the deliverable the verifier checks — is marked TODO below. Fill it from
# the task's own files (task.md / oracle/solve.sh show the contract) before this
# produces a real number.
set -euo pipefail

TASK_DIR="${1:?usage: direct_run.sh <task-dir> <agent.jac>}"
AGENT="${2:?usage: direct_run.sh <task-dir> <agent.jac>}"
[ -d "$TASK_DIR/environment" ] || { echo "no $TASK_DIR/environment (not a SkillsBench task?)" >&2; exit 1; }
[ -f "$AGENT" ] || { echo "no agent at $AGENT (run: sigil compile ./SKILL.md -e agent.jac)" >&2; exit 1; }

IMG="skillsbench-$(basename "$TASK_DIR" | tr '[:upper:]' '[:lower:]')"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cp "$AGENT" "$WORK/agent.jac"

echo "[1/3] building task image ($IMG) …"
docker build -q -t "$IMG" "$TASK_DIR/environment" >/dev/null

echo "[2/3] running the compiled agent on the task …"
# The task prompt (SkillsBench tasks carry it in task.md, usually under a
# frontmatter block). Pass it to the agent however this task expects.
PROMPT_FILE="$TASK_DIR/task.md"
# -------------------------------------------------------------------------
# TODO (task-specific): run /work/agent.jac on the task prompt so it writes the
# deliverable to the path the verifier reads. Example scaffold:
#
#   docker run --rm -v "$WORK:/work" -e SIGIL_MODEL="${SIGIL_MODEL:-gpt-4o-mini}" \
#     "$IMG" bash -lc '/work/agent.jac "'"$(cat "$PROMPT_FILE")"'" > /work/output'
#
# then place /work/output where <task>/verifier expects it.
# -------------------------------------------------------------------------
echo "    (fill the TODO in $0 for this task's I/O contract)" >&2

echo "[3/3] running the task verifier …"
# SkillsBench writes the scalar reward (1/0) to the verifier's reward file.
docker run --rm -v "$WORK:/work" "$IMG" bash -lc '
  if [ -f /verifier/test.sh ]; then bash /verifier/test.sh || true; fi
  cat /logs/verifier/reward.txt 2>/dev/null || echo "reward: (verifier did not write one — check the TODO above)"
'
