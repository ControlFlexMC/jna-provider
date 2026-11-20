package com.ifels.jnaprovider;

import cpw.mods.fml.common.FMLLog;
import cpw.mods.fml.common.Mod;
import cpw.mods.fml.common.event.FMLPreInitializationEvent;

import java.io.InputStream;
import java.util.Properties;

/**
 * Registers this jar as an ordinary Forge mod, and does nothing else.
 *
 * <p>The mod has no gameplay content and no API. Its whole purpose is that a jar
 * sitting in {@code mods/} is added to Forge's {@code LaunchClassLoader}, which is
 * where {@code com.sun.jna.*} has to be for anything that calls into a native
 * library through JNA. Every other mod in the instance sees those classes for
 * free, without shipping its own copy and without a launcher class-path tweak.</p>
 *
 * <p>Minecraft 1.7.10 is the only version this is needed for. 1.8.9 and later
 * declare JNA in their own version JSON, so installing this there would only add
 * a second copy and make the winning version depend on jar ordering.</p>
 *
 * <p>A mod that wants to depend on this one declares
 * {@code dependencies = "required-after:jnaprovider"} (or {@code after:} for a soft
 * dependency) and compiles against {@code net.java.dev.jna:jna} from Maven
 * Central — never against this jar, which carries no classes of its own to call.</p>
 *
 * <p>Deliberately absent from this class: any touch of JNA itself. Loading or
 * initialising {@code com.sun.jna.Native} at startup would decide the bootstrap
 * order for every other JNA consumer in the pack, and some of them (Steam Bridge
 * is one) need to control that order themselves. The class is probed, never
 * initialised.</p>
 */
@Mod(
        modid = JnaProvider.MODID,
        name = JnaProvider.NAME,
        acceptableRemoteVersions = "*",
        acceptedMinecraftVersions = "[1.7.10]"
)
public final class JnaProvider {

    public static final String MODID = "jnaprovider";
    public static final String NAME = "JNA Provider";

    /**
     * Logged once at startup so a crash report answers the only question that
     * matters afterwards: is JNA on the class path, and which copy.
     */
    @Mod.EventHandler
    public void preInit(FMLPreInitializationEvent event) {
        Properties info = readOwnProperties();
        String version = info.getProperty("version", "unknown");
        String jnaVersion = info.getProperty("jnaVersion", "unknown");

        boolean visible = jnaVisible();
        FMLLog.info("[%s] %s %s - bundles JNA %s; com.sun.jna.Native visible: %s",
                MODID, NAME, version, jnaVersion, visible);

        if (!visible) {
            // Should be impossible: the classes are in this very jar. If it does
            // happen another mod has replaced the class path in a way that also
            // breaks every other JNA consumer, so say so rather than fail.
            FMLLog.warning("[%s] JNA classes are not visible to this mod's class loader; "
                    + "native-access mods will not work.", MODID);
        }
    }

    /**
     * @return true when {@code com.sun.jna.Native} resolves on this mod's class
     *         loader. Passes {@code false} for {@code initialize} on purpose —
     *         resolving the class is the question being asked, running its static
     *         initialiser is not.
     */
    private static boolean jnaVisible() {
        try {
            Class.forName("com.sun.jna.Native", false, JnaProvider.class.getClassLoader());
            return true;
        } catch (Throwable t) {
            return false;
        }
    }

    private static Properties readOwnProperties() {
        Properties properties = new Properties();
        try (InputStream in = JnaProvider.class.getResourceAsStream("/jnaprovider.properties")) {
            if (in != null) {
                properties.load(in);
            }
        } catch (Throwable t) {
            // Never let a diagnostic break startup.
        }
        return properties;
    }
}
