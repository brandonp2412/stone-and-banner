# Stone & Banner

A turn-based strategy board game. Build, trade and defend your realm. First to 15 Renown wins.

[Play online](https://brandonp2412.github.io/stone-and-banner/) | [Download for Android, Linux and Windows](https://github.com/brandonp2412/stone-and-banner/releases)

Play offline against bots, pass and play, or play with friends over LAN or P2P. Matches are saved automatically.

![Gameplay](fastlane/metadata/android/en-US/images/tenInchScreenshots/01-board.png)

<img src="fastlane/metadata/android/en-US/images/phoneScreenshots/01-board.png" alt="Board" width="230"> <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/02-trade.png" alt="Trade" width="230"> <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/03-realm.png" alt="Realm" width="230">

## Development

```sh
flutter pub get
flutter run -d chrome
flutter test
```

[Screenshots](fastlane/metadata/android/en-US/images) are generated on every push to main. [Release builds](https://github.com/brandonp2412/stone-and-banner/actions/workflows/release.yml) are generated on version tags or manually.
