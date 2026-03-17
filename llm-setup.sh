#!/usr/bin/env bash
# llm-setup.sh — One-time LiteLLM gateway setup commands
#
# Prerequisites:
#   kubectl -n llmgw port-forward svc/litellm 4000:4000
#
# Usage:
#   chmod +x llm-setup.sh
#   MASTER_KEY=<your-key> ./llm-setup.sh
#
# Or run individual sections manually.

set -euo pipefail

# Load env vars from .envrc if not already set (e.g. when direnv is not active)
if [ -f "$(dirname "$0")/.envrc" ]; then
  # shellcheck source=.envrc
  source "$(dirname "$0")/.envrc"
fi

MASTER_KEY="${MASTER_KEY:?MASTER_KEY is required — set it in .envrc}"
BASE_URL="${GATEWAY_URL:-http://localhost:4000}"

echo "=== Creating LiteLLM teams ==="

# REQ §1, §2, §3, §4
# feature-team1: haiku only, $50/mo budget, 60 RPM, 200K TPM
echo "Creating feature-team1..."
curl -s -X POST "$BASE_URL/team/new" \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "team_id": "feature-team1",
    "team_alias": "Feature Team 1",
    "max_budget": 50,
    "budget_duration": "1mo",
    "rpm_limit": 60,
    "tpm_limit": 200000,
    "models": ["claude-haiku"]
  }' | python3 -c "import sys,json; d=json.load(sys.stdin); print('  team_id:', d.get('team_id'), '| budget: $'+str(d.get('max_budget')), '| models:', d.get('models'))"

# feature-team2: haiku only, $50/mo budget, 60 RPM, 200K TPM
echo "Creating feature-team2..."
curl -s -X POST "$BASE_URL/team/new" \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "team_id": "feature-team2",
    "team_alias": "Feature Team 2",
    "max_budget": 50,
    "budget_duration": "1mo",
    "rpm_limit": 60,
    "tpm_limit": 200000,
    "models": ["claude-haiku"]
  }' | python3 -c "import sys,json; d=json.load(sys.stdin); print('  team_id:', d.get('team_id'), '| budget: $'+str(d.get('max_budget')), '| models:', d.get('models'))"

# feature-team3: all models, $200/mo budget, 120 RPM, 500K TPM
echo "Creating feature-team3..."
curl -s -X POST "$BASE_URL/team/new" \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "team_id": "feature-team3",
    "team_alias": "Feature Team 3",
    "max_budget": 200,
    "budget_duration": "1mo",
    "rpm_limit": 120,
    "tpm_limit": 500000,
    "models": ["claude-haiku", "claude-sonnet", "claude-auto"]
  }' | python3 -c "import sys,json; d=json.load(sys.stdin); print('  team_id:', d.get('team_id'), '| budget: $'+str(d.get('max_budget')), '| models:', d.get('models'))"

# feature-team4: all models, $200/mo budget, 120 RPM, 500K TPM
echo "Creating feature-team4..."
curl -s -X POST "$BASE_URL/team/new" \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "team_id": "feature-team4",
    "team_alias": "Feature Team 4",
    "max_budget": 200,
    "budget_duration": "1mo",
    "rpm_limit": 120,
    "tpm_limit": 500000,
    "models": ["claude-haiku", "claude-sonnet", "claude-auto"]
  }' | python3 -c "import sys,json; d=json.load(sys.stdin); print('  team_id:', d.get('team_id'), '| budget: $'+str(d.get('max_budget')), '| models:', d.get('models'))"

echo ""
echo "=== Done. Verify at http://localhost:4000/ui?page=teams ==="

# =============================================================================
# §7.2: Bedrock Guardrail — managed via Terraform (terraform/bedrock_guardrail.tf)
# =============================================================================
#
# To provision:
#   cd terraform && terraform apply
#
# Then wire the outputs into k8s/01-secrets.yaml:
#   terraform output bedrock_guardrail_id      → guardrail-id
#   terraform output bedrock_guardrail_version → guardrail-version
#
# Then apply and restart:
#   kubectl apply -f k8s/01-secrets.yaml
#   kubectl apply -f k8s/02-configmap-litellm.yaml
#   kubectl apply -f k8s/04-litellm.yaml
#   kubectl -n llmgw rollout restart deployment/litellm
