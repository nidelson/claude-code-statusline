# Changelog

## [0.2.0](https://github.com/nidelson/claude-code-statusline/compare/v0.1.0...v0.2.0) (2026-08-15)


### Features

* alarme de gravação de cache na última troca ([a02229d](https://github.com/nidelson/claude-code-statusline/commit/a02229d917abbff1c7d71839f0c124f5fa1feeff))
* countdown de expiração do cache no widget ([ff783aa](https://github.com/nidelson/claude-code-statusline/commit/ff783aaba769157cb5d60aaf7ccec5a985a24317))
* data de renovação no flow, ancorada em quem está em alerta ([57b3552](https://github.com/nidelson/claude-code-statusline/commit/57b3552ac2ebb8819e0e6e18dc81300601ccdb21))
* default de instalação com doze widgets em vez de três ([b6ee626](https://github.com/nidelson/claude-code-statusline/commit/b6ee6266784fd5977e159366e461d2a223661678))
* emoji nos rótulos do flow, palavras inteiras sem ícones ([87f9abc](https://github.com/nidelson/claude-code-statusline/commit/87f9abc496edf0e2f953bd43b65bf6320a1ada15))
* expõe SL_TRANSCRIPT no parse do stdin ([2e65ce2](https://github.com/nidelson/claude-code-statusline/commit/2e65ce2fa6db096cb5ce3cd881edd46c7abfafc1))
* flow no fim da primeira linha do default ([670b097](https://github.com/nidelson/claude-code-statusline/commit/670b0973389958770adb67a173a039bba34bb87a))
* instalação grava padding 0 no settings.json ([03fc608](https://github.com/nidelson/claude-code-statusline/commit/03fc608a8b7271080274441a7d8637359feccfab))
* opção countdown do widget cache, e README ([557c740](https://github.com/nidelson/claude-code-statusline/commit/557c7409471feb3a48d280ecf6b426c1e697d130))
* previsão de bloqueio no flow e no rate-forecast ([216bd71](https://github.com/nidelson/claude-code-statusline/commit/216bd71584f84b28f503d0d51efb67acf91842ea))
* projeção só aparece quando pede reação, e flow ganha dois segmentos ([b22ef15](https://github.com/nidelson/claude-code-statusline/commit/b22ef15e98cfa1ad385356d2f71aa9e4d0878459))
* rótulo da metodologia no widget sprint ([45aa4d3](https://github.com/nidelson/claude-code-statusline/commit/45aa4d32300e799d73562c25af14583a9ec2887e))
* segundos no countdown só abaixo de cinco minutos ([6fa9a15](https://github.com/nidelson/claude-code-statusline/commit/6fa9a15bb2bc163ec2e0c309a1adb5ed6bda59a3))
* setup reconhece a plataforma; README declara o suporte ([5757e60](https://github.com/nidelson/claude-code-statusline/commit/5757e606a0ad34f385c313d92db417069908fce5))
* sl_fmt_ttl, regressiva com resolução de segundo ([dd83902](https://github.com/nidelson/claude-code-statusline/commit/dd83902a07252ba2b8605dddf0460d93dc59c2f2))
* sonda o transcript para carimbo e TTL do cache ([a252044](https://github.com/nidelson/claude-code-statusline/commit/a25204419d644ab3aaa22e48670a046f10c3bd31))
* suporte a Windows via Git Bash ([edd0bf1](https://github.com/nidelson/claude-code-statusline/commit/edd0bf16da32a3ed787186f23a0d02af1b9ce043))
* terceiro segmento do flow, e falha que não apaga o que já foi lido ([467523f](https://github.com/nidelson/claude-code-statusline/commit/467523fdd48ea7f504e1cae819550b3030ca0dd2))


### Bug Fixes

* dois testes do rate-forecast dependiam do relógio da máquina ([7523726](https://github.com/nidelson/claude-code-statusline/commit/7523726b55632a9d64ec5b194ef99aa2c69adb9a))
* normaliza gitdir e common pelo mesmo caminho; testes de separador ([ad45c44](https://github.com/nidelson/claude-code-statusline/commit/ad45c44a5ee4219c87945303dc5eda79eb254cfa))
* previsão de 7d calibrada pela janela, e helper embarcado no plugin ([37918b7](https://github.com/nidelson/claude-code-statusline/commit/37918b7f8e9f8f411e623684b5901672a12f96e4))
* remove package-name do release-please para casar com a tag existente ([48caaf9](https://github.com/nidelson/claude-code-statusline/commit/48caaf9c949794c4c91e248754d140c6b630324a))
* sl_jq remove o CR que o jq do Windows emite ([8276410](https://github.com/nidelson/claude-code-statusline/commit/82764104e2275d1dac0f296bcec4a73ecbacf38a))
* uma regra de arredondamento para todos os percentuais ([800b0bc](https://github.com/nidelson/claude-code-statusline/commit/800b0bc0965e4cf1e4879269a42ee363cb04b5f1))
