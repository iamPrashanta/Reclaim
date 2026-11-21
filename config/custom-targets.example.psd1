# Copy this file to custom-targets.psd1 (ignored by git) and add your own folders.
# Same fields as config\targets.psd1.
@{
    Targets = @(
        @{ Id = 'my-render-cache'; Group = 'Custom'; Name = 'Blender / DaVinci render cache'; Risk = 'Safe'
           Paths = @('D:\Renders\cache', '%APPDATA%\Blackmagic Design\DaVinci Resolve\Support\CacheClip')
           After = 'Previews are rendered again.' }
        @{ Id = 'my-old-logs'; Group = 'Custom'; Name = 'Project logs older than 60 days'; Risk = 'Safe'
           Paths = @('D:\Code\*\logs'); OlderThanDays = 60
           After = 'Nothing.' }
    )
}
