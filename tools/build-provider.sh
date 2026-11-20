#!/usr/bin/env bash
# Build the JNA Provider jar and optionally deploy it to a Minecraft 1.7.10 instance.
#
# Usage:
#   ./tools/build-provider.sh
#   ./tools/build-provider.sh --release
#   ./tools/build-provider.sh --clean
#   ./tools/build-provider.sh --keep-logs
#
# Environment:
#   MC_1_7_10_FORGE_PATH  instance game dir (…/minecraft); unset -> skip deploy (WARNING)
#   RELEASE_DEPLOY_PATH   extra copy dest on --release; unset -> WARNING
#   JAVA_HOME             build JVM; must be 9..19 (see below); auto-detected when unset
#
# WHY JAVA_HOME IS PINNED. The build sets `options.release = 8`, which only exists on
# javac 9+, so a JDK 8 cannot build it -- but Gradle 8.1.1 (what the wrapper pins) cannot
# run on a JDK newer than 19 ("Unsupported class file major version"), and a machine like
# this one defaults to 21 or 25. JDK 17 satisfies both, so the script looks for one
# instead of making every caller remember.
#
# WHY THE JAR IS ~1.8 MB. It is JNA itself, unpacked flat: Forge 1.7.10 has no jar-in-jar,
# and a nested JNA would sit where no other mod's class loader could see it. `verifyJar`
# (part of `build`) fails if JNA, mcmod.info or the jnidispatch natives are missing; this
# script re-states the numbers afterwards so a green build is not mistaken for a correct
# one, then re-checks the instance for a second copy of com.sun.jna -- the one thing that
# can quietly defeat this mod.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

RELEASE=false
CLEAN=false
KEEP_LOGS=false
EXTRA_ARGS=()

for arg in "$@"; do
    case "$arg" in
        --release)   RELEASE=true ;;
        --clean)     CLEAN=true ;;
        --keep-logs) KEEP_LOGS=true ;;
        *)           EXTRA_ARGS+=("$arg") ;;
    esac
done

# Resolve the instance before building, not after: a typo'd path should cost a second,
# not a full build. Accept either the game dir or the instance root -- the launcher
# convention here is <instance>/minecraft, and the other repos' deploy scripts normalise
# the same way.
MC_INSTANCE="${MC_1_7_10_FORGE_PATH:-}"
MC_INSTANCE="${MC_INSTANCE%/}"
if [[ -n "$MC_INSTANCE" ]]; then
    if [[ ! -d "${MC_INSTANCE}/mods" && -d "${MC_INSTANCE}/minecraft" ]]; then
        MC_INSTANCE="${MC_INSTANCE}/minecraft"
    fi
    if [[ ! -d "$MC_INSTANCE" ]]; then
        echo "MC_1_7_10_FORGE_PATH does not exist: $MC_INSTANCE"
        echo "Refusing to guess a mods folder. Fix the variable and retry."
        exit 1
    fi
fi

# Prints 8 for "1.8.0_504", 17 for "17.0.16", 25 for "25.0.3".
java_major() {
    "$1" -version 2>&1 \
        | awk -F'"' '/version/ { print $2; exit }' \
        | sed -e 's/^1\.\([0-9]\{1,\}\).*/\1/' -e 's/^\([0-9]\{1,\}\).*/\1/'
}

