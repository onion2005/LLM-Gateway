# Multi-Team LiteLLM Gateway — Requirements

## Overview

Multiple internal teams share a single LiteLLM Gateway. Each team should have independent budget caps, rate limits, and optionally restricted model access. Teams are identified by virtual API keys issued by the gateway admin.

---

## Open Questions

> Answer these to finalise the requirements before implementation.

### 1. Teams

- Team names / identifiers: Use `feature-team1`, `feature-team2`, `feature-team3`, `feature-team4`
- Platform team is managing LLM Gateway. All feature teams are consuming LLM Gateway.

### 2. Budget Controls

- Budgets be enforced as a **monthly USD spend cap** per team.
- When a team hits its budget — hard block?
- There is a **global gateway budget** ceiling across all teams.

### 3. Rate Limits

- Rate limits set as **RPM** (requests per minute) and **TPM** (tokens per minute). (The lowest threshold will take effect first)
- limits are set to per-team and per-user.
- limits differ by model (e.g. stricter limits on `claude-sonnet` than `claude-haiku`).

### 4. Model Access

- some teams are restricted to specific models.
  - Example: `feature-team1`,`feature-team2` team → `claude-haiku` only (cost control)
  - Example: `feature-team3`, `feature-team4` team → all models (`claude-haiku`, `claude-sonnet`, `claude-auto`)
- The `claude-auto` routing model is available to `feature-team3`, `feature-team4`

### 5. Key Management

- Platform team issues virtual keys to teams — platform team manually via the LiteLLM UI for now. Later can be automated via CI/CD pipelines.
- keys are rotated every 30 days.
- keys be stored in AWS Secrets Manager.

### 6. Observability

- per-team spend and usage is visible in the Grafana dashboard.
- teams receive spend alerts (e.g. email/Slack at 80% budget) via slack.
---

## Assumed Constraints

| Constraint | Assumption |
|---|---|
| Auth mechanism | Virtual keys (Bearer tokens) issued per team |
| Budget currency | USD, based on token cost pricing in config |
| Budget reset period | Monthly |
| Enforcement | Hard block at budget limit (HTTP 429) |
| Config storage | Teams + budgets stored in PostgreSQL; defaults seeded from config |

---

## §7 Guardrails & Policies

> Answer these to finalise before implementation.

### 7.1 PII Protection

- **Scope**: Apply PII detection on input (user prompt), output (model response), or both?
- **Action on detection**:
  - `mask` — redact PII before sending to model / returning to user (e.g. `[EMAIL]`, `[Date of birth]`)
  - `block` — reject the request entirely with HTTP 400
  - `log_only` — allow through but flag in spend logs for audit
- **PII entity types to enforce** — which of these should be detected?
  - Names, email addresses, phone numbers
  - National IDs / SSNs
  - Credit card / financial data
  - IP addresses
  - Custom entities (e.g. internal employee IDs)?
- **Provider**: LiteLLM supports Microsoft Presidio (self-hosted, free) and AWS Comprehend (managed, per-request cost). Use Microsoft Presidio for now because it's free. 
- **Team scope**: Apply to all teams.

### 7.2 Standard Guardrails

- **Prompt injection protection**: Block attempts to override system instructions.
- **Content moderation**: Block generation of harmful / offensive content.
  - Categories include hate speech, violence, self-harm, adult content. 
- **Provider for content moderation**: LiteLLM supports Lakera Guard, Aporia, Bedrock Guardrails, or custom callbacks. Use Bedrock Guardrails for content moderation. 
- **Team-specific policies**: Guardrail strictness applies uniformly to all team.

### 7.3 Policy Enforcement

- **Logging**: Guardrail hits (blocks / masks) are logged to PostgreSQL for audit purposes.
- **Alerting**: Guardrail hits trigger Slack alerts (same channel as budget alerts).
- **Fail behaviour**: If the guardrail service is unavailable, should requests be allowed through (`fail_open`).

---

## Assumed Constraints (guardrails)

| Constraint | Assumption |
|---|---|
| PII action | mask (not block) — avoids breaking user workflows |
| Guardrail scope | Both input and output |
| Applies to | All teams uniformly |
| Fail behaviour | fail_open (guardrail outage does not block traffic) |

---

## Summary of configs
┌─────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────┐
│   Requirement   │                                           Implementation                                           │
├─────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ §1 Teams        │ default_team_settings seeds 4 teams in PostgreSQL on startup                                       │
├─────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ §2 Budget caps  │ feature-team1/2: $50/mo · feature-team3/4: $200/mo · global ceiling: $600/mo                       │
├─────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ §3 Rate limits  │ Per-team RPM/TPM + per-user defaults (20 RPM / 50K TPM); sonnet stricter than haiku at model level │
├─────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ §4 Model access │ team1/2 → claude-haiku only; team3/4 → all models incl. claude-auto                                │
├─────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ §6 Slack alerts │ Webhook env var wired; fires at 80% spend threshold                                                │
└─────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────┘
│ §7 Governance   │ Guardrails and policies defined (use presidio anonymizer for PII data redact).                     │
└─────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────┘
