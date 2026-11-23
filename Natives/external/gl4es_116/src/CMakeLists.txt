include_directories(util)

#file(GLOB_RECURSE GL_SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/gl/*.c)
SET(GL_SRC
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/arbconverter.c
	${CMAKE_CURRENT_SOURCE_DIR}/gl/arbgenerator.c
	${CMAKE_CURRENT_SOURCE_DIR}/gl/arbhelper.c
	${CMAKE_CURRENT_SOURCE_DIR}/gl/arbparser.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/array.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/blit.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/blend.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/buffers.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/build_info.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/debug.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/decompress.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/depth.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/directstate.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/drawing.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/enable.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/envvars.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/error_trace.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/eval.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/face.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/fog.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/fpe.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/fpe_cache.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/fpe_shader.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/framebuffers.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/gl_lookup.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/getter.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/gl4es.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/glstate.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/hint.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/init.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/light.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/line.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/list.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/listdraw.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/listrl.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/loader.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/logs.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/matrix.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/matvec.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/oldprogram.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/pixel.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/planes.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/pointsprite.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/preproc.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/program.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/queries.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/raster.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/render.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/samplers.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/shader.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/shaderconv.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/shader_hacks.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/stack.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/stencil.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/string_utils.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/stubs.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/texenv.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/texgen.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/texture.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/texture_compressed.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/texture_params.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/texture_read.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/texture_3d.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/uniform.c
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/vertexattrib.c
	${CMAKE_CURRENT_SOURCE_DIR}/gl/wrap/gl4eswraps.c
	${CMAKE_CURRENT_SOURCE_DIR}/gl/wrap/gles.c
	${CMAKE_CURRENT_SOURCE_DIR}/gl/wrap/glstub.c
	${CMAKE_CURRENT_SOURCE_DIR}/gl/math/matheval.c
)

SET(GL_H
    ${CMAKE_CURRENT_SOURCE_DIR}/../version.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/arbconverter.h
	${CMAKE_CURRENT_SOURCE_DIR}/gl/arbgenerator.h
	${CMAKE_CURRENT_SOURCE_DIR}/gl/arbhelper.h
	${CMAKE_CURRENT_SOURCE_DIR}/gl/arbparser.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/array.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/blend.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/blit.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/buffers.h
	${CMAKE_CURRENT_SOURCE_DIR}/gl/build_info.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/const.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/debug.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/decompress.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/depth.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/directstate.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/envvars.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/eval.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/face.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/fog.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/fpe.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/fpe_cache.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/fpe_shader.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/framebuffers.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/gl_lookup.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/gles.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/gl4es.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/glstate.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/hint.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/init.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/light.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/line.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/list.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/loader.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/logs.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/matrix.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/matvec.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/oldprogram.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/pixel.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/planes.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/pointsprite.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/preproc.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/program.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/queries.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/raster.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/render.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/samplers.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/shader.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/shaderconv.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/shader_hacks.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/stack.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/state.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/stencil.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/stb_dxt_104.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/string_utils.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/texenv.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/texgen.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/uniform.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/texture.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/vertexattrib.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/math/eval.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/wrap/gl4es.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/wrap/gles.h
    ${CMAKE_CURRENT_SOURCE_DIR}/gl/wrap/stub.h
)

if(${CMAKE_SYSTEM_NAME} MATCHES "Linux" AND NOT NO_LOADER)
    include_directories(glx)
#    aux_source_directory(glx GLX_SOURCES)
#    list(APPEND GL_SOURCES ${GLX_SOURCES})
    list(APPEND GL_SRC
        ${CMAKE_CURRENT_SOURCE_DIR}/glx/hardext.c
        ${CMAKE_CURRENT_SOURCE_DIR}/glx/gbm.c
	    ${CMAKE_CURRENT_SOURCE_DIR}/glx/glx.c
	    ${CMAKE_CURRENT_SOURCE_DIR}/glx/glx_stubs.c
	    ${CMAKE_CURRENT_SOURCE_DIR}/glx/lookup.c
        ${CMAKE_CURRENT_SOURCE_DIR}/glx/rpi.c
	    ${CMAKE_CURRENT_SOURCE_DIR}/glx/streaming.c
        ${CMAKE_CURRENT_SOURCE_DIR}/glx/utils.c
    )
    list(APPEND GL_H
        ${CMAKE_CURRENT_SOURCE_DIR}/glx/glx_gbm.h
        ${CMAKE_CURRENT_SOURCE_DIR}/glx/gbmfunc.h
        ${CMAKE_CURRENT_SOURCE_DIR}/glx/drmfunc.h
        ${CMAKE_CURRENT_SOURCE_DIR}/glx/glx.h
        ${CMAKE_CURRENT_SOURCE_DIR}/glx/hardext.h
        ${CMAKE_CURRENT_SOURCE_DIR}/glx/rpi.h
        ${CMAKE_CURRENT_SOURCE_DIR}/glx/streaming.h
        ${CMAKE_CURRENT_SOURCE_DIR}/glx/utils.h
    )
