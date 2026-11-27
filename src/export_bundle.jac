"""export_bundle.jac — compile ONE real skill and emit the visualizer bundle.

    jac run src/export_bundle.jac -- <SKILL.md> [out.json | out.html]

Runs the full pipeline on a specific skill and writes the visualizer data. With
an .html out name it inlines the data into the explorer template and writes ONE
self-contained page (scp it back and just open it); otherwise it writes a
bundle.json that tools/pipeline-explorer/index.html loads via "load bundle.json":

    SKILL.md --extract_spec--> rules (contract, with verbatim quotes)
             --lift----------> AG-IR (ir_text) + lowered JAC + validation findings

The LIFT front-end calls a model, so connect one first (keys / relay base URL in
`.env`: OPENAI_API_KEY + OPENAI_API_BASE; the default slot model is gpt-4o-mini).
The deterministic parts (load_agir / transpile_ir / compile_gate) need no model —
see src/debug_pipeline.jac to watch just those.

NOTE: untested in CI; verify the first bundle it writes. The back-end `can n_<id>`
blocks are mapped to nodes by the viewer directly, so no anchors are injected.
"""

import os;
import sys;
import json;
import from src.sigil_agir_yaml { load_agir }
import from src.compiler.ai.spec_loop { extract_spec }
import from src.compiler.ai.lift { lift, pin_all_lift_llms }
import from src.compiler.ai.gates { compile_gate }
import from jaclang.byllm.lib { Model }

def _name_of(path: str) -> str {
    base = os.path.basename(path);
    stem = base[:-3] if base.endswith(".md") else base;
    return stem.replace("-", "_").replace(" ", "_").lower();
}

with entry {
    # jac's sys.argv is [prog, "run", "<script>", <user args...>] and it strips the
    # "--" separator, so find our own script and take everything after it.
    av = [str(a) for a in sys.argv];
    _s = 1;
    for _i in range(len(av)) { if av[_i].endswith("export_bundle.jac") { _s = _i + 1; break; } }
    args = av[_s:];
    if args and args[0] == "--" { args = args[1:]; }
    if not args {
        print("usage: jac run src/export_bundle.jac -- <SKILL.md> [out.json | out.html]");
    } else {
        skill_path = args[0];
        out_path = args[1] if len(args) > 1 else "bundle.json";
        name = _name_of(skill_path);
        with open(skill_path) as f { skill = f.read(); }

        # pick the compile model: $SIGIL_MODEL overrides the built-in default
        # (gpt-4o-mini). With a relay set via $OPENAI_API_BASE, this is the model
        # NAME sent there, so set it to one your relay serves (e.g. openai/gpt-4o-mini).
        _m = os.getenv("SIGIL_MODEL", "");
        if _m { pin_all_lift_llms(Model(model_name=_m)); print("model: " + _m); }

        print("[1/4] extracting the contract (spec loop, model) …");
        sr = extract_spec(skill, name);
        rules = [
            {
                "id": r.id, "quote": r.quote,
                "kind": r.kind.name, "modality": r.modality.name,
                "statement": r.statement, "condition": r.condition,
            }
            for r in sr.spec.rules
        ];
        print("      " + str(len(rules)) + " rules");

        print("[2/4] lifting to AG-IR + lowering to JAC (model) …");
        lr = lift(skill, name);
        ir = load_agir(lr.ir_text);
        nodes = ir.get("nodes", []) or [];
        edges = [
            {"src": e.get("from"), "dst": e.get("to"),
             "guard": e.get("guard", "") or ""}
            for e in (ir.get("edges", []) or [])
        ];
        print("      " + str(len(nodes)) + " nodes, lift ok=" + str(lr.ok));

        print("[3/4] running the COMPILE oracle …");
        cg = compile_gate(lr.ir_text, name);

        findings = [
            {"gate": str(fd.get("gate", "")), "severity": str(fd.get("severity", "warning")),
             "title": str(fd.get("gate", "finding")), "explain": str(fd.get("message", ""))}
            for fd in (lr.findings or [])
        ];

        bundle = {
            "skill_name": name,
            "skill_md": skill,
            "rules": rules,
            "agir": {"shape": ir.get("shape", ""), "nodes": nodes, "edges": edges},
            "jac": lr.module_src,
            "validation": {
                "ok": bool(lr.ok and cg.ok),
                "findings": findings,
                "compile": {"ok": cg.ok, "errors": cg.errors},
            },
        };

        print("[4/4] writing " + out_path + " …");
        if out_path.endswith(".html") {
            # self-contained page: inline the bundle into the explorer template at
            # its <!-- EMBED --> marker, so the one file opens with the data baked in.
            tpl_path = os.path.join("tools", "pipeline-explorer", "index.html");
            with open(tpl_path) as f { tpl = f.read(); }
            embed = "<script>window.__EMBEDDED_BUNDLE__ = " + json.dumps(bundle) + ";</script>";
            with open(out_path, "w") as f { f.write(tpl.replace("<!-- EMBED -->", embed, 1)); }
            print("done. self-contained page -> " + out_path + "  (scp it back and just open it)");
        } else {
            with open(out_path, "w") as f { json.dump(bundle, f, indent=2); }
            print("done. open tools/pipeline-explorer/index.html and load " + out_path);
        }
    }
}
