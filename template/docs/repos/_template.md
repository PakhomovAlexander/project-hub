# {{repo-name}}

<!-- TEMPLATE: a short orientation doc for one linked repo — what it is and what an agent
     must know before touching it. Copy to <repo-name>.md, one per linked repo. Delete the
     whole docs/repos/ directory for a single-repo project. Keep it brief; depth lives in
     the repo itself. -->

{{One or two sentences: what this repo is and its role in {{PROJECT_NAME}}.}}

- **GitHub:** [{{ORG}}/{{repo-name}}](https://github.com/{{ORG}}/{{repo-name}}) · default branch `{{main}}`
- **Linked as:** `repos/{{repo-name}}` (clone dir `{{clone-dir}}` if it differs).
- **Kind:** {{service | infra | web | lib | gitops | …}}

## What an agent must know

<!-- TEMPLATE: the project-specific facts that aren't obvious from the code — invariants
     that apply here, deploy quirks, naming exceptions, "don't touch X". Link the relevant
     ADR / workstream. -->

- {{Key fact / constraint specific to this repo.}}
- {{Where its deploy values / config live, if separate.}}
