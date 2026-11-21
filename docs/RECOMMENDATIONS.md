# Keeping C: from filling up again

Cleaning gets space back once. These changes stop most of it from coming back.

## Let Windows do the routine work

- **Storage Sense** (Settings > System > Storage > Storage Sense): turn it on and let it empty temp files
  and the Recycle Bin every week or month. Reclaim's weekly Quick clean (`reclaim -Schedule weekly`) covers
  the developer and browser caches that Storage Sense does not know about.
- **Low space alert**: `reclaim -Schedule alert` shows a notification when any drive drops under
  `LowSpaceGB` (20 GB by default), before things start failing.

## Move the things that grow

| What | How |
| --- | --- |
| Downloads, Documents, Videos | Right-click the folder > Properties > Location > Move, choose a folder on D:. |
| Developer caches | Reclaim menu **M** sets `npm_config_cache`, `YARN_CACHE_FOLDER`, `PIP_CACHE_DIR`, `UV_CACHE_DIR`, `NUGET_PACKAGES`, `GRADLE_USER_HOME`, `PUPPETEER_CACHE_DIR`, `PLAYWRIGHT_BROWSERS_PATH` and `HF_HOME` to a folder on another drive. |
| WSL distro | `wsl --shutdown`, `wsl --export Ubuntu D:\wsl\ubuntu.tar`, `wsl --unregister Ubuntu`, `wsl --import Ubuntu D:\wsl\Ubuntu D:\wsl\ubuntu.tar`. Check the export before unregistering. |
| Docker Desktop | Settings > Resources > Advanced > Disk image location. |
| Android emulators | Set the user variable `ANDROID_AVD_HOME` (for example `D:\Android\avd`) before creating emulators; install the SDK on D: in Android Studio > Settings > Android SDK. |
| Projects | Keep code on D: (`D:\Code`). Run menu **6** every few months for old `node_modules` and build folders. |

## Settings worth changing

- **Hibernation**: menu 9 > 1 > `r` (reduced) roughly halves `hiberfil.sys` and keeps Fast Startup.
  Turn it off completely only if you never use Hibernate and do not care about Fast Startup.
- **Compact OS**: menu 9 > 4 compresses Windows system files, usually 2 to 4 GB, with no noticeable cost on
  an SSD. Reversible with `compact /compactos:never`.
- **Chrome's on-device AI model** (about 4 GB, downloads itself again after you delete it): turn it off in
  `chrome://settings/ai`, or set the Chrome policy `GenAILocalFoundationalModelSettings` to `1`.
- **WSL sparse disks**: menu 8 offers `wsl --manage <distro> --set-sparse true` (WSL 2.0 and newer), so
  the Linux disk gives freed space back to Windows by itself.
- **pnpm instead of npm** for many Node projects: one shared store with hard links instead of a full copy of
  every package in every project.
- **OneDrive Files On-Demand**: right-click big OneDrive folders > Free up space.

## Leave these alone

Never delete these by hand, even when they are big. Reclaim refuses to touch them:

- `C:\Windows\WinSxS`: use the DISM item (Deep clean) instead.
- `C:\Windows\Installer` and `C:\ProgramData\Package Cache`: programs need them to update, repair and uninstall.
- `pagefile.sys`: keep it on and managed by Windows; add a second one on D: if C: is small.
- `C:\System Volume Information`: restore points; manage them in System Protection (menu 9 > 3).
