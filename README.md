# JNA Provider

Bundles [JNA](https://github.com/java-native-access/jna) for **Forge 1.7.10**, the
one Minecraft version that ships no JNA of its own. Drop the jar in `mods/` and
every mod in the instance that reaches a native library through JNA works — no
per-mod copy, no launcher class-path tweak.

This mod contains no gameplay content and exposes no API. It exists so that other
mods do not each have to bundle their own copy.

Unofficial. Not affiliated with the java-native-access project.

## Using it from another mod

Two separate things, and it is worth keeping them apart:

**At runtime**, declare it as a dependency and let Forge do the ordering:

```java
@Mod(modid = "mymod", dependencies = "after:jnaprovider")
// two entries go in one string, separated by ';' -- never by ',':
// dependencies = "required-after:unimixins;after:jnaprovider"
```

Use `after:` unless JNA is genuinely mandatory — `required-after:` refuses to start
the game when this mod is missing, which turns an optional provider into a hard
requirement.

The separator matters more than it looks. FML 1.7.10 splits the dependency string
on `;` and then each entry on `:`, so a comma-separated pair is read as ONE entry
with three colon parts, fails `Loader.computeDependencies`, and throws out of
`bindMetadata` — leaving the container's version `null` and crashing later in
`sortModList` with an NPE in `DefaultArtifactVersion`. The only clue is a single
"Unable to parse dependency string" line. Editing `mcmod.info`'s `dependencies`
array is not a substitute: without `useDependencyInformation` FML ignores it for
sorting, and with it enabled the `required-after` entries lose their hard-gate
status.

The ordering is not cosmetic. Forge 1.7.10 does **not** put every `mods/*.jar` on
the class path at launch: `FMLModContainer.constructMod` calls
`ModClassLoader.addFile(source)` for its own jar and only then instantiates the mod
class. A mod constructed earlier can therefore not resolve `com.sun.jna.*` yet, and
touching JNA from a constructor fails with `NoClassDefFoundError` unless this mod is
constructed first. Everything from `FMLPreInitializationEvent` onwards is safe,
because every mod has been constructed by then — the constructor is the one place
that is not. Declare `after:` and stop depending on modid ordering.

**At compile time**, depend on JNA itself, never on this jar:

```groovy
compileOnly "net.java.dev.jna:jna:5.12.1"   // Maven Central
```

This jar carries no callable classes of its own, and depending on it would pin
your build to a mod revision for nothing. Ship the same JNA version this mod
bundles, or an older one whose API you stay inside — JNA 5.x is binary compatible
back to 3.4.0 for the core types.

## Why this exists

Forge adds every jar in `mods/` to `LaunchClassLoader`, so a jar that carries
`com.sun.jna` is enough to satisfy mods that need it. That is all this mod is: JNA
plus an empty `@Mod` class, so Forge registers it cleanly instead of warning about
a jar with no mod class.

The alternative — every mod embedding its own JNA — does not produce duplicate
classes (the class loader caches the first one it finds and keeps using it), but it
does make *which version wins* depend on jar ordering. A single shared provider
removes that ambiguity.

## Which versions

| Minecraft | Needs this mod? |
|---|---|
| 1.7.10 | **Yes** — no JNA in the version JSON |
| 1.8.9 – 1.16.5 | No — ships JNA 3.4.0 / 4.4.0 |
| 1.17 and later | No — ships JNA 5.8.0 or newer |

`acceptedMinecraftVersions` is pinned to `[1.7.10]`, so Forge refuses to load it
anywhere else. That is deliberate: on 1.8.9+ the game already provides JNA, and a
second copy only makes the winning version depend on file ordering.

## Install

1. Put `jna-provider-<version>-mc1.7.10.jar` in `.minecraft/mods/`.
2. Start the game.

Nothing to configure — no config file, no keybind, no command.

## Verifying it works

The mod logs one line during pre-init:

```
[jnaprovider] JNA Provider 1.0.0 - bundles JNA 5.12.1; com.sun.jna.Native visible: true
```

`com.sun.jna.Native visible: false` means the classes are not reaching the class
loader, which would be a bug in this mod rather than in whatever is trying to use
JNA.

## What it bundles

JNA 5.12.1, unmodified, including its native `jnidispatch` for every platform JNA
supports. Only the core artifact is included; `jna-platform` is not.

`jna.nosys`, `jna.boot.library.path` and any class-transformer exclusions are
**not** set here. Those belong to whoever loads the native library, and setting
them globally would change the bootstrap order for every other JNA consumer in the
pack.

## Building

Requires JDK 17 — Gradle 8.1.1 refuses to start on Java 20 or newer
(`Unsupported class file major version`), and `--release 8` needs JDK 9+ — plus
network access on the first build. The jar itself targets Java 8.

```bash
./gradlew build          # jar + verifyJar
./gradlew jar            # build/libs/jna-provider-<version>-mc1.7.10.jar

./tools/build-provider.sh            # picks a JDK, builds, deploys to $MC_1_7_10_FORGE_PATH
./tools/build-provider.sh --release  # ... and copies to $RELEASE_DEPLOY_PATH
./tools/build-provider.sh --keep-logs  # ... without clearing the instance's logs
```

The script exists because the build needs a JDK in 9..19 and the default one
usually is not: it finds such a JVM, runs the same `build` task, then replaces any
older `jna-provider-*.jar` in the instance and reports what shipped.

`verifyJar` fails the build if the jar is missing `mcmod.info`, the mod class, the
JNA classes or the `jnidispatch` natives, or if any Forge/Minecraft class leaked
into it.

## License

This repository's own code is Apache-2.0 — see [LICENSE](LICENSE).

JNA is © the java-native-access project, dual-licensed Apache-2.0 OR LGPL-2.1. It is
redistributed here unmodified under Apache-2.0; the full text is in
[LICENSE_JNA](LICENSE_JNA) and travels inside the jar as `META-INF/AL2.0`.
