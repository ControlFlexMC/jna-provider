# JNA Provider

**One JNA for every mod in the instance.** For Forge 1.7.10 — the last Minecraft
version that ships no JNA of its own.

## What is this?

Minecraft 1.7.10 is the only version whose version JSON declares no JNA. So on
1.7.10, every mod that reaches a native library through JNA has to get
`com.sun.jna.*` onto the class path itself — and there are only two ways to do
that alone, both worse than they look:

- **Bundle JNA inside the mod.** It works: the class loader takes the first copy
  it finds and keeps using it. But *which* version wins is then decided by jar
  ordering, and two mods built against different JNA versions quietly end up
  sharing one.
- **Put JNA on the launcher's class path, or drop it into the game's libraries
  folder.** Works once — on one instance, on one machine. Nothing in the modpack
  records that it was needed, so the next person to install the pack gets a
  `NoClassDefFoundError` and no clue where it came from.

JNA Provider is the third option. It is a jar containing **JNA 5.12.1** and an
otherwise empty `@Mod` class. Forge adds every jar in `mods/` to its launch class
loader, so one copy dropped in `mods/` puts `com.sun.jna.*` in front of every mod
in the instance — one version, one file, no launcher arguments.

No gameplay content. No API. No config file, no keybind, no command.

## What this is NOT

Read this part twice:

- **Not a JNA fork or a wrapper.** `com.sun.jna` here is JNA 5.12.1, unmodified,
  including its `jnidispatch` native for all 27 platforms JNA ships. Only the core
  artifact is included; `jna-platform` is not.
- **Not a fix for a mod that misuses JNA.** If something crashes inside a native
  call, this jar only guarantees that the classes it needs are present.
- **Not for 1.8.9 or later.** Those versions declare JNA in their own version
  JSON. Installing this there only adds a second copy and makes the winning
  version depend on file order — so `acceptedMinecraftVersions` is pinned to
  `[1.7.10]` and Forge refuses to load it anywhere else.
- **Not configurable.** `jna.nosys`, `jna.boot.library.path` and
  class-transformer exclusions are deliberately left unset. They belong to
  whoever loads a native library, and setting them globally would change the
  bootstrap order for every other JNA consumer in the pack.
- **Not invisible.** It shows up in the mod list as "JNA Provider". That is
  deliberate: a jar with no mod class draws a Forge warning, and other mods need
  a modid to declare a dependency against.

## Installation

1. Install **Minecraft 1.7.10 + Forge** as usual.
2. Drop `jna-provider-1.0.0-mc1.7.10.jar` into your `mods` folder.
3. Start the game.

That's it. Client, server, or both — a server-only install is fine too.

## For mod authors

Declare the dependency and let Forge do the ordering:

```java
@Mod(modid = "mymod", dependencies = "after:jnaprovider")
```

Use `after:` rather than `required-after:` unless JNA is genuinely mandatory —
`required-after:` refuses to start the game when this mod is missing, which turns
an optional provider into a hard requirement.

The ordering is not cosmetic. FML 1.7.10 adds a mod's jar to the class loader
inside `FMLModContainer.constructMod`, so a mod constructed earlier cannot resolve
`com.sun.jna.*` yet. Touch JNA from your constructor without `after:jnaprovider`
and you get a `NoClassDefFoundError`. From `FMLPreInitializationEvent` onwards
every mod has been constructed and everything is in place — the constructor is the
one place that is not.

Two entries go in one string separated by `;`, never by `,`. FML splits the string
on `;` first, so a comma-separated pair is read as one malformed entry, fails
`Loader.computeDependencies`, and crashes later in `sortModList` with an NPE — the
only clue being a single "Unable to parse dependency string" line in the log.

At compile time, depend on JNA itself, never on this jar:

```groovy
compileOnly "net.java.dev.jna:jna:5.12.1"
```

This jar carries no callable classes of its own. Ship the same JNA version this
mod bundles, or an older one whose API you stay inside — JNA 5.x is binary
compatible back to 3.4.0 for the core types.

## Verifying it works

The mod logs one line during pre-init:

