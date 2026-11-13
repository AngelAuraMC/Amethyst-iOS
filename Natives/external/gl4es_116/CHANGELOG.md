Version history
----
##### v1.1.6
* Improve glGetError() handling
* Improve LIBGL_FB=3 handling
* Added some ShaderHacks
* Better Renderbuffer handling
* Fixed many issues with VAO and VBO
* Improved ARB shader support
* optimized some format conversion
* Improve mipmap handling
* Improve Android support
* Added sampler handling
* Improve texture format handling
* some fixes to a few matrix computation
* Added support for a new platform: Windows (thx to @yjh-styx)
* Added some more extension to GLES2 backend

##### v1.1.4
* Fixed some regression, and foobillard++ is working fine now
* Set default GL version to 2.1 (instead of 2.0) for GLES2.0 backend
* Added ARB_vertex_program and ARB_fragment_program
* Improved fpe with more compatibility fixes
* Improved Handling of DXTc textures
* Improve handling of partially mipmap'd textures
* Added PYRA Profile
* Added support for Texture LOD access in Fragment Shaders
* Increased maximum Texture Unit support to 16 (from 8)
* Added support for program without Vertex Shader
* Some fixes for program that switch GLX Context frequently.
* Fixes and improvements in fpe_shaders (less array access)
* Added support for Clipping Plane in custom shaders (help OpenMW water reflection)
* Added support for multiple FBO attachement (if hardware support it)

