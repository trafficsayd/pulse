# Review notes для модерации (App Store / Google Play)

Главный риск ревью: **приложение осмысленно только с двумя устройствами**.
Ревьюер с одним устройством увидит экран пейринга и решит, что приложение
не работает. Противоядие: явные notes + демо-видео.

## Демо-видео (обязательно)

Снимите 60–90 секунд одним дублем (двумя телефонами на столе, экраны в
кадре):

1. Устройство A: «Создать пару» → показан 6-значный код.
2. Устройство B: «Присоединиться» → ввод кода → на обоих экранах одинаковый
   SAS → подтверждение.
3. Режим «Тук-Тук»: касание на A → отклик (свет/вибрация) на B.
4. «Свечка»: A зажигает, B задувает в микрофон.
5. Paywall: открыть, показать цену, Restore purchases, тап по Terms и
   Privacy (открываются в браузере).
6. Sneak In с колеса сигналов.

Залейте как unlisted на YouTube (или файлом в Play Console — там есть
поле). Ссылку — в notes ниже.

## App Store Connect → App Review Information → Notes (EN)

```
Pulse is a two-device app: trusted people pair their phones directly and
exchange sensory signals (touch, vibration, light, sound). There are no
accounts and no server-side content — pairing keys live only on the two
devices, all traffic is end-to-end encrypted.

TO REVIEW WITH ONE DEVICE: the pairing screen, mode catalog, settings,
diagnostics and the subscription paywall (including Restore Purchases,
Terms of Use and Privacy Policy links) are all reachable without a partner
device.

TO SEE THE FULL FLOW: please watch this 90-second demo of two phones
pairing by 6-digit code and exchanging signals over BLE / local network /
internet relay: <VIDEO_URL>

Subscription: Pulse Premium (pulse_premium_monthly), 1 month with a 7-day
free trial, unlocks all modes, unlimited "Sneak In" signals and up to 10
saved connections. Free tier keeps Knock-Knock and Half-Heart modes.

Background modes: bluetooth-central / bluetooth-peripheral keep the paired
link alive to receive short "Sneak In" signals (core product behavior, see
demo video).

Note: the one-time pairing handshake normally goes through our signaling
relay, but it also works fully offline: when the relay is unreachable the
phones exchange public keys directly over BLE (the hosting device must be
an Android phone in that case). After pairing, nearby modes always run
fully offline over BLE / local network.

No account credentials are required for review.
```

## Play Console → App access → Instructions (EN)

```
No login required. Full functionality requires a second phone: users pair
two devices with a 6-digit code and exchange encrypted sensory signals
(vibration / light). Demo video of the complete two-device flow:
<VIDEO_URL>. With a single device you can review pairing, the mode
catalog, settings and the subscription paywall (price is loaded from
Google Play; 7-day free trial offer; Restore purchases; Privacy Policy
link).
```

## Если придёт реджект

- **«App doesn't work / stuck at pairing»** — вежливо указать на notes и
  видео; предложить созвон-демо (Apple иногда соглашается).
- **«Subscription terms unclear»** — на paywall есть цена из стора, срок
  триала, Restore, ссылки Terms/Privacy; в описании — абзац об
  автопродлении. Указать таймкод в видео.
