# New AI session prompt

Copy everything below the line into a new Cursor chat, or into another coding assistant, with this repository open.

---

You are working in the SocietyEats repository (GitHub `agrawalpuran/societybites`, folders still named SocietyBites). The product display name is SocietyEats.

Do this before you change any code:

1. Read `AGENTS.md`.
2. Read `docs/LATEST_HANDOVER.md`, `docs/PROJECT_CONTEXT.md`, `docs/ARCHITECTURE.md`, and `docs/PROJECT_STATUS.md`.
3. Open `docs/API_REFERENCE.md`, `docs/DATABASE_REFERENCE.md`, `docs/DECISION_LOG.md`, and `docs/KNOWN_ISSUES.md` for the area you will touch.
4. If an older file in `docs/01` through `docs/17`, or a local skill named `societybites-development-guide`, disagrees with the code or with those documents, follow the code and the newer documents. The older pages still describe a pickup-only, single-society MVP.
5. Run `git status`, `git branch -vv`, and `git stash list`. Name the branch, the HEAD commit, and every uncommitted or stashed change. Do not reset, clean, or discard anything. Do not commit or push unless I ask in this conversation.
6. Read the source for the task. Search for the existing route, library module, Prisma model, and Flutter screen before adding a new one.
7. Reply with a short project briefing: what SocietyEats is, what is already built, what is unfinished, what the working tree contains, and what you believe the next step is. Then continue. Do not ask me to re-explain the business, the stack, the order flow, or the payment model when those are already in the docs.

While you work:

- Make the smallest change that solves the request.
- Keep API contracts and order statuses stable unless I explicitly approve a break.
- Keep WhatsApp and push failures from failing orders.
- Leave Cashfree, WhatsApp, and any new paid vendor off unless I approve them.
- Derive identity on the server from the JWT.
- Do not put secrets in code, docs, or chat.
- Do not say tests passed unless you ran them.
- After a significant change, update `docs/PROJECT_STATUS.md`, `docs/LATEST_HANDOVER.md`, and any of `docs/ARCHITECTURE.md`, `docs/DATABASE_REFERENCE.md`, `docs/API_REFERENCE.md`, `docs/DECISION_LOG.md`, `docs/KNOWN_ISSUES.md`, and `docs/ROADMAP.md` that the change affected.

The uncommitted admin city-scope work, if `git status` still shows it, is in progress. Do not overwrite it.
