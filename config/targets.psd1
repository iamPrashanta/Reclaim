# Reclaim cleaning targets.
#
#   Id         unique, stable, kebab-case (used on the command line: -Targets npm-cache,gradle-caches)
#   Group      menu group
#   Risk       Safe     = you will not notice anything (caches, temp files)
#              Moderate = something is rebuilt or downloaded again the next time (slower once)
#              Careful  = removes things you may want back (emulators, models, old Windows). Never in a preset.
#   Admin      needs "Run as administrator"
#   Paths      %VARIABLES% and * / ? wildcards in any segment
#   Mode       Contents = empty the folder, keep it (default) | Folder = delete the folder or file itself
#   OlderThanDays  only files older than this (optional)
#   Processes  programs that should be closed first (without .exe)
#   Handler    special cleaning code in src\System.ps1 instead of plain deletion
#   Presets    override which presets include it (default: Quick = Safe without admin,
#              Dev = Safe + Moderate without admin, Deep = Safe + Moderate including admin)
#   Recycle    $true = send to the Recycle Bin instead of deleting permanently
#   After      what happens after cleaning, shown before you confirm
#
# Add your own targets in config\custom-targets.psd1 (same format, see custom-targets.example.psd1).
@{
    Targets = @(
        # ================================================================ Windows (your account)
        @{ Id = 'user-temp'; Group = 'Windows'; Name = 'Your temp folder (older than 1 day)'; Risk = 'Safe'
           Paths = @('%TEMP%'); OlderThanDays = 1
           After = 'Nothing. Files that programs are still using are skipped.' }
        @{ Id = 'inet-cache'; Group = 'Windows'; Name = 'Windows internet cache (INetCache)'; Risk = 'Safe'
           Paths = @('%LOCALAPPDATA%\Microsoft\Windows\INetCache')
           After = 'Nothing.' }
        @{ Id = 'user-crash-dumps'; Group = 'Windows'; Name = 'Program crash dumps and error reports'; Risk = 'Safe'
           Paths = @('%LOCALAPPDATA%\CrashDumps', '%LOCALAPPDATA%\Microsoft\Windows\WER\ReportArchive', '%LOCALAPPDATA%\Microsoft\Windows\WER\ReportQueue')
           After = 'Nothing. Old crash reports are gone.' }
        @{ Id = 'directx-shader-cache'; Group = 'Windows'; Name = 'DirectX shader cache'; Risk = 'Safe'
           Paths = @('%LOCALAPPDATA%\D3DSCache')
           After = 'Games and apps rebuild shaders on their next start (a little slower once).' }
        @{ Id = 'recycle-bin'; Group = 'Windows'; Name = 'Recycle Bin (all drives)'; Risk = 'Moderate'; Handler = 'recycle-bin'
           Presets = @('Deep')
           After = 'Deleted files can no longer be restored. As administrator this empties every account''s bin.' }
        @{ Id = 'old-installers'; Group = 'Windows'; Name = 'Installers in Downloads older than 30 days (.exe .msi .msix .iso)'; Risk = 'Careful'
           Paths = @('%USERPROFILE%\Downloads\*.exe', '%USERPROFILE%\Downloads\*.msi', '%USERPROFILE%\Downloads\*.msix', '%USERPROFILE%\Downloads\*.msixbundle', '%USERPROFILE%\Downloads\*.iso')
           Mode = 'Folder'; OlderThanDays = 30; Recycle = $true
           After = 'Sent to the Recycle Bin, so you can still restore them.' }

        # ================================================================ Browsers
        @{ Id = 'chrome-cache'; Group = 'Browsers'; Name = 'Google Chrome cache (all profiles)'; Risk = 'Safe'; Processes = @('chrome')
           Paths = @('%LOCALAPPDATA%\Google\Chrome\User Data\*\Cache', '%LOCALAPPDATA%\Google\Chrome\User Data\*\Code Cache',
                     '%LOCALAPPDATA%\Google\Chrome\User Data\*\GPUCache', '%LOCALAPPDATA%\Google\Chrome\User Data\*\Service Worker\CacheStorage',
                     '%LOCALAPPDATA%\Google\Chrome\User Data\*\Service Worker\ScriptCache', '%LOCALAPPDATA%\Google\Chrome\User Data\ShaderCache',
                     '%LOCALAPPDATA%\Google\Chrome\User Data\GrShaderCache', '%LOCALAPPDATA%\Google\Chrome\User Data\GraphiteDawnCache')
           After = 'Pages load a little slower the first time. Logins, history, passwords and bookmarks are kept.' }
        @{ Id = 'chrome-ai-model'; Group = 'Browsers'; Name = 'Chrome on-device AI model (Gemini Nano)'; Risk = 'Moderate'; Processes = @('chrome')
           Paths = @('%LOCALAPPDATA%\Google\Chrome\User Data\OptGuideOnDeviceModel'); Mode = 'Folder'
           After = 'Chrome downloads it again (about 4 GB) if its on-device AI is on. Turn it off in chrome://settings/ai, or set the Chrome policy GenAILocalFoundationalModelSettings = 1, to keep it away.' }
        @{ Id = 'edge-cache'; Group = 'Browsers'; Name = 'Microsoft Edge cache (all profiles)'; Risk = 'Safe'; Processes = @('msedge')
           Paths = @('%LOCALAPPDATA%\Microsoft\Edge\User Data\*\Cache', '%LOCALAPPDATA%\Microsoft\Edge\User Data\*\Code Cache',
                     '%LOCALAPPDATA%\Microsoft\Edge\User Data\*\GPUCache', '%LOCALAPPDATA%\Microsoft\Edge\User Data\*\Service Worker\CacheStorage',
                     '%LOCALAPPDATA%\Microsoft\Edge\User Data\*\Service Worker\ScriptCache', '%LOCALAPPDATA%\Microsoft\Edge\User Data\ShaderCache',
                     '%LOCALAPPDATA%\Microsoft\Edge\User Data\GrShaderCache')
           After = 'Pages load a little slower the first time. Logins and history are kept.' }
        @{ Id = 'brave-cache'; Group = 'Browsers'; Name = 'Brave cache (all profiles)'; Risk = 'Safe'; Processes = @('brave')
           Paths = @('%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data\*\Cache', '%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data\*\Code Cache',
                     '%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data\*\GPUCache', '%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data\*\Service Worker\CacheStorage',
                     '%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data\ShaderCache')
           After = 'Pages load a little slower the first time.' }
        @{ Id = 'vivaldi-opera-cache'; Group = 'Browsers'; Name = 'Vivaldi and Opera cache'; Risk = 'Safe'; Processes = @('vivaldi', 'opera')
           Paths = @('%LOCALAPPDATA%\Vivaldi\User Data\*\Cache', '%LOCALAPPDATA%\Vivaldi\User Data\*\Code Cache', '%LOCALAPPDATA%\Vivaldi\User Data\*\GPUCache',
                     '%LOCALAPPDATA%\Opera Software\Opera Stable\Cache', '%LOCALAPPDATA%\Opera Software\Opera GX Stable\Cache',
                     '%APPDATA%\Opera Software\Opera Stable\Code Cache', '%APPDATA%\Opera Software\Opera GX Stable\Code Cache')
           After = 'Pages load a little slower the first time.' }
        @{ Id = 'firefox-cache'; Group = 'Browsers'; Name = 'Firefox cache (all profiles)'; Risk = 'Safe'; Processes = @('firefox')
           Paths = @('%LOCALAPPDATA%\Mozilla\Firefox\Profiles\*\cache2', '%LOCALAPPDATA%\Mozilla\Firefox\Profiles\*\startupCache', '%LOCALAPPDATA%\Mozilla\Firefox\Profiles\*\thumbnails')
           After = 'Pages load a little slower the first time.' }
        @{ Id = 'antigravity-browser'; Group = 'Browsers'; Name = 'Antigravity browser profile cache and AI model'; Risk = 'Moderate'; Processes = @('Antigravity')
           Paths = @('%USERPROFILE%\.gemini\antigravity-browser-profile\OptGuideOnDeviceModel', '%USERPROFILE%\.gemini\antigravity-browser-profile\*\Cache',
                     '%USERPROFILE%\.gemini\antigravity-browser-profile\*\Code Cache', '%USERPROFILE%\.gemini\antigravity-browser-profile\component_crx_cache')
           After = 'The agent browser downloads its model again if it needs it.' }

        # ================================================================ Developer tools
        @{ Id = 'npm-cache'; Group = 'Developer'; Name = 'npm cache'; Risk = 'Safe'
           Paths = @('%LOCALAPPDATA%\npm-cache\_cacache', '%LOCALAPPDATA%\npm-cache\_npx', '%LOCALAPPDATA%\npm-cache\_logs')
           After = 'npm downloads packages again when needed. Your projects are not touched.' }
        @{ Id = 'yarn-bun-cache'; Group = 'Developer'; Name = 'Yarn and Bun caches'; Risk = 'Safe'
           Paths = @('%LOCALAPPDATA%\Yarn\Cache', '%LOCALAPPDATA%\Yarn\Berry\cache', '%USERPROFILE%\.bun\install\cache')
           After = 'Packages are downloaded again when needed.' }
        @{ Id = 'pnpm-store'; Group = 'Developer'; Name = 'pnpm store (unused packages only)'; Risk = 'Safe'; Handler = 'pnpm-store'
           Paths = @('%LOCALAPPDATA%\pnpm\store')
           After = 'Runs "pnpm store prune": only packages no project uses are removed.' }
        @{ Id = 'node-tool-caches'; Group = 'Developer'; Name = 'node-gyp, Electron, TypeScript and Deno caches'; Risk = 'Safe'
           Paths = @('%LOCALAPPDATA%\node-gyp\Cache', '%LOCALAPPDATA%\electron\Cache', '%LOCALAPPDATA%\electron-builder\Cache',
                     '%LOCALAPPDATA%\Microsoft\TypeScript', '%LOCALAPPDATA%\deno')
           After = 'Downloaded again when a build needs them.' }
        @{ Id = 'browser-test-binaries'; Group = 'Developer'; Name = 'Puppeteer, Playwright and Cypress browsers'; Risk = 'Moderate'
           Paths = @('%USERPROFILE%\.cache\puppeteer', '%LOCALAPPDATA%\ms-playwright', '%LOCALAPPDATA%\Cypress\Cache')
           After = 'Puppeteer downloads Chrome again on npm install; run "npx playwright install" / "npx cypress install" again.' }
        @{ Id = 'python-caches'; Group = 'Developer'; Name = 'pip, uv and Poetry caches'; Risk = 'Safe'
           Paths = @('%LOCALAPPDATA%\pip\Cache', '%LOCALAPPDATA%\uv\cache', '%LOCALAPPDATA%\pypoetry\Cache')
           After = 'Packages are downloaded again when you install them. Existing virtualenvs keep working.' }
        @{ Id = 'conda-cache'; Group = 'Developer'; Name = 'Conda package cache'; Risk = 'Moderate'; Handler = 'conda'
           Paths = @('%USERPROFILE%\anaconda3\pkgs', '%USERPROFILE%\miniconda3\pkgs', '%LOCALAPPDATA%\anaconda3\pkgs', '%LOCALAPPDATA%\miniconda3\pkgs')
           After = 'Runs "conda clean --all": unused package files and tarballs are removed, environments keep working.' }
        @{ Id = 'ml-model-caches'; Group = 'Developer'; Name = 'Hugging Face and PyTorch downloaded models'; Risk = 'Careful'
           Paths = @('%USERPROFILE%\.cache\huggingface\hub', '%USERPROFILE%\.cache\torch')
           After = 'Models are downloaded again (often many GB) the next time code loads them.' }
        @{ Id = 'nuget-http-cache'; Group = 'Developer'; Name = 'NuGet download cache'; Risk = 'Safe'
           Paths = @('%LOCALAPPDATA%\NuGet\v3-cache', '%LOCALAPPDATA%\NuGet\plugins-cache', '%TEMP%\NuGetScratch')
           After = 'Nothing you will notice.' }
        @{ Id = 'nuget-packages'; Group = 'Developer'; Name = 'NuGet global packages (.nuget\packages)'; Risk = 'Moderate'; Processes = @('devenv')
           Paths = @('%USERPROFILE%\.nuget\packages')
           After = 'The next "dotnet restore" downloads the packages your projects use again.' }
        @{ Id = 'gradle-caches'; Group = 'Developer'; Name = 'Gradle caches, old wrappers and daemon logs'; Risk = 'Moderate'; Processes = @('studio64', 'idea64')
           Paths = @('%USERPROFILE%\.gradle\caches', '%USERPROFILE%\.gradle\wrapper\dists', '%USERPROFILE%\.gradle\daemon', '%USERPROFILE%\.gradle\native')
           After = 'The next Android / Flutter / Java build downloads dependencies again (slower once).' }
        @{ Id = 'maven-repo'; Group = 'Developer'; Name = 'Maven local repository (.m2)'; Risk = 'Moderate'
           Paths = @('%USERPROFILE%\.m2\repository')
           After = 'Maven downloads dependencies again on the next build.' }
        @{ Id = 'cargo-cache'; Group = 'Developer'; Name = 'Rust Cargo registry and git caches'; Risk = 'Moderate'
           Paths = @('%USERPROFILE%\.cargo\registry\cache', '%USERPROFILE%\.cargo\registry\src', '%USERPROFILE%\.cargo\git\checkouts')
           After = 'Cargo downloads crates again on the next build.' }
        @{ Id = 'go-caches'; Group = 'Developer'; Name = 'Go build and module caches'; Risk = 'Moderate'
           Paths = @('%LOCALAPPDATA%\go-build', '%USERPROFILE%\go\pkg\mod')
           After = 'Go rebuilds and downloads modules again when needed.' }
        @{ Id = 'composer-cache'; Group = 'Developer'; Name = 'Composer (PHP) cache'; Risk = 'Safe'
           Paths = @('%LOCALAPPDATA%\Composer\files', '%LOCALAPPDATA%\Composer\repo', '%LOCALAPPDATA%\Composer\vcs')
           After = 'Packages are downloaded again when needed.' }
        @{ Id = 'pub-cache'; Group = 'Developer'; Name = 'Flutter / Dart pub cache'; Risk = 'Moderate'
           Paths = @('%LOCALAPPDATA%\Pub\Cache\hosted', '%LOCALAPPDATA%\Pub\Cache\git', '%LOCALAPPDATA%\Pub\Cache\_temp')
           After = 'Run "flutter pub get" in a project to download its packages again; global tools may need "dart pub global activate" again.' }
        @{ Id = 'jetbrains-caches'; Group = 'Developer'; Name = 'JetBrains IDE caches, logs and Toolbox downloads'; Risk = 'Moderate'
           Processes = @('idea64', 'pycharm64', 'webstorm64', 'rider64', 'phpstorm64', 'goland64', 'clion64', 'rustrover64', 'datagrip64', 'jetbrains-toolbox')
           Paths = @('%LOCALAPPDATA%\JetBrains\*\caches', '%LOCALAPPDATA%\JetBrains\*\log', '%LOCALAPPDATA%\JetBrains\Toolbox\cache')
           After = 'The IDE re-indexes your project on next open (a few minutes). Settings and plugins are kept.' }
        @{ Id = 'old-ide-versions'; Group = 'Developer'; Name = 'Caches of old Android Studio / JetBrains IDE versions'; Risk = 'Moderate'; Handler = 'old-ide-versions'
           Processes = @('studio64', 'idea64', 'pycharm64', 'webstorm64', 'rider64', 'phpstorm64', 'goland64', 'clion64', 'rustrover64', 'datagrip64')
           After = 'Only versions older than the newest one you have are removed (for example AndroidStudio2026.1.2 when 2026.1.4 is installed). Settings are kept.' }
        @{ Id = 'android-studio-caches'; Group = 'Developer'; Name = 'Android Studio caches and logs'; Risk = 'Moderate'; Processes = @('studio64')
           Paths = @('%LOCALAPPDATA%\Google\AndroidStudio*\caches', '%LOCALAPPDATA%\Google\AndroidStudio*\log')
           After = 'Android Studio re-indexes on next open.' }
        @{ Id = 'code-editor-caches'; Group = 'Developer'; Name = 'VS Code, Cursor, Windsurf and Antigravity caches'; Risk = 'Safe'
           Processes = @('Code', 'Cursor', 'Windsurf', 'Antigravity')
           Paths = @('%APPDATA%\Code\Cache', '%APPDATA%\Code\CachedData', '%APPDATA%\Code\CachedExtensionVSIXs', '%APPDATA%\Code\Code Cache', '%APPDATA%\Code\GPUCache', '%APPDATA%\Code\logs',
                     '%APPDATA%\Code - Insiders\Cache', '%APPDATA%\Code - Insiders\CachedData',
                     '%APPDATA%\Cursor\Cache', '%APPDATA%\Cursor\CachedData', '%APPDATA%\Cursor\Code Cache', '%APPDATA%\Cursor\logs',
                     '%APPDATA%\Windsurf\Cache', '%APPDATA%\Windsurf\CachedData', '%APPDATA%\Windsurf\logs',
                     '%APPDATA%\Antigravity\Cache', '%APPDATA%\Antigravity\CachedData', '%APPDATA%\Antigravity\Code Cache', '%APPDATA%\Antigravity\logs')
           After = 'Nothing you will notice. Extensions and settings are kept.' }
        @{ Id = 'visual-studio-cache'; Group = 'Developer'; Name = 'Visual Studio component cache'; Risk = 'Safe'; Processes = @('devenv')
           Paths = @('%LOCALAPPDATA%\Microsoft\VisualStudio\*\ComponentModelCache')
           After = 'Visual Studio rebuilds it on next start.' }
        @{ Id = 'docker-prune'; Group = 'Developer'; Name = 'Docker: stopped containers, dangling images, build cache'; Risk = 'Moderate'; Handler = 'docker-prune'
           After = 'Runs "docker system prune -f". Running containers, tagged images and volumes are kept. Compact the disk afterwards (menu: WSL / Docker disks).' }
        @{ Id = 'unity-cache'; Group = 'Developer'; Name = 'Unity cache'; Risk = 'Moderate'; Processes = @('Unity', 'Unity Hub')
           Paths = @('%LOCALAPPDATA%\Unity\cache')
           After = 'Unity downloads packages again when a project needs them.' }

        # ================================================================ Apps
        @{ Id = 'chat-app-caches'; Group = 'Apps'; Name = 'Teams, Slack and Discord caches'; Risk = 'Safe'; Processes = @('ms-teams', 'Teams', 'slack', 'Discord')
           Paths = @('%APPDATA%\Microsoft\Teams\Cache', '%APPDATA%\Microsoft\Teams\Code Cache', '%APPDATA%\Microsoft\Teams\GPUCache', '%APPDATA%\Microsoft\Teams\Service Worker\CacheStorage',
                     '%LOCALAPPDATA%\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView\*\Cache',
                     '%APPDATA%\Slack\Cache', '%APPDATA%\Slack\Code Cache', '%APPDATA%\Slack\GPUCache', '%APPDATA%\Slack\Service Worker\CacheStorage',
                     '%APPDATA%\discord\Cache', '%APPDATA%\discord\Code Cache', '%APPDATA%\discord\GPUCache')
           After = 'Images and attachments load again from the internet. Messages and logins are kept.' }
        @{ Id = 'misc-app-caches'; Group = 'Apps'; Name = 'Notion, Postman and Steam web caches'; Risk = 'Safe'; Processes = @('Notion', 'Postman', 'steam')
           Paths = @('%APPDATA%\Notion\Cache', '%APPDATA%\Notion\Code Cache', '%APPDATA%\Postman\Cache', '%APPDATA%\Postman\Code Cache', '%LOCALAPPDATA%\Steam\htmlcache')
           After = 'Nothing you will notice.' }
        @{ Id = 'spotify-cache'; Group = 'Apps'; Name = 'Spotify cache'; Risk = 'Moderate'; Processes = @('Spotify')
           Paths = @('%LOCALAPPDATA%\Spotify\Storage', '%LOCALAPPDATA%\Packages\SpotifyAB.SpotifyMusic_zpdnekdrzrea0\LocalCache\Spotify\Storage')
           After = 'Songs stream again; songs you downloaded for offline use may have to be downloaded again.' }

        # ================================================================ GPU and drivers
        @{ Id = 'gpu-shader-caches'; Group = 'GPU and drivers'; Name = 'NVIDIA / AMD / Intel shader caches'; Risk = 'Safe'
           Paths = @('%LOCALAPPDATA%\NVIDIA\DXCache', '%LOCALAPPDATA%\NVIDIA\GLCache', '%LOCALAPPDATA%\NVIDIA Corporation\NV_Cache',
                     '%LOCALAPPDATA%\AMD\DxCache', '%LOCALAPPDATA%\AMD\DxcCache', '%LOCALAPPDATA%\AMD\GLCache', '%LOCALAPPDATA%\AMD\VkCache',
                     '%USERPROFILE%\AppData\LocalLow\Intel\ShaderCache')
           After = 'Games rebuild shaders on their next start (a little slower once).' }
        @{ Id = 'nvidia-downloads'; Group = 'GPU and drivers'; Name = 'NVIDIA App / GeForce Experience downloaded updates'; Risk = 'Moderate'; Admin = $true
           Paths = @('%ProgramData%\NVIDIA Corporation\NVIDIA App\UpdateFramework\ota-artifacts', '%ProgramData%\NVIDIA Corporation\Downloader')
           After = 'Old driver installers are removed. Your installed driver is not touched.' }
        @{ Id = 'driver-extract-folders'; Group = 'GPU and drivers'; Name = 'Extracted driver installers (C:\NVIDIA, C:\AMD)'; Risk = 'Moderate'; Admin = $true
           Paths = @('%SystemDrive%\NVIDIA', '%SystemDrive%\AMD'); Mode = 'Folder'; MinDepth = 2
           After = 'These are only unpacked setup files. Installed drivers are not touched.' }

        # ================================================================ Android and phones
        @{ Id = 'android-avd-snapshots'; Group = 'Android and phones'; Name = 'Android emulator quick-boot snapshots'; Risk = 'Moderate'; Processes = @('qemu-system-x86_64', 'emulator')
           Paths = @('%USERPROFILE%\.android\avd\*.avd\snapshots')
           After = 'Emulators do a cold boot once (about a minute). Apps and data inside them are kept.' }
        @{ Id = 'android-cache'; Group = 'Android and phones'; Name = 'Android tools cache (.android\cache)'; Risk = 'Safe'
           Paths = @('%USERPROFILE%\.android\cache')
           After = 'Nothing you will notice.' }
        @{ Id = 'android-avds'; Group = 'Android and phones'; Name = 'Android emulators (whole virtual devices)'; Risk = 'Careful'; Processes = @('qemu-system-x86_64', 'emulator')
           Paths = @('%USERPROFILE%\.android\avd\*.avd', '%USERPROFILE%\.android\avd\*.ini'); Mode = 'Folder'
           After = 'The emulators and everything installed in them are gone. Create new ones in Android Studio > Device Manager.' }
        @{ Id = 'android-system-images'; Group = 'Android and phones'; Name = 'Android SDK system images'; Risk = 'Careful'
           Paths = @('%LOCALAPPDATA%\Android\Sdk\system-images\*'); Mode = 'Folder'
           After = 'Download them again in Android Studio > SDK Manager before creating an emulator.' }
        @{ Id = 'iphone-backups'; Group = 'Android and phones'; Name = 'iPhone / iPad backups (iTunes, Apple Devices)'; Risk = 'Careful'; Processes = @('iTunes', 'AppleMobileDeviceProcess')
           Paths = @('%APPDATA%\Apple Computer\MobileSync\Backup\*', '%USERPROFILE%\Apple\MobileSync\Backup\*'); Mode = 'Folder'; Recycle = $true
           After = 'Sent to the Recycle Bin. Make sure the phone is backed up to iCloud or elsewhere first.' }

        # ================================================================ System (administrator)
        @{ Id = 'windows-temp'; Group = 'System (admin)'; Name = 'Windows temp folder (older than 1 day)'; Risk = 'Safe'; Admin = $true
           Paths = @('%SystemRoot%\Temp'); OlderThanDays = 1
           After = 'Nothing. Files in use are skipped.' }
        @{ Id = 'windows-update-cache'; Group = 'System (admin)'; Name = 'Windows Update download cache'; Risk = 'Moderate'; Admin = $true; Handler = 'windows-update-cache'
           Paths = @('%SystemRoot%\SoftwareDistribution\Download')
           After = 'Windows Update is stopped for a moment. An update that was half downloaded starts again.' }
        @{ Id = 'delivery-optimization'; Group = 'System (admin)'; Name = 'Delivery Optimization cache'; Risk = 'Safe'; Admin = $true; Handler = 'delivery-optimization'
           Paths = @('%SystemRoot%\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache',
                     '%SystemRoot%\SoftwareDistribution\DeliveryOptimization')
           After = 'Nothing. Updates are no longer shared with other PCs from this cache.' }
        @{ Id = 'system-crash-dumps'; Group = 'System (admin)'; Name = 'System crash dumps and error reports'; Risk = 'Safe'; Admin = $true
           Paths = @('%SystemRoot%\Minidump', '%SystemRoot%\LiveKernelReports', '%ProgramData%\Microsoft\Windows\WER\ReportArchive',
                     '%ProgramData%\Microsoft\Windows\WER\ReportQueue', '%ProgramData%\Microsoft\Windows\WER\Temp')
           After = 'Old blue-screen and crash reports are gone.' }
        @{ Id = 'system-memory-dump'; Group = 'System (admin)'; Name = 'Full memory dump (MEMORY.DMP)'; Risk = 'Safe'; Admin = $true
           Paths = @('%SystemRoot%\MEMORY.DMP'); Mode = 'Folder'
           After = 'The last blue-screen dump is gone (only needed to debug that crash).' }
        @{ Id = 'windows-logs'; Group = 'System (admin)'; Name = 'Old Windows setup logs (CBS, DISM) older than 14 days'; Risk = 'Safe'; Admin = $true
           Paths = @('%SystemRoot%\Logs\CBS', '%SystemRoot%\Logs\DISM', '%SystemRoot%\Logs\MeasuredBoot'); OlderThanDays = 14
           After = 'Nothing.' }
        @{ Id = 'component-store'; Group = 'System (admin)'; Name = 'Windows component store cleanup (DISM)'; Risk = 'Moderate'; Admin = $true; Handler = 'dism'
           After = 'Superseded update files are removed (often 2-10 GB). Takes 5-15 minutes. Updates already installed stay installed.' }
        @{ Id = 'windows-old'; Group = 'System (admin)'; Name = 'Previous Windows installation (Windows.old) and upgrade files'; Risk = 'Careful'; Admin = $true; Handler = 'windows-old'
           Paths = @('%SystemDrive%\Windows.old', '%SystemDrive%\$Windows.~BT', '%SystemDrive%\$Windows.~WS', '%SystemDrive%\ESD\Windows')
           After = 'You can no longer roll back to the previous Windows version.' }
    )
}