```
[jnaprovider] JNA Provider 1.0.0 - bundles JNA 5.12.1; com.sun.jna.Native visible: true
```

`com.sun.jna.Native visible: false` means the classes are not reaching the class
loader — a bug in this mod, not in whatever is trying to use JNA.

## Which versions

| Minecraft | Needs this mod? |
| --- | --- |
| **1.7.10** | **Yes** — no JNA in the version JSON |
| 1.8.9 – 1.16.5 | No — ships JNA 3.4.0 / 4.4.0 |
| 1.17 and later | No — ships JNA 5.8.0 or newer |

The jar targets Java 8, which is what 1.7.10 runs on.

## For pack makers

- **One copy per instance.** Do not bundle it inside another mod, and do not
  shade or relocate `com.sun.jna`: JNA resolves its own `jnidispatch` by package
  path, and other mods look the classes up by that exact name.
- **Redistribution in a pack is fine**, unmodified, with `LICENSE` and
  `META-INF/AL2.0` intact — Apache-2.0 requires the notices to travel with the
  copy.
- **If the pack already contains a mod that bundles JNA, you probably don't need
  this.** Every `mods/*.jar` shares one class loader, so one copy already serves
  everyone; a second only adds ambiguity about which one wins.
- **Server-only installs are safe.** `acceptableRemoteVersions = "*"`, so clients
  that don't have it are not rejected.

## FAQ

**Does this give mods JNA support they didn't have?**

It makes `com.sun.jna.*` resolvable for every mod in the instance, which is the
part 1.7.10 cannot do for itself. A mod that never calls into a native library is
unaffected and doesn't care either way.

**Will it fix a mod built against JNA 3.4.0?**

Usually, yes. JNA 5.x is binary compatible back to 3.4.0 for the core types, so a
mod using `Native.load`, structures, callbacks and the standard argument/return
mappings runs unchanged on 5.12.1. A mod reaching for an API that was removed
since then won't be rescued by a newer copy — that needs the mod itself updated.

**My pack already has a mod that bundles JNA. Which version am I actually running?**

Ask JNA instead of guessing: `com.sun.jna.Native.VERSION` reports the version of
the copy that really loaded. The log line above reports what *this* jar bundles,
which is only the same thing when it is the only copy in the instance. That
ambiguity is precisely why one shared provider beats several embedded copies.

**Does it change JNA system properties for other mods?**

No. `jna.nosys`, `jna.boot.library.path` and class-transformer exclusions are left
untouched on purpose — a global setting here would override the choice of every
other JNA consumer in the pack, and some of them (Steam Bridge is one) need to
control their own bootstrap order. This mod probes `com.sun.jna.Native` without
initialising it.

**Does it work on a server?**

Yes — client, server, or both. `acceptableRemoteVersions = "*"` means clients
without it can still join.

**About 1.7 MB for an "empty" mod — what's in it?**

Almost all of it is `jnidispatch`: 27 platform builds, from `win32-x86` to
`darwin-aarch64`, so the same jar works on Windows, macOS, Linux, and the
BSD / Solaris / AIX targets JNA supports. Nothing is extracted to disk until a mod
actually calls into a native library.

**Can the bundled JNA be updated?**

Yes, and cheaply. This mod's own code never touches JNA's API — the version is one
property in `gradle.properties` — so a bump needs no code change. If an advisory
lands against the bundled copy, a new file will be published; check the file list
rather than assuming a silent rebuild.

**Is this an official JNA release?**

No. It is unofficial and not affiliated with the java-native-access project. JNA
is redistributed here unmodified under Apache-2.0, notices included.

## License

This mod's own code is Apache-2.0. JNA is © the java-native-access project,
dual-licensed Apache-2.0 OR LGPL-2.1; it travels inside the jar unmodified under
Apache-2.0, with `META-INF/AL2.0` alongside it.

## Links

- Source & issue tracker: [github.com/ControlFlexMC/jna-provider](https://github.com/ControlFlexMC/jna-provider)
- Companion project: [ControlFlex](https://www.curseforge.com/minecraft/mc-mods/control-flex) —
  its 1.7.10 gamepad layer reaches SDL3 through JNA, which is why this jar exists.

---
