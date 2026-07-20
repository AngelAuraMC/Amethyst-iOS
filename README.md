**All the new versions of Minecraft work as of right now, including the 26.3 snapshots. The Keyboard is fixed! Make sure to set your renderer to MobileGlues when you first launch the game! Vulkan does work, just first launch the game using MobileGlues and then change the Prefered Graphics API to Vulkan. There is currently a bug with Sodium and MobileGlues. If someone knows how to fix this, that would be great! There is a post about it in Issues.**

This is a build of AngelAuraAmethyst iOS which has been customized to be able to launch Minecraft 26.x.x. This includes the snapshots. Do note that this is completely unofficial. Don't bother the Amethyst devs if something breaks. Instead, post an issue here and i'll look into it. Keyboard is now working thanks to @T1k-T1k and @DuyAnh662. @T1k-T1k also made compiling possible. Huge thanks to both of them. This build bundles a custom lwjgl version and Java 25. It also does not include slimmed versions. Builds are only published in Releases and not in Actions. Builds in Actions are never intended to be used until they become releases. Most older Minecraft versions that use Java 21 will launch with this by selecting Java 25 as the Java version. All versions that use Java 8 work without any special configuration. Versions that use Java 17 do not currently work. Instead, you can install normal Amethyst alongside this version because of different bundle identifiers.

Compiling does work, and is supported, but is still not recommended. If you compile, be sure to replace lwjgl.jar in the libs section of the built ipa or tipa with the one at the root of this repo.

Thanks to vibecodest for the source code!
## Third party components and their licenses
- [Caciocavallo](https://github.com/PojavLauncherTeam/caciocavallo): [GNU GPLv2 License](https://github.com/PojavLauncherTeam/caciocavallo/blob/master/LICENSE).
- [jsr305](https://code.google.com/p/jsr-305): [3-Clause BSD License](http://opensource.org/licenses/BSD-3-Clause).
- [Boardwalk](https://github.com/zhuowei/Boardwalk): [Apache 2.0 License](https://github.com/zhuowei/Boardwalk/blob/master/LICENSE) 
- [GL4ES](https://github.com/ptitSeb/gl4es) by @lunixbochs @ptitSeb: [MIT License](https://github.com/ptitSeb/gl4es/blob/master/LICENSE).
- [Mesa 3D Graphics Library](https://gitlab.freedesktop.org/mesa/mesa): [MIT License](https://docs.mesa3d.org/license.html).
- [MetalANGLE](https://github.com/khanhduytran0/metalangle) by @kakashidinho and ANGLE team: [BSD 2.0 License](https://github.com/kakashidinho/metalangle/blob/master/LICENSE).
- [MoltenVK](https://github.com/KhronosGroup/MoltenVK): [Apache 2.0 License](https://github.com/KhronosGroup/MoltenVK/blob/master/LICENSE).
- [openal-soft](https://github.com/kcat/openal-soft): [LGPLv2 License](https://github.com/kcat/openal-soft/blob/master/COPYING).
- [Azul Zulu JDK](https://www.azul.com/downloads/?package=jdk): [GNU GPLv2 License](https://openjdk.java.net/legal/gplv2+ce.html).
- [LWJGL3](https://github.com/PojavLauncherTeam/lwjgl3): [BSD-3 License](https://github.com/LWJGL/lwjgl3/blob/master/LICENSE.md).
- [LWJGLX](https://github.com/PojavLauncherTeam/lwjglx) (LWJGL2 API compatibility layer for LWJGL3): unknown license.
- [DBNumberedSlider](https://github.com/khanhduytran0/DBNumberedSlider): [Apache 2.0 License](https://github.com/immago/DBNumberedSlider/blob/master/LICENSE)
- [fishhook](https://github.com/khanhduytran0/fishhook): [BSD-3 License](https://github.com/facebook/fishhook/blob/main/LICENSE).
- [shaderc](https://github.com/khanhduytran0/shaderc) (used by Vulkan rendering mods): [Apache 2.0 License](https://github.com/google/shaderc/blob/main/LICENSE).
- [NRFileManager](https://github.com/mozilla-mobile/firefox-ios/tree/b2f89ac40835c5988a1a3eb642982544e00f0f90/ThirdParty/NRFileManager): [MPL-2.0 License](https://www.mozilla.org/en-US/MPL/2.0)
- [AltKit](https://github.com/rileytestut/AltKit)
- [UnzipKit](https://github.com/abbeycode/UnzipKit): [BSD-2 License](https://github.com/abbeycode/UnzipKit/blob/master/LICENSE).
- [DyldDeNeuralyzer](https://github.com/xpn/DyldDeNeuralyzer): bypasses Library Validation for loading external runtime.
- [LTW render](https://github.com/MojoLauncher/LTW.git): [LGPL-3.0 license](https://github.com/MojoLauncher/LTW/blob/master/LICENSE).
- Thanks to [MCHeads](https://mc-heads.net) for providing Minecraft avatars.
