# Cleaning targets

Generated from `config/targets.psd1` by `tools/gen-targets-doc.ps1`. Do not edit by hand.

**Risk**: Safe = you will not notice anything. Moderate = something is downloaded or rebuilt again (slower once). Careful = removes things you may want back; never part of a preset, always needs typing `YES`.

**Presets**: Q = Quick (Safe, no admin), D = Developer (Safe + Moderate, no admin), X = Deep (Safe + Moderate, with admin).

## Windows

| Id | What | Risk | Admin | Presets | After cleaning |
| --- | --- | --- | --- | --- | --- |
| `user-temp` | Your temp folder (older than 1 day) | Safe |  | Q D X | Nothing. Files that programs are still using are skipped. |
| `inet-cache` | Windows internet cache (INetCache) | Safe |  | Q D X | Nothing. |
| `user-crash-dumps` | Program crash dumps and error reports | Safe |  | Q D X | Nothing. Old crash reports are gone. |
| `directx-shader-cache` | DirectX shader cache | Safe |  | Q D X | Games and apps rebuild shaders on their next start (a little slower once). |
| `recycle-bin` | Recycle Bin (all drives) | Moderate |  | X | Deleted files can no longer be restored. As administrator this empties every account's bin. |
| `old-installers` | Installers in Downloads older than 30 days (.exe .msi .msix .iso) | Careful |  |  | Sent to the Recycle Bin, so you can still restore them. |

## Browsers

| Id | What | Risk | Admin | Presets | After cleaning |
| --- | --- | --- | --- | --- | --- |
| `chrome-cache` | Google Chrome cache (all profiles) | Safe |  | Q D X | Pages load a little slower the first time. Logins, history, passwords and bookmarks are kept. |
| `chrome-ai-model` | Chrome on-device AI model (Gemini Nano) | Moderate |  | D X | Chrome downloads it again (about 4 GB) if its on-device AI is on. Turn it off in chrome://settings/ai, or set the Chrome policy GenAILocalFoundationalModelSettings = 1, to keep it away. |
| `edge-cache` | Microsoft Edge cache (all profiles) | Safe |  | Q D X | Pages load a little slower the first time. Logins and history are kept. |
| `brave-cache` | Brave cache (all profiles) | Safe |  | Q D X | Pages load a little slower the first time. |
| `vivaldi-opera-cache` | Vivaldi and Opera cache | Safe |  | Q D X | Pages load a little slower the first time. |
| `firefox-cache` | Firefox cache (all profiles) | Safe |  | Q D X | Pages load a little slower the first time. |
| `antigravity-browser` | Antigravity browser profile cache and AI model | Moderate |  | D X | The agent browser downloads its model again if it needs it. |

## Developer

| Id | What | Risk | Admin | Presets | After cleaning |
| --- | --- | --- | --- | --- | --- |
| `npm-cache` | npm cache | Safe |  | Q D X | npm downloads packages again when needed. Your projects are not touched. |
| `yarn-bun-cache` | Yarn and Bun caches | Safe |  | Q D X | Packages are downloaded again when needed. |
| `pnpm-store` | pnpm store (unused packages only) | Safe |  | Q D X | Runs "pnpm store prune": only packages no project uses are removed. |
| `node-tool-caches` | node-gyp, Electron, TypeScript and Deno caches | Safe |  | Q D X | Downloaded again when a build needs them. |
| `browser-test-binaries` | Puppeteer, Playwright and Cypress browsers | Moderate |  | D X | Puppeteer downloads Chrome again on npm install; run "npx playwright install" / "npx cypress install" again. |
| `python-caches` | pip, uv and Poetry caches | Safe |  | Q D X | Packages are downloaded again when you install them. Existing virtualenvs keep working. |
| `conda-cache` | Conda package cache | Moderate |  | D X | Runs "conda clean --all": unused package files and tarballs are removed, environments keep working. |
| `ml-model-caches` | Hugging Face and PyTorch downloaded models | Careful |  |  | Models are downloaded again (often many GB) the next time code loads them. |
| `nuget-http-cache` | NuGet download cache | Safe |  | Q D X | Nothing you will notice. |
| `nuget-packages` | NuGet global packages (.nuget\packages) | Moderate |  | D X | The next "dotnet restore" downloads the packages your projects use again. |
| `gradle-caches` | Gradle caches, old wrappers and daemon logs | Moderate |  | D X | The next Android / Flutter / Java build downloads dependencies again (slower once). |
| `maven-repo` | Maven local repository (.m2) | Moderate |  | D X | Maven downloads dependencies again on the next build. |
| `cargo-cache` | Rust Cargo registry and git caches | Moderate |  | D X | Cargo downloads crates again on the next build. |
| `go-caches` | Go build and module caches | Moderate |  | D X | Go rebuilds and downloads modules again when needed. |
| `composer-cache` | Composer (PHP) cache | Safe |  | Q D X | Packages are downloaded again when needed. |
| `pub-cache` | Flutter / Dart pub cache | Moderate |  | D X | Run "flutter pub get" in a project to download its packages again; global tools may need "dart pub global activate" again. |
| `jetbrains-caches` | JetBrains IDE caches, logs and Toolbox downloads | Moderate |  | D X | The IDE re-indexes your project on next open (a few minutes). Settings and plugins are kept. |
| `old-ide-versions` | Caches of old Android Studio / JetBrains IDE versions | Moderate |  | D X | Only versions older than the newest one you have are removed (for example AndroidStudio2026.1.2 when 2026.1.4 is installed). Settings are kept. |
| `android-studio-caches` | Android Studio caches and logs | Moderate |  | D X | Android Studio re-indexes on next open. |
| `code-editor-caches` | VS Code, Cursor, Windsurf and Antigravity caches | Safe |  | Q D X | Nothing you will notice. Extensions and settings are kept. |
| `visual-studio-cache` | Visual Studio component cache | Safe |  | Q D X | Visual Studio rebuilds it on next start. |
| `docker-prune` | Docker: stopped containers, dangling images, build cache | Moderate |  | D X | Runs "docker system prune -f". Running containers, tagged images and volumes are kept. Compact the disk afterwards (menu: WSL / Docker disks). |
| `unity-cache` | Unity cache | Moderate |  | D X | Unity downloads packages again when a project needs them. |

