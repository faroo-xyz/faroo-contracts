# Repository rules

Any task touching tbPROS, including `contracts/tbpros/`, `test/tbpros/`,
`docs/tbpros/`, `deploy/tbpros/`, `scripts/tbpros/`, `reference/tbpros/`,
or related reference models, MUST first read:

1. `contracts/tbpros/AGENTS.md`
2. `docs/tbpros/00-decision-register.md`
3. `docs/tbpros/README.md`

Protocol hard rules belong in `contracts/tbpros/AGENTS.md`; this file only routes
work. Report conflicts between the current specification and implementation.

`archive-*` files/directories are historical evidence only. Do not restore
superseded designs. Keep test probes separate from production contracts, run
checks appropriate to the change, and distinguish model results from deployment
or audit evidence. Never print RPC credentials or private keys.
