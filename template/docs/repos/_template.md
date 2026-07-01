# {{repo-name}} — {{one-line purpose}}

<!-- TEMPLATE: the Tier-1 reference for one linked repo/service — what it is and what an
     agent must know before touching it (see docs/service-catalog.md for the tiers). Copy to
     <repo-name>.md, one per linked repo. Delete the whole docs/repos/ directory for a
     single-repo project. Keep it DENSE; front-load *where things live* and *gotchas* — that's
     what removes friction. Most repos need only the top block + "What it does"; add the
     deeper sections for services on the critical path. Remove TEMPLATE comments as you go. -->

- **Runs as:** {{chart / deploy target · image · replicas/scaling}}
- **Source:** `repos/{{repo-name}}` (clone dir `{{clone-dir}}` if it differs) · **stack:** {{lang/framework}}
- **GitHub:** [{{ORG}}/{{repo-name}}](https://github.com/{{ORG}}/{{repo-name}}) · default branch `{{main}}` · **kind:** {{service | infra | web | lib | gitops | …}}
- **Status / gap:** {{deployed? which invariants apply (link the ADR)? known debt?}}

> _{{Confirmed = read from source on {{date}}; inferred items marked. Verify before relying
> on specifics.}}_

## What it does

{{2–4 sentences: its role in {{PROJECT_NAME}} and the surfaces/APIs it owns.}}

## What an agent must know

<!-- TEMPLATE: the project-specific facts that aren't obvious from the code — invariants that
     apply here, deploy quirks, naming exceptions, "don't touch X". Link the relevant ADR. -->

- {{Key constraint / invariant specific to this repo.}}
- {{Where its deploy values / config / secrets live, if separate.}}

<!-- TEMPLATE: add these deeper sections for critical-path services; delete them otherwise.

## Contracts & protocols
{{APIs exposed / consumed: REST/gRPC/proto, queues/exchanges, events, ports.}}

## Dependencies
{{DBs, queues, buckets, other services, secret paths.}}

## Config
{{Key flags, where values live, per-env differences.}}

## Source map
{{The 5–10 files to read first.}}

## Open questions / inferred-vs-confirmed
{{What you couldn't verify from source.}}
-->
