"""debug_pipeline.jac — watch the compiler's BACK-END, one stage at a time.

What this shows (deterministic half — NO model, NO API key needed):

    AG-IR text  ->  load_agir()  ->  validation gates  ->  transpile_ir()  ->  COMPILE oracle
      (input)        (parse)          (checks)             (JAC output)        (lower + jac check)

It runs on an AG-IR that already exists on disk (examples/*/*.agir), i.e. the
thing the AI front-end produced from a SKILL.md. The FRONT-END half
(SKILL.md -> AG-IR) needs a model; to run the whole pipeline on a real skill and
emit a visualizer bundle, use src/export_bundle.jac instead.

Run it from the repo root:

    SIGIL_JAC=<path-to-jac> jac run src/debug_pipeline.jac

Pick a different example with an env var:

    SIGIL_DEBUG_EXAMPLE=writing-plans jac run src/debug_pipeline.jac
"""

import os;
import from src.sigil_agir_yaml { load_agir }
import from src.compiler.mechanical.compiler { transpile_ir }
import from src.compiler.ai.gates {
    compile_gate,
    gate_env_binding,
    gate_input_provenance,
    gate_constraints,
    gate_type_unification,
    gate_concurrency
}

def banner(title: str) -> None {
    print("\n" + ("=" * 72));
    print("  " + title);
    print("=" * 72);
}

def head(text: str, n: int) -> str {
    if len(text) <= n { return text; }
    return text[:n] + "\n... (" + str(len(text) - n) + " more chars)";
}

with entry {
    # ---- which example (an .agir that the front-end already produced) ----
    ex = os.environ.get("SIGIL_DEBUG_EXAMPLE", "csv-clean");
    # map example dir -> (agir filename, the module name used when lowering)
    cfg = {
        "csv-clean": ("csv-clean.agir", "clean_csv"),
        "writing-plans": ("writing-plans.agir", "writing_plans"),
    };
    (agir_file, name) = cfg.get(ex, (ex + ".agir", ex.replace("-", "_")));
    agir_path = os.path.join("examples", ex, agir_file);

    print("example   : " + ex);
    print("agir file : " + agir_path);
    print("lower name: " + name);

    with open(agir_path) as f { ir_text = f.read(); }

    # ---- STEP 1: the AG-IR (front-end OUTPUT = back-end INPUT) ----
    banner("STEP 1  AG-IR text  (what the AI front-end emitted; input to everything below)");
    print(head(ir_text, 1600));

    # ---- STEP 2: parse the IR text into a dict ----
    ir = load_agir(ir_text);
    wf = ir.get("walker", {}) or {};
    nodes = ir.get("nodes", []) or [];
    banner("STEP 2  load_agir()  -> parsed IR structure");
    print("top-level keys : " + str(list(ir.keys())));
    print("shape          : " + str(ir.get("shape")));
    print("walker         : " + str(wf.get("name")));
    print("carries        : " + str(list((wf.get("carries") or {}).keys())));
    print("node ids       : " + str([n.get("id") for n in nodes]));
    print("");
    print("node details (id | type | reads -> writes):");
    for n in nodes {
        print("  - " + str(n.get("id"))
            + "  [" + str(n.get("type")) + "]  "
            + str(n.get("reads") or []) + " -> " + str(n.get("writes") or []));
    }

    # ---- STEP 3: validation gates (deterministic, text-level, no model) ----
    banner("STEP 3  validation gates on the IR  (empty list/no-finding = clean)");
    print("gate_env_binding      : " + str(gate_env_binding(ir_text)));
    print("gate_input_provenance : " + str(gate_input_provenance(ir_text)));
    print("gate_constraints      : " + str(gate_constraints(ir_text)));
    print("gate_type_unification : " + str(gate_type_unification(ir_text)));
    print("gate_concurrency      : " + str(gate_concurrency(ir_text)));

    # ---- STEP 4: lower the IR into JAC source ----
    jac_src = str(transpile_ir(ir_text, name));
    banner("STEP 4  transpile_ir()  -> lowered JAC source  (the OUTPUT)");
    print(head(jac_src, 1600));

    # write the full lowered module out so you can diff it against the shipped one
    out_path = os.path.join("examples", ex, "_debug_lowered.jac");
    with open(out_path, "w") as f { f.write(jac_src); }
    print("\nfull lowered module written to: " + out_path);
    print("compare with the shipped one:   diff " + out_path
        + " examples/" + ex + "/" + name.replace("_", "-") + ".jac");

    # ---- STEP 5: the COMPILE oracle (lower + `jac check`) ----
    banner("STEP 5  compile_gate()  -> COMPILE oracle: does the lowered module type-check?");
    v = compile_gate(ir_text, name);
    print("ok     : " + str(v.ok));
    if not v.ok { print("errors :\n" + str(v.errors)); }
    else { print("(the lowered module passed `jac check` with zero errors)"); }

    banner("done");
}
