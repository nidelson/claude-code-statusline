load ../helper

setup() {
  source "$PROJECT_ROOT/lib/colors.sh"
  source "$PROJECT_ROOT/lib/core.sh"
  source "$PROJECT_ROOT/widgets/model.sh"
  SL_MODEL_ID=""
}

@test "renders the model name" {
  SL_MODEL="Opus 5"
  run widget_model_render
  [[ "$output" == *"Opus 5"* ]]
}

@test "renders nothing when there is no model" {
  SL_MODEL=""
  run widget_model_render
  [ "$output" = "" ]
}

@test "renders nothing for the Unknown placeholder" {
  SL_MODEL="Unknown"
  run widget_model_render
  [ "$output" = "" ]
}

@test "registers itself on load" {
  sl_widget_registered model
}

@test "declares self-color" {
  [ "$(sl_widget_attr SELFCOLOR model)" = "1" ]
}

@test "paints Anthropic models with the brand colour" {
  SL_MODEL="Opus 5"; SL_MODEL_ID="claude-opus-5"
  run widget_model_render
  [[ "$output" == *$'\033[38;2;217;119;87m'* ]]
}

@test "matches the brand by display name when there is no id" {
  SL_MODEL="Sonnet 5"; SL_MODEL_ID=""
  run widget_model_render
  [[ "$output" == *$'\033[38;2;217;119;87m'* ]]
}

@test "brand match is case insensitive" {
  SL_MODEL="HAIKU 4.5"; SL_MODEL_ID=""
  run widget_model_render
  [[ "$output" == *$'\033[38;2;217;119;87m'* ]]
}

@test "paints non-Anthropic models magenta" {
  SL_MODEL="Llama 3"; SL_MODEL_ID="meta-llama-3"
  run widget_model_render
  [[ "$output" == *$'\033[35m'* ]]
  [[ "$output" != *$'\033[38;2;217;119;87m'* ]]
}
