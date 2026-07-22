# Экспортная криптография (iOS App Store)

## Почему это касается Pulse

Pulse шифрует пользовательский трафик собственным протоколом: ECDH на
Curve25519, HKDF-SHA-256, AES-256-GCM (пакет `cryptography` в Dart). Это
**не** «только HTTPS», поэтому ответ «приложение не использует шифрование /
использует только exempt» — некорректен. В `Info.plist` мы честно ставим:

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<true/>
```

Хорошая новость: приложения, использующие **стандартные** алгоритмы
(AES, ECDH на стандартных кривых), проходят по упрощённой схеме
«mass market / standard algorithms» — распространять можно, нужны лишь
две формальности ниже.

## Ответы в App Store Connect (при первом билде и раз в год)

1. *Is your app designed to use cryptography or does it contain or
   incorporate cryptography?* → **Yes**.
2. *Does your app qualify for any of the exemptions provided in Category 5,
   Part 2 of the U.S. Export Administration Regulations?* → **No**.
3. *Does your app implement any encryption algorithms that are proprietary
   or not accepted as standard...?* → **No** (только стандартные: AES,
   Curve25519, SHA-256).
4. App Store Connect предложит указать, доступно ли приложение во Франции,
   и напомнит про годовой отчёт — см. ниже.

После первого прохождения можно записать выданный
`ITSEncryptionExportComplianceCode` в `Info.plist`, чтобы вопросы не
задавались на каждый билд.

## Две формальности

1. **Годовой self-classification report (США, BIS).** Раз в год (до
   1 февраля за прошедший год) отправляется e-mail с CSV-отчётом на
   `crypt-supp8@bis.doc.gov` и `enc@nsa.gov`. Формат CSV описан в
   EAR §742.15(b). Строка для Pulse (шаблон):

   ```csv
   PRODUCT NAME,MODEL NUMBER,MANUFACTURER,ECCN,AUTHORIZATION TYPE,ITEM TYPE
   Pulse,1.0,<имя разработчика/ИП>,5D992.c,MMKT,Mobility and mobile applications n.e.s.
   ```

2. **Франция (ANSSI).** Для приложений с шифрованием, доступных во
   французском App Store, формально требуется декларация в ANSSI (форма на
   ssi.gouv.fr). Прагматичный вариант для v1 — исключить Францию из списка
   стран в App Store Connect → Pricing and Availability и добавить её после
   подачи декларации.

## Google Play

Play не задаёт вопросов об экспортной криптографии на этом уровне —
достаточно корректной Data Safety (см. `play_console.md`). Юридическая
обязанность self-classification (США) покрывает обе платформы разом.

## Если хочется «проще»

Единственный способ честно вернуть `ITSAppUsesNonExemptEncryption=false` —
убрать собственную криптографию из приложения, что противоречит сути Pulse.
Не рекомендуется. Формальности выше — это ~30 минут раз в год.
