"""debug_pipeline.py — drive the compiler BACK-END from plain Python, so you can
set PyCharm breakpoints on these lines and inspect every intermediate value.

Why this works: jaclang installs an import hook when you `import jaclang`, after
which `.jac` modules import like normal Python modules. So you never install
Sigil as a package — you run it straight from this checkout.

    AG-IR text -> load_agir() -> validation gates -> transpile_ir() -> COMPILE oracle
      (input)      (parse)        (checks)            (JAC output)      (lower + jac check)

Prereqs (run from the repo root, in a venv):
    pip install 'jaclang==0.37.25' pyyaml      # minimal: steps 1-4
    # (step 5 shells out to `jac check`, which the jaclang install provides)

Run / debug:
    python debug_pipeline.py
    SIGIL_DEBUG_EXAMPLE=writing-plans python debug_pipeline.py

To stop INSIDE the compiler's own code (e.g. watch transpile_ir build the
module node by node), drop a `breakpoint();` line into that .jac function and
run `jac run src/debug_pipeline.jac` — pdb will halt there. PyCharm breakpoints
set in THIS file stop at the driver level.
"""

import os

import jaclang  # noqa: F401 -- registers the .jac import hook; MUST come first

# These are the real compiler functions, imported from source (not a package):
from src.sigil_agir_yaml import load_agir                 # IR text -> dict
from src.compiler.mechanical.compiler import transpile_ir  # IR -> JAC source (LOWER)
from src.compiler.ai.gates import (                        # validation
    compile_gate,
    gate_env_binding,
    gate_input_provenance,
    gate_constraints,
    gate_type_unification,
    gate_concurrency,
)

EXAMPLES = {
    "csv-clean": ("csv-clean.agir", "clean_csv"),
    "writing-plans": ("writing-plans.agir", "writing_plans"),
}


def banner(title: str) -> None:
    print("\n" + "=" * 72 + f"\n  {title}\n" + "=" * 72)


def head(text: str, n: int) -> str:
    return text if len(text) <= n else text[:n] + f"\n... ({len(text) - n} more chars)"


def main() -> None:
    ex = os.environ.get("SIGIL_DEBUG_EXAMPLE", "csv-clean")
    agir_file, name = EXAMPLES.get(ex, (f"{ex}.agir", ex.replace("-", "_")))
    agir_path = os.path.join("examples", ex, agir_file)
    print(f"example={ex}  agir={agir_path}  lower-name={name}")

    with open(agir_path) as f:
        ir_text = f.read()

    # STEP 1 — the AG-IR the AI front-end produced (input to everything below)
    banner("STEP 1  AG-IR text")
    print(head(ir_text, 1600))

    # STEP 2 — parse it  (set a breakpoint on the next line to inspect `ir`)
    ir = load_agir(ir_text)
    wf = ir.get("walker", {}) or {}
    nodes = ir.get("nodes", []) or []
    banner("STEP 2  load_agir() -> parsed structure")
    print("keys    :", list(ir.keys()))
    print("shape   :", ir.get("shape"))
    print("walker  :", wf.get("name"))
    print("carries :", list((wf.get("carries") or {}).keys()))
    for n in nodes:
        print(f"  - {n.get('id')} [{n.get('type')}]  "
              f"{n.get('reads') or []} -> {n.get('writes') or []}")

    # STEP 3 — validation gates (deterministic; [] == clean)
    banner("STEP 3  validation gates")
    print("env_binding      :", gate_env_binding(ir_text))
    print("input_provenance :", gate_input_provenance(ir_text))
    print("constraints      :", gate_constraints(ir_text))
    print("type_unification :", gate_type_unification(ir_text))
    print("concurrency      :", gate_concurrency(ir_text))

    # STEP 4 — lower IR -> JAC  (breakpoint here, then step into transpile_ir)
    jac_src = str(transpile_ir(ir_text, name))
    banner("STEP 4  transpile_ir() -> lowered JAC source")
    print(head(jac_src, 1600))
    out_path = os.path.join("examples", ex, "_debug_lowered.jac")
    with open(out_path, "w") as f:
        f.write(jac_src)
    print(f"\nfull module -> {out_path}")
    print(f"diff {out_path} examples/{ex}/{name.replace('_', '-')}.jac")

    # STEP 5 — COMPILE oracle: lower + `jac check`
    banner("STEP 5  compile_gate() -> COMPILE oracle")
    v = compile_gate(ir_text, name)
    print("ok    :", v.ok)
    if not v.ok:
        print("errors:\n" + str(v.errors))


if __name__ == "__main__":
    main()