pick_java_home() {
    if [[ -n "${JAVA_HOME:-}" && -x "${JAVA_HOME}/bin/java" ]]; then
        local major
        major=$(java_major "${JAVA_HOME}/bin/java")
        if [[ -n "$major" && "$major" -ge 9 && "$major" -le 19 ]]; then
            echo "$JAVA_HOME"
            return 0
        fi
        echo "  note: JAVA_HOME=$JAVA_HOME is JDK ${major}, outside 9..19; looking for another" >&2
    fi
    local candidate major
    for candidate in /Library/Java/JavaVirtualMachines/*/Contents/Home \
                     /usr/lib/jvm/* "$HOME"/.sdkman/candidates/java/*; do
        [[ -x "$candidate/bin/java" ]] || continue
        major=$(java_major "$candidate/bin/java")
        if [[ -n "$major" && "$major" -ge 11 && "$major" -le 19 ]]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

if ! JAVA_HOME_PICKED="$(pick_java_home)"; then
    echo 'No usable JDK found (need 9..19): options.release = 8 needs javac 9+, and Gradle 8.1.1 needs a JDK no newer than 19.'
    echo "Set JAVA_HOME to such a JDK and retry."
    exit 1
fi
export JAVA_HOME="$JAVA_HOME_PICKED"
echo "==> build JVM: $JAVA_HOME (JDK $(java_major "$JAVA_HOME/bin/java"))"

cd "$PROJECT_DIR"

if [[ -x ./gradlew ]]; then
    gradle_cmd=(./gradlew)
else
    gradle_cmd=(gradle)
fi

if $CLEAN; then
    echo "==> Cleaning first..."
    "${gradle_cmd[@]}" clean
fi

# The version lives in gradle.properties here, not in build.gradle: the jar name is
# assembled from it in the `jar` task (archiveVersion = "<version>-mc1.7.10").
provider_version=$(sed -n 's/^version=\(.*\)/\1/p' gradle.properties | head -1 | tr -d '[:space:]')
jna_version=$(sed -n 's/^jnaVersion=\(.*\)/\1/p' gradle.properties | head -1 | tr -d '[:space:]')
if [[ -z "$provider_version" || -z "$jna_version" ]]; then
    echo "Could not read version / jnaVersion from gradle.properties"
    exit 1
fi

if $RELEASE; then build_type="Release"; else build_type="Debug"; fi
echo "==> ${build_type} provider build: version ${provider_version}, JNA ${jna_version}"

build_args=(build)
if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then build_args+=("${EXTRA_ARGS[@]}"); fi
echo "==> Running: ${gradle_cmd[*]} ${build_args[*]}"
"${gradle_cmd[@]}" "${build_args[@]}"

NEW_JAR="${PROJECT_DIR}/build/libs/jna-provider-${provider_version}-mc1.7.10.jar"
if [[ ! -f "$NEW_JAR" ]]; then
    echo "JAR not found: $NEW_JAR"
    exit 1
fi

# verifyJar already gated the contents; this only reports them, so a reader does not have
# to open the jar to learn what shipped.
size_bytes=$(wc -c < "$NEW_JAR" | tr -d '[:space:]')
size_mb=$(awk -v b="$size_bytes" 'BEGIN { printf "%.1f", b / 1048576 }')
jna_classes=$(unzip -Z1 "$NEW_JAR" | grep -c '^com/sun/jna/.*\.class$' || true)

echo ""
echo "Build complete: $(basename "$NEW_JAR") (${size_mb} MB, ${jna_classes} JNA classes, bundles JNA ${jna_version})"

if [[ -z "$MC_INSTANCE" ]]; then
    echo "MC_1_7_10_FORGE_PATH is not set; skipping instance deploy"
    echo "   artifact: $NEW_JAR"
else
    MODS_DIR="${MC_INSTANCE}/mods"

    if ! $KEEP_LOGS; then
        LOGS_DIR="${MC_INSTANCE}/logs"
        if [[ -d "$LOGS_DIR" ]]; then
            rm -rf "${LOGS_DIR:?}"/*
            echo "  cleared logs: $LOGS_DIR"
        fi

        CRASH_DIR="${MC_INSTANCE}/crash-reports"
        if [[ -d "$CRASH_DIR" ]]; then
            rm -rf "${CRASH_DIR:?}"/*
            echo "  cleared crash-reports: $CRASH_DIR"
        fi
    fi

    mkdir -p "$MODS_DIR"
    if compgen -G "${MODS_DIR}/jna-provider-*.jar" > /dev/null; then
        rm -f "${MODS_DIR}"/jna-provider-*.jar
        echo "  removed old provider jars"
    fi
    cp "$NEW_JAR" "$MODS_DIR/"
    echo "  deployed: ${MODS_DIR}/$(basename "$NEW_JAR")"

    # A second copy of com.sun.jna on the same class loader does not error -- the first
    # jar reached wins and the loser vanishes without a word -- so say which mods ship one
    # rather than leave "which JNA version is running" to file order. zipinfo only reads
    # the central directory, so this costs milliseconds per jar.
    for other in "${MODS_DIR}"/*.jar; do
        [[ -f "$other" ]] || continue
        other_name="$(basename "$other")"
        [[ "$other_name" == jna-provider-* ]] && continue
        if unzip -Z1 "$other" 'com/sun/jna/Native.class' >/dev/null 2>&1; then
            echo "  note: ${other_name} also ships com.sun.jna; whichever jar the class loader reaches first wins"
        fi
    done

    # Leftovers from an A/B test are inert (Forge only loads *.jar) but they make the next
    # run's result easy to misread. Reported, never deleted: the file may be deliberate.
    for stale in "${MODS_DIR}"/jna-provider-*.jar.*; do
        [[ -f "$stale" ]] || continue
        echo "  note: $(basename "$stale") is present but will not load; delete it if it is left over from an A/B test"
    done

    echo "  expect in ${MC_INSTANCE}/logs/latest.log:"
    echo "    [jnaprovider] JNA Provider ${provider_version} - bundles JNA ${jna_version}; com.sun.jna.Native visible: true"
fi

if $RELEASE; then
    if [[ -n "${RELEASE_DEPLOY_PATH:-}" ]]; then
        mkdir -p "$RELEASE_DEPLOY_PATH"
        cp "$NEW_JAR" "${RELEASE_DEPLOY_PATH}/"
        echo "  release copy: ${RELEASE_DEPLOY_PATH}/$(basename "$NEW_JAR")"
    else
        echo "RELEASE_DEPLOY_PATH is not set; skipping release copy"
    fi
fi
