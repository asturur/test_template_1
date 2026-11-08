# Rejected ZAP timing experiments

These patches are retained as evidence and are **not** part of the active
`patches/zap/[0-9]*.patch` series or `UPSTREAM.json` modifications.

- `0049-late-owner-forwarding.patch`: functionally/cycle equivalent, but routed
  fit42520603079 regressed pointer→issue to−1.607ns, execute→issue to−1.872ns,
  total negative setup slack to−4933.783ns and Fmax to77.97MHz. Active RTL was
  restored to patch0048 without rewriting Git history. See timing-closure.md
  and cpu-operand-stage-contract.md for evidence; do not reapply by default.