## Apps

| Id | What | Risk | Admin | Presets | After cleaning |
| --- | --- | --- | --- | --- | --- |
| `chat-app-caches` | Teams, Slack and Discord caches | Safe |  | Q D X | Images and attachments load again from the internet. Messages and logins are kept. |
| `misc-app-caches` | Notion, Postman and Steam web caches | Safe |  | Q D X | Nothing you will notice. |
| `spotify-cache` | Spotify cache | Moderate |  | D X | Songs stream again; songs you downloaded for offline use may have to be downloaded again. |

## GPU and drivers

| Id | What | Risk | Admin | Presets | After cleaning |
| --- | --- | --- | --- | --- | --- |
| `gpu-shader-caches` | NVIDIA / AMD / Intel shader caches | Safe |  | Q D X | Games rebuild shaders on their next start (a little slower once). |
| `nvidia-downloads` | NVIDIA App / GeForce Experience downloaded updates | Moderate | yes | X | Old driver installers are removed. Your installed driver is not touched. |
| `driver-extract-folders` | Extracted driver installers (C:\NVIDIA, C:\AMD) | Moderate | yes | X | These are only unpacked setup files. Installed drivers are not touched. |

## Android and phones

| Id | What | Risk | Admin | Presets | After cleaning |
| --- | --- | --- | --- | --- | --- |
| `android-avd-snapshots` | Android emulator quick-boot snapshots | Moderate |  | D X | Emulators do a cold boot once (about a minute). Apps and data inside them are kept. |
| `android-cache` | Android tools cache (.android\cache) | Safe |  | Q D X | Nothing you will notice. |
| `android-avds` | Android emulators (whole virtual devices) | Careful |  |  | The emulators and everything installed in them are gone. Create new ones in Android Studio > Device Manager. |
| `android-system-images` | Android SDK system images | Careful |  |  | Download them again in Android Studio > SDK Manager before creating an emulator. |
| `iphone-backups` | iPhone / iPad backups (iTunes, Apple Devices) | Careful |  |  | Sent to the Recycle Bin. Make sure the phone is backed up to iCloud or elsewhere first. |

## System (admin)

| Id | What | Risk | Admin | Presets | After cleaning |
| --- | --- | --- | --- | --- | --- |
| `windows-temp` | Windows temp folder (older than 1 day) | Safe | yes | X | Nothing. Files in use are skipped. |
| `windows-update-cache` | Windows Update download cache | Moderate | yes | X | Windows Update is stopped for a moment. An update that was half downloaded starts again. |
| `delivery-optimization` | Delivery Optimization cache | Safe | yes | X | Nothing. Updates are no longer shared with other PCs from this cache. |
| `system-crash-dumps` | System crash dumps and error reports | Safe | yes | X | Old blue-screen and crash reports are gone. |
| `system-memory-dump` | Full memory dump (MEMORY.DMP) | Safe | yes | X | The last blue-screen dump is gone (only needed to debug that crash). |
| `windows-logs` | Old Windows setup logs (CBS, DISM) older than 14 days | Safe | yes | X | Nothing. |
| `component-store` | Windows component store cleanup (DISM) | Moderate | yes | X | Superseded update files are removed (often 2-10 GB). Takes 5-15 minutes. Updates already installed stay installed. |
| `windows-old` | Previous Windows installation (Windows.old) and upgrade files | Careful | yes |  | You can no longer roll back to the previous Windows version. |

55 targets in total.
