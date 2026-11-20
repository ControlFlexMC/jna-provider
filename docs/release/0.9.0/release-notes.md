# JNA Provider 0.9.0

First release.

**What it does**
- Bundles JNA 5.12.1 (unmodified, core artifact only) plus an empty `@Mod` class, so every mod in a Forge 1.7.10 instance can resolve `com.sun.jna.*` without shipping its own copy or editing the launcher's class path
- No gameplay content, no API, no config file, no keybind, no command

**Install**
- Minecraft 1.7.10 + Forge; drop `jna-provider-0.9.0-mc1.7.10.jar` into `mods/`
- Startup logs one line: `[jnaprovider] JNA Provider 0.9.0 - bundles JNA 5.12.1; com.sun.jna.Native visible: true`

**For mod authors**
- `dependencies = "after:jnaprovider"` — `;` separates entries, never `,`
- Compile against `net.java.dev.jna:jna:5.12.1`, never against this jar

**Notes**
- 1.7.10 only: `acceptedMinecraftVersions` is pinned to `[1.7.10]`, because 1.8.9 and later ship their own JNA
- Unofficial; not affiliated with the java-native-access project
