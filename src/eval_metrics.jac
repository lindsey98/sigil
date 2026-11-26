"""eval_metrics.jac — run ONE compiled skill on a task and print two of the
paper's three metrics, directly: SKILL ADHERENCE and TOKEN COST.

    jac run src/eval_metrics.jac -- <SKILL.md> "<task prompt>" [out.json]

What it does, and how each number is produced (honest about fidelity):

  - compile the skill (LIFT front-end, needs a model),
  - extract its MANDATORY obligations from the SKILL.md text (extract_spec),
  - run the compiled module on the task (execute_module), capturing its report
    and its per-call token log (observability/live.jsonl),
  - TOKEN COST  = sum of prompt/completion/reasoning tokens (+ litellm cost_usd)
    over that log — this is exact, it is the runtime's own accounting.
  - SKILL ADHERENCE = fraction of applicable MANDATORY obligations an LLM judge
    says the run realized, judging each against (task, the run's report). This
    APPROXIMATES the paper (GPT-5 judge over task + harness + full trace vs a
    reviewed reference DAG, Appendix D): here the mandates come from the skill's
    own text, and the judge sees the final report rather than the node trace.

The third metric, TEST PASS RATE, needs a task's real verifier — that is
SkillsBench's job; see tools/skillsbench/.

Models: the run uses $SIGIL_MODEL (else $SIGIL_SMALL); the judge uses $SIGIL_JUDGE
(else gpt-5). Connect a model first (keys / relay in .env). UNTESTED in CI —
verify the first run, and if token cost is 0 your compiled runtime did not write
the obs log (check $SIGIL_OBS support).
"""

import os;
import sys;
import json;
import tempfile;
import from src.compiler.ai.lift { lift }
import from src.compiler.ai.spec_loop { extract_spec }
import from src.sigil_runtime { execute_module, OBS_LOG }
import from jaclang.byllm.lib { Model }

glob judge_llm: any = Model(model_name=os.getenv("SIGIL_JUDGE", "gpt-5"));

obj MandateVerdict {
    has realized: bool = False;
    has reason: str = "";
}

"""Judge whether the run REALIZED this one mandatory obligation from the skill.
Base the verdict only on evidence in the run output; absence of evidence is NOT
realized."""
def judge_mandate(mandate: str, task: str, run_output: str) -> MandateVerdict by judge_llm();

def _name_of(path: str) -> str {
    base = os.path.basename(path);
    stem = base[:-3] if base.endswith(".md") else base;
    return stem.replace("-", "_").replace(" ", "_").lower();
}

def _sum_tokens(obs_path: str) -> dict[str, any] {
    agg = {"calls": 0, "prompt_tokens": 0, "completion_tokens": 0,
           "reasoning_tokens": 0, "total_tokens": 0, "cost_usd": 0.0};
    if not os.path.exists(obs_path) { return agg; }
    with open(obs_path) as f {
        for line in f {
            line = line.strip();
            if not line { continue; }
            try { rec = json.loads(line); } except Exception as e { continue; }
            agg["calls"] += 1;
            for k in ["prompt_tokens", "completion_tokens", "reasoning_tokens", "total_tokens"] {
                agg[k] += int(rec.get(k, 0) or 0);
            }
            agg["cost_usd"] += float(rec.get("cost_usd", 0) or 0.0);
        }
    }
    return agg;
}

with entry {
    argv = [a for a in sys.argv];
    rest = argv[argv.index("--") + 1:] if "--" in argv else argv[1:];
    if len(rest) < 2 {
        print("usage: jac run src/eval_metrics.jac -- <SKILL.md> \"<task>\" [out.json]");
    } else {
        skill_path = rest[0];
        task = rest[1];
        out_path = rest[2] if len(rest) > 2 else "";
        name = _name_of(skill_path);
        with open(skill_path) as f { skill = f.read(); }

        print("[1/4] compiling " + name + " (LIFT, model) …");
        lr = lift(skill, name);
        if not lr.ok {
            print("compile failed: " + str(lr.status));
        } else {
            wd = tempfile.mkdtemp(prefix="sigil_eval_");
            module_path = os.path.join(wd, name + ".jac");
            with open(module_path, "w") as f { f.write(lr.module_src); }

            print("[2/4] extracting MANDATORY obligations …");
            sr = extract_spec(skill, name);
            mandates = [r for r in sr.spec.rules if r.modality.name == "MANDATORY"];
            print("      " + str(len(mandates)) + " mandatory obligations");

            print("[3/4] running on the task …");
            run_model = os.getenv("SIGIL_MODEL", "") or os.getenv("SIGIL_SMALL", "ollama_chat/qwen3:32b");
            res = execute_module(module_path, task, run_model, name, wd);
            report = str(res.get("report", ""));
            tokens = _sum_tokens(os.path.join(wd, OBS_LOG));

            print("[4/4] judging adherence over " + str(len(mandates)) + " obligations …");
            per = [];
            passed = 0;
            for m in mandates {
                v = judge_mandate(m.quote, task, report);
                if v.realized { passed += 1; }
                per.append({"id": m.id, "quote": m.quote, "realized": v.realized, "reason": v.reason});
            }
            adherence = (float(passed) / float(len(mandates))) if mandates else 1.0;

            result = {
                "skill": name,
                "task": task,
                "run_ok": bool(res.get("ok", False)),
                "skill_adherence": round(adherence, 4),
                "mandates_realized": str(passed) + "/" + str(len(mandates)),
                "token_cost": tokens,
                "per_mandate": per,
            };
            print("\n==================== RESULT ====================");
            print("skill_adherence : " + str(round(adherence, 4))
                  + "  (" + str(passed) + "/" + str(len(mandates)) + " mandatory obligations)");
            print("token_cost      : " + str(tokens["total_tokens"]) + " tokens over "
                  + str(tokens["calls"]) + " calls  ($" + str(round(tokens["cost_usd"], 4)) + ")");
            print("test_pass_rate  : (run via tools/skillsbench — needs the task verifier)");
            if out_path {
                with open(out_path, "w") as f { json.dump(result, f, indent=2); }
                print("full detail -> " + out_path);
            }
        }
    }
}
