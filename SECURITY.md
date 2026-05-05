# Security Policy

## Supported Scope

Agent Orchestra is a multi-agent fleet conductor for the GitHub Copilot CLI.
Security fixes should target:

- setup scripts and helper launchers in this repository
- copied Agent Pulse source under `agent-pulse-current/`
- commander-group run artifacts when they expose sensitive data or unsafe
  defaults

Runtime fixes should preserve commander groups, sub-agent telemetry, live
collaboration ledgers, Agent Pulse observability, and sealed Shadow Score
evaluation.

## Reporting a Vulnerability

Do not create a public issue for vulnerabilities. Use GitHub private
vulnerability reporting for this repository:

https://github.com/DUBSOpenHub/agent-orchestra/security/advisories/new

Include:

- a short description
- steps to reproduce
- affected files or artifacts
- potential impact
- suggested fix, if known

## Security Activation

Run this from a checked-out repo after `gh auth login`:

```bash
./scripts/activate-security.sh
```

The script enables repository security settings that do not require adding
workflow files. CI and CodeQL workflow templates are kept in
`archived-workflows/root/workflows/` until the pushing token has GitHub
`workflow` scope.