##### v1.1.2
* Improved a bit the merger (wich merge subsequent `glBegin(...)`/`glEnd()`) efficiency
* Removed LIBGL_BEGINEND=2 (that was not working correctly, and it complexify the code too much)
* Added some Direct Access function (from EXT_direct_access)
* Fixes and Improvements on depth (and depth_Stencil) Texture handling
* Handling of GL_BGRA color size in VA (for HumandRessourceMachine)
* Some fixes to fpe_shader (for Neverwinter Night)
* Rework of Header structure (from @rajdakin)
* Better test, using "make test" (from @rajdakin, still using apitrace for replay)
* Added PSA: Precompiled Shader Archive, to store (and fast retrieve) FPE shader (and avoid some pauses when complex FPE shaders are computed)
* Numerous optimization and changes in Batch mode.
* Fixes to GL_BGRA handling
* Improvement in texture format handling, to limit number of conversions
* Added handling of VBO. Real VBO are used (in GLES2+ only) for GL_ARRAY_BUFFER and GL_ELEMENT_ARRAY_BUFFER
* Added VBO when processing glList (only in GLES2+)
* Added a few more GL3.x functions (like glTexStorage). No real GL3.0 support yet
* Can now use GBM/DRM, using LIBGL_FB=4. Still WIP, but now it start to work (thanks to @icecream95)
* Preliminary Emscripten support (thanks to @CecilHarvey)
* AmigaOS4 support is now live (thanks to @kas1e)
* Some fixes to texture handling, when uploading (or modifying) a texture in a multi-texture context
* Small optimization some of the FPE Generated program (many fragment shaders that do texturing)
* Added support to glGetProgramBinary extension
* GL4ES has a logo now :) !
* AmigaOS4 is now fully supported! And SDK (with libs and samples) is available on os4depot
* Emscripten is now supported! A first example of a game using gl4es in a web build can be found [here](http://ptitseb.github.io/stuntcarremake/) with [Stunt Car Remake](https://github.com/ptitSeb/stuntcarremake)


##### v1.1.0
* Default backend is now GLES2 (but not on Pandora, still GLES1.1 for compatibility reasons)
* Added LIBGL_SHADERNOGLES to remove the GLES part of shaders (if any).
* Various RPi improvements, mainly in the context creation.
* Various AmigaOS4 improvement and workaround (but still in a beta state)
* Various improvement in GLX function, with a more accurate way to emulate GLXFBConfig
* Improved the way eglSurface are created in glx.c, to avoid try to create 2 on the same window (EGL doesn't allow that)
* Added LIBGL_GLXRECYCLE to not delete eglSurface and recycle them
* Added tracking of Framebuffers Object and Renderbuffers Objects
* Added (real) support for Float and Half-float Texture (including has attachement to FBO, emulating it if not supported in Hardware)
* Added support for Depth Stencil texture when attached to an FBO
* Added LIBGL_FBO=WxH for all platform
* Fixed some issue when resized textures attached to an FBO
* Added LIBGL_NODEPTHTEX to avoid using Depth Texture when available (using renderbuffer can be faster)
* Added support for Depth Texture when attached to an FBO (if supported by Hardware)
* Fixes some isue with blitting of FBO when size of Main Framebuffer changed
* Added option LIBGL_LOGSHADERERROR to get Shader compiler log and error
* Added support for (emulated) Hardware Instancing
* Added support for GL_ARB_draw_elements_base_vertex

##### v1.0.8
* Fixes and improvments to avoid unnecessary GLES state changes
* Fixes some memory issues with glBitmap
* Fixes to FPE (when using multitexture and GL_COMBINE)
* Added some TexEnv extension for GLES2 backend
* Fixes to Batch / Merger on GL_POLYGON primitives
* Fixes to LineStipple
* Pandora only: Fixed use of Texture Streaming on GLES2 backend

##### v1.0.6
* Factorised "Blit" function, and implemented `glBlitFramebuffer`
* Optimized `glBitmap`
* Added (limited) direct support to `GL_UNSIGNED_INT` for `glDrawElements` for hardware that support it
* Improved (a lot) `glBegin`/`glEnd` merger
* Added Anisotropic filtering support, for hardware that support it.
* Changed `LIBGL_BATCH`. It will now try to merge small (parametrable) subsequent `glDrawXXXX`
* Changed (simplified) the way texture "0" is handled
* Improvement to `glDrawArrays` and `glDrawElement`, with less copy of data
* WIP AmigaOS4 support (and BigEndian architecture)
* Improved NPOT support for "Limited NPOT" hardware
* Lots of FPE fixes
* Improve the way multi glX Context are handled
* Added basic pre-proc (only handle comments for now)
* Small optimization on when using `glDrawArrays` with GL_QUADS
* Improvement to GL_RENDER
* Improvement to line stipple
* Improvement to glPolygonMode(GL_LINE)
 
##### v1.0.4
 * FPE is now usable. Most function are implemented
 * ShaderConv in now usable. Basic GL 2 shader are supported
 * Refactored Texture cache and handling, for better Tex1D/Tex3D/TexRectangle handling

##### v1.0.2
 * Added GLES2 backend infrastructure
 * Begin GLES2 backend
 * Infrastructure for FPE (Fixed Pipeline Emulator)
 * Basic and Crude Shader convertor
 * Added blit function for GLES2 backend
 * Added some OpenGL Builtin VAs and Uniforms

##### 1.0.0
 * Removed old ES2 defines (ES2 will be dynamic later)

##### 0.9.8
 * Added TravisCI build on github
 * Added some optimization when to discard call to glBindTexture if useless (same texture) between 2 glBegin/glEnd blocks
 * Stubbed glGet with GL_DRAW_BUFFER
 * Improvement to Raster operations
 * Factorised Blit function (only 1 function for that now)
 * Tracking ShadeModel
 * Tracking TexEnv
 
##### 0.9.7
 * Tracking Clip Planes
 * Refactor Blitting function, and use glDrawTex extension if present
 * Restructured README and split in several files
 * Some improvments and fixes to LIBGL_BEGINEND=2 mode
 * Some improvments to some LIBGL_SHRINK mode
 * Proper support for DOT3 extension
 * Some fixes to Read/Draw Buffer handling
 * Some fix with the PixMap glX context creation
 
##### 0.9.6
 * Some fixes in GL_TEXTURE_RECTANGLE_ARB handling
 * Some other fixes in texture handling (unpack and glList related)
 * Some fix with the PBuffer glX context creation
 * Tracking of glFog
 * Exposed glBlendEquation if supported
 * New LIBGL_AVOID16BITS parameter to prefer 32bits texture (useful on ODroid)
 * Some optimisations in texture conversion

##### 0.9.5
 * Added some optimizations for sequential glBegin/glEnd blocks, with a switch to control them
 * Fixed many issue with Lights introduced with 0.9.4
 * Fixed Android build introduced with 0.9.4

##### 0.9.4
 * Fixed some extended functions (like glBlendFuncSeparate) not working inside list (fixing some issues with Batch mode)
 * Added back GL_TEXTURE_RECTANGLE_ARB handling (and using npot texture, even limited, if available)
 * Added tracking of Lights and Materials
 * Fixed (Added in fact) support for Multisampling on the GLX Context creation (a bit hacky, but seems to works)
 * Added LIBGL_NODOWNSAMPLING and associated Hint
 * Try to implement some caching on VAO to avoid some memcpy in renderlist (with a way to disable it just in case)

##### 0.9.3
 * Added support for Cube Mapping (with hardware support)
 * Improved Texture state tracking
 * Added LIBGL_NOTEXMAT env. var. switch for Texture Matrix handling
 * Added GL_EXT_vertex_array_bgra (and NEONinzed some loop)
 * Finished GL_EXT_direct_state_access extension
 * Mangled glX function (to be able to use apitrace to capture GL frames)
 * Return some values in glXQueryServerString, coherent with glXGetClientString

##### 0.9.2
 * All matrix are tracked now
 * Texture Matrix are 100% handled by gl4es. GLES Hardware keep an Identity matrix (TexCoord are transformed if needed). This allows a better handling of NPOT texture on hardware that doesn't support Full NPOT (fixed movies being horizontally shifted in openmw with LIBGL_NPOT=1 for example)

##### 0.9.1
 * Added gl4es specifics glHint capabilities. If the extension GL_GL4ES_hint is present, than a few Hint are accessible. Look in include/gl4eshint.h for the list.

##### 0.9.0
 * New name: gl4es
