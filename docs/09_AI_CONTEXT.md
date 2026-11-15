# AI Context

**Current instructions live in [AGENTS.md](../AGENTS.md).** The numbered files in this folder (`01` through `17`, plus older audits) are retained history. Where they disagree with the code or with `docs/PROJECT_CONTEXT.md`, `docs/ARCHITECTURE.md`, and `docs/PROJECT_STATUS.md`, follow the code and those newer documents. Several older pages still say pickup-only and single-society. The application now supports delivery, selling reach, and multiple societies.

Before making changes:

- Read all documentation in /docs.
- Understand existing architecture.
- Reuse existing components.
- Do not rewrite working code.
- Do not introduce unnecessary dependencies.
- Keep backward compatibility.
- Follow existing coding style.

Never change without approval

- Authentication architecture
- Database technology
- Direct UPI payment approach
- Business rules
- Order lifecycle

Prefer extending existing modules over creating new ones.