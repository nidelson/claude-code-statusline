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

# A unidade menor só desaparece quando é zero — `20d0h` gastava duas colunas
# para dizer "e mais zero horas". `1d1h` prova que ela não é cortada sempre.
@test "drops a zero hour from the day countdown" {
  run sl_fmt_countdown 1728000
  [ "$output" = "20d" ]
}

@test "drops a zero minute from the hour countdown" {
  run sl_fmt_countdown 10800
  [ "$output" = "3h" ]
}

@test "keeps a single hour that is not zero" {
  run sl_fmt_countdown 90000
  [ "$output" = "1d1h" ]
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
  [[ "$output" =~ ^[0-9]{2}:[0-9]{2}·1h48m$ ]]
}

@test "reset over a day shows the weekday" {
  run sl_reset_label 1800454000 1800000000
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[A-Za-z]{3}·5d6h$ ]]
}

# Uma semana é o limite do nome do dia: além dela "Tue" descreve várias terças,
# e quem lê não tem como escolher. Os dois testes marcam os dois lados da
# fronteira, para que mexer nela quebre algo.
@test "reset just under a week still shows the weekday" {
  run sl_reset_label 1800604799 1800000000
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[A-Za-z]{3}·6d23h$ ]]
}

@test "reset over a week shows the day and month" {
  run sl_reset_label 1801728000 1800000000
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]{2}[A-Za-z]{3}·20d$ ]]
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

@test "ttl format keeps seconds below a minute" {
  [ "$(sl_fmt_ttl 47)" = "47s" ]
}

@test "ttl format pairs minutes with seconds" {
  [ "$(sl_fmt_ttl 252)" = "4m12s" ]
}

@test "ttl format drops zeroed seconds" {
  [ "$(sl_fmt_ttl 240)" = "4m" ]
}

@test "ttl format pairs hours with minutes" {
  [ "$(sl_fmt_ttl 3720)" = "1h2m" ]
}

@test "ttl format drops zeroed minutes" {
  [ "$(sl_fmt_ttl 3600)" = "1h" ]
}

@test "ttl format reads zero as zero seconds" {
  [ "$(sl_fmt_ttl 0)" = "0s" ]
}

@test "ttl format survives junk" {
  [ "$(sl_fmt_ttl abc)" = "0s" ]
  [ "$(sl_fmt_ttl '')" = "0s" ]
}

@test "the coarse countdown keeps its sub-minute floor" {
  # Contraprova de convivência: sl_fmt_ttl não pode ter sido implementado
  # trocando o piso da função existente. O reset de 5h do rate-forecast
  # depende de "<1m" — com segundos ali a linha pisca a cada repaint.
  [ "$(sl_fmt_countdown 47)" = "<1m" ]
  [ "$(sl_fmt_ttl 47)" = "47s" ]
}

@test "ttl format drops seconds above five minutes" {
  # 350s é 5m50s. Acima do limite, o segundo é ruído que pisca a cada repaint.
  [ "$(sl_fmt_ttl 350)" = "5m" ]
}

@test "ttl format keeps seconds right below five minutes" {
  # Contraprova da faixa: um segundo abaixo do limite, os segundos voltam.
  [ "$(sl_fmt_ttl 299)" = "4m59s" ]
  [ "$(sl_fmt_ttl 300)" = "5m" ]
}

@test "ttl format drops seconds on a long window" {
  # 3480s é 58m, a leitura típica de uma conta com TTL de uma hora.
  [ "$(sl_fmt_ttl 3480)" = "58m" ]
}
