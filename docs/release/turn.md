# TURN-релей: нужен ли и как включить

## Что уже есть

`lib/features/transport/webrtc/ice_servers.dart` шлёт в WebRTC два
публичных STUN (Google, Cloudflare) и TURN-запись, чьи URL/креды берутся из
`--dart-define=TURN_URL / TURN_USER / TURN_CRED`. Без кредов TURN просто
не используется. Если P2P не открылся за 12 секунд, транспорт автоматически
падает в **шифрованный релей через signaling Worker** — связь сохраняется.

## Решение для v1

Можно выпускаться **без TURN**: связка STUN + relay-фолбэк покрывает 100%
случаев (какой-то процент сессий с симметричными NAT просто поедет через
Worker с большей задержкой). Включить TURN стоит, если в бете увидите
жёлтый индикатор+лаги у заметной доли пар в мобильных сетях.

## Варианты TURN (когда решите включать)

| Вариант | Цена | Замечания |
| --- | --- | --- |
| **coturn на VPS** (рекомендую для v1) | ~$5/мес | Статические long-term креды → ложатся прямо в dart-define без доработок кода |
| Cloudflare Calls TURN | ~$0.05/GB | Креды короткоживущие: нужен эндпоинт выдачи (можно добавить в signaling Worker) + доработка клиента на динамические креды |
| Twilio NTS / Metered.ca | pay-as-you-go | То же ограничение: эфемерные креды |

## coturn за 15 минут

VPS с публичным IP (Ubuntu):

```bash
apt install coturn
cat >> /etc/turnserver.conf << 'EOF'
listening-port=3478
fingerprint
lt-cred-mech
user=pulse:<СТОЙКИЙ_ПАРОЛЬ>
realm=turn.<ваш-домен>
no-multicast-peers
no-cli
EOF
systemctl enable --now coturn
# firewall: открыть 3478/udp+tcp и 49152-65535/udp
```

DNS: `turn.<ваш-домен>` → IP VPS. Затем в сборки/CI:

```
TURN_URL=turn:turn.<ваш-домен>:3478
TURN_USER=pulse
TURN_CRED=<СТОЙКИЙ_ПАРОЛЬ>
```

Проверка: trickle-ice тестер WebRTC (webrtc.github.io/samples) должен
выдавать `relay`-кандидаты с вашими кредами.

⚠️ Статические креды в бинарнике извлекаемы — злоумышленник может гонять
трафик через ваш TURN. Для v1 это приемлемый риск (лимитируйте по
`total-quota`/`bps-capacity` в coturn); при росте — переход на эфемерные
креды через Worker.
