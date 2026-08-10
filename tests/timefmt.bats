load helper

setup() {
  source "$PROJECT_ROOT/lib/timefmt.sh"
}

@test "normalizes an epoch in seconds unchanged" {
  run sl_epoch_normalize 1800000000
  [ "$output" = "1800000000" ]
}

@test "normalizes an epoch in milliseconds" {
  run sl_epoch_normalize 1800000000000
  [ "$output" = "1800000000" ]
}

@test "drops the fractional part" {
  run sl_epoch_normalize 1800000000.5
  [ "$output" = "1800000000" ]
}

@test "rejects an empty value" {
  run sl_epoch_normalize ""
  [ "$status" -eq 1 ]
}

@test "rejects a non-numeric value that is not a date" {
  run sl_epoch_normalize "banana"
  [ "$status" -eq 1 ]
}

@test "normalizes an ISO 8601 timestamp with Z" {
  run sl_epoch_normalize "2027-01-15T08:00:00Z"
  [ "$status" -eq 0 ]
  [ "$output" = "1800000000" ]
}

@test "formats a clock time under LC_ALL=C" {
  run sl_date_fmt 1800000000 '%H:%M'
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]{2}:[0-9]{2}$ ]]
}

@test "formats a weekday in three ASCII letters" {
  run sl_date_fmt 1800000000 '%a'
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[A-Za-z]{3}$ ]]
}

@test "counts down in days and hours" {
  run sl_fmt_countdown 454000
  [ "$output" = "5d6h" ]
}

@test "counts down in hours and minutes" {
  run sl_fmt_countdown 6480
  [ "$output" = "1h48m" ]
}

@test "counts down in minutes alone" {
  run sl_fmt_countdown 2880
  [ "$output" = "48m" ]
}

@test "counts down under a minute" {
  run sl_fmt_countdown 30
  [ "$output" = "<1m" ]
}

@test "counts down at zero" {
  run sl_fmt_countdown 0
  [ "$output" = "<1m" ]
}

@test "reset under a day shows the clock" {
  run sl_reset_label 1800006480 1800000000
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]{2}:[0-9]{2}.1h48m$ ]]
}

@test "reset over a day shows the weekday" {
  run sl_reset_label 1800454000 1800000000
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[A-Za-z]{3}.5d6h$ ]]
}

@test "reset in the past is refused" {
  run sl_reset_label 1799999000 1800000000
  [ "$status" -eq 1 ]
}

@test "no usable date form refuses instead of printing garbage" {
  SL_DATE_FORM=""
  run sl_reset_label 1800006480 1800000000
  [ "$status" -eq 1 ]
}
