load helper

setup() {
  source "$PROJECT_ROOT/lib/core.sh"
}

@test "registers and retrieves the render function name" {
  register_widget model --render widget_model_render --color cyan
  [ "$(sl_widget_attr RENDER model)" = "widget_model_render" ]
  [ "$(sl_widget_attr COLOR model)" = "cyan" ]
}

@test "accepts a hyphenated widget name" {
  register_widget rate-forecast --render widget_rf_render
  [ "$(sl_widget_attr RENDER rate-forecast)" = "widget_rf_render" ]
}

@test "flags self-color widgets" {
  register_widget a --render fn_a --self-color
  register_widget b --render fn_b
  [ "$(sl_widget_attr SELFCOLOR a)" = "1" ]
  [ "$(sl_widget_attr SELFCOLOR b)" = "0" ]
}

@test "recognises registered widgets and rejects unknown ones" {
  register_widget model --render fn
  sl_widget_registered model
  ! sl_widget_registered nonexistent
}

@test "accumulates registered names in the list" {
  register_widget a --render fa
  register_widget b --render fb
  [ "$SL_WIDGET_LIST" = " a b" ]
}

@test "rejects registration without --render" {
  ! register_widget broken --color red
  ! sl_widget_registered broken
}
