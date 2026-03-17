# §7.2: Bedrock Guardrail — content moderation + prompt injection protection
#
# Applies uniformly to all teams (feature-team1 through feature-team4).
# LiteLLM calls this guardrail on both input (pre_call) and output (post_call).
#
# After terraform apply, copy the outputs into k8s/01-secrets.yaml:
#   guardrail-id:      = output.bedrock_guardrail_id
#   guardrail-version: = output.bedrock_guardrail_version

resource "aws_bedrock_guardrail" "llmgw" {
  name                      = "llmgw-content-guardrail"
  description               = "Content moderation and prompt injection protection for LLM Gateway"
  blocked_input_messaging   = "Your request was blocked by the content policy. Please revise and try again."
  blocked_outputs_messaging = "The model response was blocked by the content policy."

  # §7.2: Content moderation — hate speech, violence, self-harm, adult content
  content_policy_config {
    filters_config {
      type             = "HATE"
      input_strength   = "HIGH"
      output_strength  = "HIGH"
    }
    filters_config {
      type             = "VIOLENCE"
      input_strength   = "HIGH"
      output_strength  = "HIGH"
    }
    filters_config {
      type             = "SEXUAL"
      input_strength   = "HIGH"
      output_strength  = "HIGH"
    }
    filters_config {
      type             = "INSULTS"
      input_strength   = "HIGH"
      output_strength  = "HIGH"
    }
    filters_config {
      type             = "MISCONDUCT"
      input_strength   = "HIGH"
      output_strength  = "HIGH"
    }
    # §7.2: Prompt injection — block attempts to override system instructions
    # output_strength must be NONE for PROMPT_ATTACK (input-only detection)
    filters_config {
      type             = "PROMPT_ATTACK"
      input_strength   = "HIGH"
      output_strength  = "NONE"
    }
  }
}

# Publish a numbered version (v1) — LiteLLM requires a specific version, not DRAFT
resource "aws_bedrock_guardrail_version" "llmgw_v1" {
  guardrail_arn = aws_bedrock_guardrail.llmgw.guardrail_arn
  description   = "v1 — initial production version"
}
