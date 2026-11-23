![logo](gl4es.png "gl4es logo")

GL4ES - OpenGL for GLES Hardware
====

![gl4es build status](https://api.travis-ci.org/ptitSeb/gl4es.png "gl4es build status")

This is a library provide OpenGL 2.x functionality for GLES2.0 accelerated Hardware (and of course also support OpenGL 1.5 function, sometimes better than when using GLES 1.1 backend)
There is also support for GLES 1.1 Hardware, emulating OpenGL 1.5, and some OpenGL 2.x+ extensions.

GL4ES is known to work on many platform: OpenPandora, ODroid, RaspberryPI (2 and 3 at least), PocketCHIP, "otherfruit"PI (like the OrangePI), Android, iOS, x86 and x86_64 Linux (tested using mesa-egl). There is also some WIP support for AmigaOS4, using experimental GLES2 driver for Warp3D.

This library is based on glshim (https://github.com/lunixbochs/glshim) but as now evolved far from it, with different feature set and objectives. Go check this lib if you need things like RemoteGL or TinyGLES (for software rendering).

The focus is on compatibility and speed with a wide selection of game and software.

It has been tested successfully of a large selection of games and software, including: Minecraft, OpenMW, SeriousSam (both First and Second Encounters), RVGL (ReVolt GL), TSMC (The Secret Maryo Chronicles), TORCS, SpeedDreams, GL-117, Foobillard(plus), half life 1&2, Blender 2.68 to name just a few. I have also some success with Linux port of XNA games, using either MonoGame or FNA.

Most function of OpenGL up to 1.5 are supported, with some notable exceptions:
 * Reading of Depth or Stencil buffer will not work
 * GL_FEEDBACK mode is not implemented
 * No Accum emulation

Some known general limitations:
 * GL_SELECT as some limitation in its implementation (for example, current Depth buffer or bounded texture are not taken into account, also custom vertex shader will not work here)
 * NPOT texture are supported, but not with GL_REPEAT / GL_MIRRORED, only GL_CLAMP will work properly (unless the GLES Hardware support NPOT)
 * Multiple Color attachment on Framebuffer are not supported
 * OcclusionQuery is implemented, but with a 0 bits precision
 * Probably many other things

Status of the GLES2 backend
 * The FPE (Fixed Pipeline Emulator) has most OpenGL 1.5 drawing call implemented
 * The Shader Conversion is really crude, so only simple shaders will work (especially, the implicit conversion float <-> int is not handled)
 * ARB_program are supported (converted on-the-fly to glsl shaders)
 * Lighting support double-side and color separation
 * FogCoord are supported, along with secondary color
 * An ES2 context should be usable (useful for SDL2)
 * OpenGL 2.x games that have been tested include: OpenRA, GZDoom, Danger from the Deep, SuperTuxKart 0.8.1, Hammerwatch, OpenMW, half life 2, many FNA & MonoGames games (FEZ, Towerfall Ascension, Stardew Valley, Dust, Owlboy, and many other), even some Unity3D games (Teslagrad, Colin McRea Rally remake and other)...
 * glxgears works, but FlatShade is not implemented (and will probably never be), so it's slightly different than using GLES1.1 or actual GL hardware
 * GL_TEXTURE_1D, GL_TEXTURE_3D and GL_TEXTURE_RECTANGLE_ARB are not yet supported in shaders (they are supported in fixed pipeline functions), and texture 3D are just a single 2D layer for now.
 * Program that link only a GL_FRAGMENT or GL_VERTEX shader are not supported yet.
 * Some VBO are used.

Status of the GLES1.1 backend
 * Framebuffer use FRAMEBUFFER_OES extension (that must be present in the GLES 1.1 stack)
 * Lighting doesn't support double-side or color separation
 * FogCoord or Secondary colors are not supported
 * GL_TEXTURE_3D are just a single 2D layer (the 1st layer).
 * VBO are supported, but they are emulated, even if VBO if supported in GLES1.1 driver

If you use gl4es in your project (as a static or dynamic link), please mention gl4es in you readme / about / whatever.

----

Compiling
----
How to compile and per-platform specific comment can be found [here](COMPILE.md)

----

GLU
----

Standard GLU do works without any issues. You can find a version [here](https://github.com/ptitSeb/GLU) if you need one.

----

Installation
----

Put lib/libGL.so.1 in your `LD_LIBRARY_PATH`.
Beware that GL4ES is meant to replace any libGL you can have on your system (like Mesa for example)

----

Usage
----

There are many environment variable to control gl4es behavior, also usable at runtime using `glHint(...)`.

See [here](USAGE.md) for all variables and what they do.

----

Media (what is working already)
----

Some screenshot and youtube links of stuffs that works [here](MEDIA.md)

----

Version history
----

The change log is [here](CHANGELOG.md)
