load ../helper

setup() {
  source "$PROJECT_ROOT/lib/core.sh"
  source "$PROJECT_ROOT/widgets/model.sh"
}

@test "renders the model name" {
  SL_MODEL="Opus 5"
  run widget_model_render
  [ "$output" = "Opus 5" ]
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
