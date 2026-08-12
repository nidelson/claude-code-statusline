load helper

setup() {
  source "$PROJECT_ROOT/lib/num.sh"
}

@test "percentage rounds up from a half or more" {
  run sl_pct 249 1000
  [ "$output" = "25" ]
}

@test "percentage rounds down from below a half" {
  run sl_pct 244 1000
  [ "$output" = "24" ]
}

@test "percentage of an exact ratio is exact" {
  run sl_pct 1 4
  [ "$output" = "25" ]
}

@test "percentage of zero is zero" {
  run sl_pct 0 100
  [ "$output" = "0" ]
}

@test "percentage of the whole is one hundred" {
  run sl_pct 7 7
  [ "$output" = "100" ]
}

@test "percentage can exceed one hundred" {
  run sl_pct 150 100
  [ "$output" = "150" ]
}

@test "seven of nine rounds to seventy eight" {
  # O caso que truncava para 77 no sprint.
  run sl_pct 7 9
  [ "$output" = "78" ]
}

@test "percentage refuses a zero denominator" {
  run sl_pct 5 0
  [ "$status" -eq 1 ]
}

@test "percentage refuses a non-numeric numerator" {
  run sl_pct banana 100
  [ "$status" -eq 1 ]
}

@test "percentage refuses an empty denominator" {
  run sl_pct 5 ""
  [ "$status" -eq 1 ]
}

@test "round takes a decimal up" {
  run sl_round 24.9
  [ "$output" = "25" ]
}

@test "round takes a decimal down" {
  run sl_round 24.3
  [ "$output" = "24" ]
}

@test "round leaves an integer alone" {
  run sl_round 92
  [ "$output" = "92" ]
}

@test "round handles the flow payload figures" {
  run sl_round 24.30
  [ "$output" = "24" ]
  run sl_round 92.33
  [ "$output" = "92" ]
}

@test "round refuses a non-numeric value" {
  run sl_round banana
  [ "$status" -eq 1 ]
}

@test "round refuses an empty value" {
  run sl_round ""
  [ "$status" -eq 1 ]
}

@test "token format leaves small numbers alone" {
  [ "$(sl_fmt_tokens 950)" = "950" ]
}

@test "token format abbreviates thousands" {
  [ "$(sl_fmt_tokens 54000)" = "54k" ]
}

@test "token format rounds to the nearest thousand" {
  [ "$(sl_fmt_tokens 53500)" = "54k" ]
  [ "$(sl_fmt_tokens 53499)" = "53k" ]
}

@test "token format abbreviates millions with one decimal" {
  [ "$(sl_fmt_tokens 1000000)" = "1.0M" ]
  [ "$(sl_fmt_tokens 1250000)" = "1.2M" ]
}

@test "token format reads junk as zero" {
  [ "$(sl_fmt_tokens abc)" = "0" ]
  [ "$(sl_fmt_tokens '')" = "0" ]
}
