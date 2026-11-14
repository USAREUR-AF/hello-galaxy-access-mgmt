# AGENTS.md

Instructions for AI coding agents, and a short version for anyone working here. [CONTRIBUTING.md](CONTRIBUTING.md) is the full process.

## What this repository is

hello-galaxy-access-mgmt demonstrates how a goat data fabric manages an identity over its lifetime: rotating a live actor's credential, then detecting and revoking a misbehaving one. Each scenario is a runbook and one script that drives the `goat` CLI against a local Zenoh router.

It is one of the Hello Galaxy demonstrations: small, runnable examples, each showing one part of [goat](https://github.com/USAREUR-AF/goatcore). It holds no goat source code.

## Layout

| Path | What |
|---|---|
| `scenarios/` | one directory per scenario: `README.md` and `run.sh` |
| `bin/access-mgmt` | the runner: `list`, one scenario, or `all` |
| `lib/` | shared shell functions |
| `local-fabric/` | a local router in Docker Compose: `up.sh`, `down.sh`, certificates, router configuration |
| `report/` | the HTML report and its generator |
| `docs/` | background, including `honesty-matrix.md`: what runs for real and what does not |

## Before you push

CI (`.github/workflows/ci.yml`) runs these. The second block needs Docker and the `goat` CLI on `PATH`; CI uses the release named by `GOAT_CLI_RELEASE` in that workflow.

```bash
shellcheck -e SC1090,SC1091,SC2086,SC2046,SC2034,SC2010,SC2164 \
  lib/access-mgmt.sh local-fabric/lib-fabric.sh bin/access-mgmt \
  scenarios/*/run.sh local-fabric/*.sh report/generate-report.sh
bin/access-mgmt list
```

```bash
local-fabric/up.sh
bin/access-mgmt all --env local
local-fabric/down.sh
```

Every directory under `scenarios/` holds a `README.md` and an executable `run.sh`; CI checks both.

## Rules

1. **Nothing from a real deployment.** No hostname, domain, address, key or person of a real goatnet goes into a file or a commit message. Use made-up names, documentation addresses (RFC 5737) and `example.org` mail.
2. **Commits.** Conventional Commits subject of 100 characters or fewer, with a scope (`fix(<component>): …`). Every commit is signed off (`git commit -s`, the DCO) and signed with a key GitHub verifies. The organization's required check `verified-commits` refuses a pull request that holds an unverified commit.
3. **One logical change per pull request.**
4. **Vulnerabilities** go through [SECURITY.md](SECURITY.md), never a public issue.

The contribution guide for goat as a whole is [goatcore CONTRIBUTING.md](https://github.com/USAREUR-AF/goatcore/blob/main/CONTRIBUTING.md).
