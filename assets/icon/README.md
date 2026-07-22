# App icon & splash source art

`app_icon.png` (1024×1024) and `splash.png` are the source art for the Pulse
launcher icon and native splash. They carry the product palette (deep #06070C
canvas, violet→magenta pulse mark).

Regenerate all platform variants after changing the source art:

```bash
dart run flutter_launcher_icons        # Android mipmaps + adaptive + iOS AppIcon set
dart run flutter_native_splash:create  # Android/iOS launch splash
```

Config for both lives in `pubspec.yaml` (`flutter_launcher_icons:` and
`flutter_native_splash:`). The generated PNGs under `android/app/src/main/res/`
and `ios/Runner/Assets.xcassets/` are committed output — re-run the tools if you
replace `app_icon.png`.

> Note: the two source PNGs are binary and are delivered alongside this repo as
> a download (they could not be pushed through the API used to open the PR).
> Drop `app_icon.png` and `splash.png` here, then run the two commands above.
