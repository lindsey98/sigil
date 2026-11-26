# Sigil Pipeline Explorer

A single self-contained HTML page that visualizes one compiled skill across the
four compiler stages, with linked highlighting (click anything → everything that
corresponds lights up, like a cross-reference / code-diff view):

```
SKILL.md ──▶ Requirements ──▶ AG-IR (dependency graph) ──▶ JAC
 (source)     (the contract)     (click a node → params      (each node's lines)
                                   + source span)
                          └── Validation (AG-IR → JAC): pass, or WHY it failed
```

## Open it

Just open `index.html` in a browser (double-click, or `file://…/index.html`).
No server, no build, no dependencies — the demo data is inlined.

Interactions:
- Click a **requirement** → highlights its verbatim span in SKILL.md, the AG-IR
  nodes that `traces_to` it, and those nodes' JAC lines.
- Click an **AG-IR node** → detail box shows its `reads`/`writes` and the SKILL.md
  it traces to; highlights the requirement + source + JAC for it.
- Click a **JAC line** → selects its node (same cross-highlight).
- Click a **validation finding** → highlights the node / requirement it breaks.
- Top-right dropdown switches between the **passing** and **failing** demo.

## The data is synthetic (for now)

The two demo bundles are hand-authored so every cross-link is correct by
construction — the point is to see the *mechanism*. The requirement→source and
node→requirement links mirror real compiler data:
- each `rule.quote` is a **verbatim** span of `skill_md` (the grounding gate
  guarantees that in a real compile), so the source highlight is a substring match;
- each AG-IR node carries `traces_to: [rule_id, …]` (real field in `.agir`);
- node→JAC lines come from `#@node <id>` anchors in the `jac` text.

## Wiring in a REAL skill later

Use the **"load bundle.json"** button to drop in a bundle emitted from the
compiler. The schema (also commented at the top of `index.html`):

```jsonc
{
  "skill_name": "…",
  "skill_md":   "the SKILL.md source text",
  "rules":      [ { "id":"r1", "quote":"VERBATIM span of skill_md",
                    "kind":"STEP|CONSTRAINT|IO|KNOWLEDGE|HIL",
                    "modality":"MANDATORY|DISCRETIONARY|FORBIDDEN",
                    "statement":"…", "condition":"…" } ],
  "agir": {
    "shape": "pipeline",
    "nodes": [ { "id":"…", "type":"OBSERVE|COMPUTE|ACT|HIL|EXTRACT",
                 "doc":"…", "reads":["carry"], "writes":["carry"],
                 "traces_to":["r1"] } ],
    "edges": [ { "src":"…", "dst":"…", "guard":"…" } ]
  },
  "jac": "lowered JAC; mark each node block with `#@node <id>` … `#@end`",
  "validation": {
    "ok": true,
    "findings": [ { "gate":"…", "severity":"error|warning|info",
                    "title":"…", "explain":"…",
                    "node":"…", "rule":"…", "carry":"…" } ],
    "compile": { "ok": true, "errors": "" }
  }
}
```

Where the real data comes from in the codebase:
- `rules` — `extract_spec` / the spec loop (`src/compiler/ai/spec_loop.jac`,
  `Rule` has `id/quote/kind/modality/condition`). **Needs a model.**
- `agir` — the lifted AG-IR (`src/compiler/ai/lift.jac` → `.ir_text`; parsed by
  `src/sigil_agir_view.jac:parse_agir`). **Needs a model** (SKILL.md → AG-IR).
- `jac` — `transpile_ir(ir_text, name)` in
  `src/compiler/mechanical/compiler.jac`. Deterministic, no model.
- `validation` — the gate battery in `src/compiler/ai/gates.jac`
  (`compile_gate`, `gate_type_unification`, `gate_env_binding`, …). Deterministic.

See also `src/debug_pipeline.jac` — a step-by-step dumper that prints each
back-end stage's I/O without a model (`jac run src/debug_pipeline.jac`); drop a
`breakpoint();` in it or in the compiler's `.jac` to step through in pdb.
