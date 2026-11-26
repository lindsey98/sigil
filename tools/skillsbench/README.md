# Test pass rate via SkillsBench

The paper's **test pass rate** ("Task Macro Pass Rate") is each task's own
verifier passing. That lives in **[SkillsBench](https://github.com/benchflow-ai/skillsbench)**,
not here. There is no official hook for a compiled Sigil artifact, so there are
two honest paths.

## Path A — the paper's comparison (turnkey)

SkillsBench runs a model **with** the skill vs **without** it and reports `reward`
(1/0) per task. This is the SKILL.md-as-prompt baseline the paper measures against
— no Sigil artifact involved, fully supported by `bench`:

```bash
# Python 3.12
git clone https://github.com/benchflow-ai/skillsbench && cd skillsbench
uv tool install benchflow && uv sync --locked
export ANTHROPIC_API_KEY=...          # or the agent/model you use

# with the skill:
bench eval run --tasks-dir tasks/<task> --agent claude-agent-acp --model <model> \
  --skill-mode with-skill --skills-dir tasks/<task>/environment/skills/ --sandbox docker
# baseline, no skill:
bench eval run --tasks-dir tasks/<task> --agent claude-agent-acp --model <model> \
  --skill-mode no-skill --sandbox docker
```

Macro pass rate = mean `reward` across the task set. Run both arms over many tasks
to reproduce the paper's "with vs without skill" gain.

## Path B — score a COMPILED Sigil artifact (template)

To score the *compiled* artifact (not SKILL.md-as-prompt), run it inside the
task's own image and run the task's real verifier — the direct-run method in
[`docs/skillsbench-compiler-bugs.md`](../../docs/skillsbench-compiler-bugs.md).
SkillsBench exposes no custom-agent plugin, so the one task-specific step — how
the agent reads the task and where it writes the deliverable — is yours to bind.
`direct_run.sh` is a **template** with that step marked `TODO`:

```bash
sigil compile ./tasks/<task>/environment/skills/<skill>/SKILL.md -e agent.jac
./tools/skillsbench/direct_run.sh tasks/<task> agent.jac
```

It builds the task image, runs the agent, runs `verifier/test.sh`, and prints the
`reward`. Adapt the `TODO` line to the task's I/O contract (SkillsBench task
layout: `task.md`, `environment/`, `oracle/solve.sh`, `verifier/`).

## The other two metrics

`skill adherence` and `token cost` do **not** come from SkillsBench — get them
from `src/eval_metrics.jac` (see the repo README, "Reproducing the paper's
numbers"). Token cost is also not reported by SkillsBench's `reward`.