else()
    include_directories(glx)
    list(APPEND GL_SRC
        ${CMAKE_CURRENT_SOURCE_DIR}/glx/hardext.c
    )
    message(STATUS "Not on Linux: building without GLX support.")
endif()

if(AMIGAOS4)
    include_directories(agl)
    list(APPEND GL_SRC
        ${CMAKE_CURRENT_SOURCE_DIR}/glx/gbm.c
        ${CMAKE_CURRENT_SOURCE_DIR}/glx/glx.c
        ${CMAKE_CURRENT_SOURCE_DIR}/agl/lookup.c
        ${CMAKE_CURRENT_SOURCE_DIR}/agl/amigaos.c
        ${CMAKE_CURRENT_SOURCE_DIR}/agl/agl.c
    )
    list(APPEND GL_H
        ${CMAKE_CURRENT_SOURCE_DIR}/glx/hardext.h
        ${CMAKE_CURRENT_SOURCE_DIR}/glx/glx.h
        ${CMAKE_CURRENT_SOURCE_DIR}/agl/amigaos.h
        ${CMAKE_CURRENT_SOURCE_DIR}/agl/agl.h
    )
endif()

set_source_files_properties(${CMAKE_CURRENT_SOURCE_DIR}/gl/build_info.c PROPERTIES OBJECT_DEPENDS "${GL_SRC};${GL_H}")

if(${CMAKE_SYSTEM_NAME} MATCHES "Windows")
    if(STATICLIB)
        add_library(OPENGL32 STATIC ${GL_SRC})
    else()
        add_library(OPENGL32 SHARED ${GL_SRC})
        # some ES simulators used opengl32.dll :(
        set_target_properties(OPENGL32 PROPERTIES OUTPUT_NAME "GL32")
        set_target_properties(OPENGL32 PROPERTIES IMPORT_PREFIX "OPEN")
    endif()
elseif(STATICLIB)
    add_library(GL STATIC ${GL_SRC})
else()
    add_library(GL SHARED ${GL_SRC})
    
    if(${CMAKE_SYSTEM_NAME} MATCHES "Linux")
        if(NOX11)
            if(AMIGAOS4)
                target_link_libraries(GL m)
            else()
                target_link_libraries(GL m dl)
            endif()
        else()
            target_link_libraries(GL X11 m dl)
        endif()
    endif()
    if(USE_CLOCK)
        target_link_libraries(GL rt)
    endif()
    if(USE_ANDROID_LOG)
        target_link_libraries(GL ${log-lib})
    endif()
    
    if(CMAKE_SHARED_LIBRARY_SUFFIX MATCHES ".so")
        set_target_properties(GL PROPERTIES SUFFIX ".so.1")
    endif()
    if(APPLE OR CMAKE_SYSTEM_NAME MATCHES "Darwin|iOS")
        set_target_properties(GL PROPERTIES
            OUTPUT_NAME "gl4es_116"
            PREFIX "lib"
            SUFFIX ".dylib"
        )
    endif()
    install(TARGETS GL
      LIBRARY
      DESTINATION "/usr/lib/gl4es/"
    )
    install(FILES "../include/gl4esinit.h" "../include/gl4eshint.h"
      DESTINATION "/usr/include/gl4es/"
    )
endif()


SET(EGL_SRC
    ${CMAKE_CURRENT_SOURCE_DIR}/egl/egl.c
    ${CMAKE_CURRENT_SOURCE_DIR}/egl/lookup.c
)

SET(EGL_H
    ${CMAKE_CURRENT_SOURCE_DIR}/egl/egl.h
)

if(EGL_WRAPPER)
    add_library(EGL SHARED ${EGL_SRC})
    target_link_libraries(EGL GL dl)
    if(USE_ANDROID_LOG)
        target_link_libraries(EGL ${log-lib})
    endif()
    if(CMAKE_SHARED_LIBRARY_SUFFIX MATCHES ".so")
        set_target_properties(EGL PROPERTIES SUFFIX ".so.1")
    endif()
endif()

