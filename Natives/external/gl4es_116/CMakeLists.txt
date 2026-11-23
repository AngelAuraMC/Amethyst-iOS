cmake_minimum_required(VERSION 2.8.12)

project(gl4es LANGUAGES C)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/bin)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/lib)
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/lib)

link_directories(${CMAKE_LIBRARY_OUTPUT_DIRECTORY})

option(PANDORA "Set to ON if targeting an OpenPandora device" ${PANDORA})
option(PYRA "Set to ON if targeting an Dragonbox Pyra device" ${PYRA})
option(BCMHOST "Set to ON if targeting an RPi(2) device" ${BCMHOST})
option(ODROID "Set to ON if targeting an ODroid device" ${ODROID})
option(GOA_CLONE "Set to ON if targeting GO Advance clones, like RG351p/v, Gameforce Chi, RGB10..." ${GOA_CLONE})
option(ANDROID "Set to ON if targeting an Android device" ${ANDROID})
option(CHIP "Set to ON if targeting an C.H.I.P. device" ${CHIP})
option(AMIGAOS4 "Set to ON if targeting an AmigaOS4/Warp3D platform (activate NOEGL and NOX11)" ${AMIGAOS4})
option(NOX11 "Set to ON to not use X11 (creation of context has to be done outside gl4es)" ${NOX11})
option(NOEGL "Set to ON to not use EGL (all functions are taken in GLES library)" ${NOEGL})
option(STATICLIB "Set to ON to build a static version of gl4es" ${STATICLIB})
option(GBM "Set to ON to not build GBM interface" ${GBM})
option(USE_CCACHE "Set to ON to use ccache if present in the system" ${USE_CCACHE})
option(USE_CLOCK "Set to ON to use clock_gettime instead of gttimeofday for LIBGL_FPS" ${USE_CLOCK})
option(NO_LOADER "disable library loader (useful for static library with NOEGL, NOX11, use include/gl4esinit.h)" ${NO_LOADER})
option(NO_INIT_CONSTRUCTOR "disable automatic initialization (useful for static library, use include/gl4esinit.h)" ${NO_INIT_CONSTRUCTOR})
option(USE_ANDROID_LOG "Set to ON to use Android log instead of stdio" ${USE_ANDROID_LOG})
option(EGL_WRAPPER "Set to ON to build EGL wrapper" ${EGL_WRAPPER})
option(GLX_STUBS "Set to ON to build GLX function stubs" ${GLX_STUBS})

include(CheckSymbolExists)
check_symbol_exists(backtrace "execinfo.h" HAS_BACKTRACE)
if (HAS_BACKTRACE)
    add_definitions(-DHAS_BACKTRACE)
endif()

if(CMAKE_SYSTEM_NAME MATCHES "Windows" OR CMAKE_SYSTEM_NAME MATCHES "MSYS")
    set(NOX11 ON)
    set(NO_GBM ON)
    set(WIN32_PLATFORM ON)
    if(CMAKE_C_COMPILER_ID MATCHES "MSVC" OR "x${CMAKE_C_SIMULATE_ID}" STREQUAL "xMSVC")
        set(WIN32_MSVC ON)  #msvc or icl or clang-cl
    endif()
endif()

# Pandora
if(PANDORA)
    add_definitions(-DPANDORA)
    add_definitions(-DTEXSTREAM)
    add_definitions(-mcpu=cortex-a8 -mfpu=neon -mfloat-abi=softfp -ftree-vectorize -fsingle-precision-constant -ffast-math)
    set(NO_GBM ON)
endif()

if((NOT GBM) OR PANDORA)
    set(NO_GBM ON)
else()
    set(NO_GBM OFF)
endif()


if(NOT DEFAULT_ES)
    if(PANDORA)
        set(DEFAULT_ES 1)
    else()
        set(DEFAULT_ES 2)
    endif()
endif()

if(STATICLIB)
    add_definitions(-DSTATICLIB)
endif(STATICLIB)

# Pyra
if(PYRA)
    add_definitions(-DPYRA)
    set(USE_CLOCK ON)
    #add_definitions(-DTEXSTREAM)
    add_definitions(-mcpu=cortex-a15 -mfpu=neon-vfpv4 -mfloat-abi=hard -ftree-vectorize -fsingle-precision-constant -ffast-math)
    set(NO_GBM ON)
endif()

# Raspberry PI
if(BCMHOST)
    include_directories(/opt/vc/include /opt/vc/include/interface/vcos/pthreads /opt/vc/include/interface/vmcs_host/linux)
    link_directories(/opt/vc/lib)
    add_definitions(-DBCMHOST)
endif()

# ODROID
if(ODROID)
    add_definitions(-DODROID)
endif()

# GOA_CLONE
if(GOA_CLONE)
    add_definitions(-DGOA_CLONE)
    add_definitions(-mcpu=cortex-a35 -mfpu=neon-vfpv3 -march=armv8-a+crc+simd+crypto -mfloat-abi=hard -ftree-vectorize -fsingle-precision-constant -ffast-math)
    set(EGL_WRAPPER ON)
    set(GLX_STUBS ON)
endif()

# Android
if(ANDROID)
    add_definitions(-DANDROID)
    add_definitions(-DNOX11 -DNO_GBM -DDEFAULT_ES=2)
endif()

if(USE_ANDROID_LOG)
    add_definitions(-DUSE_ANDROID_LOG)
    find_library(log-lib log)
endif()

#PocketCHIP
if(CHIP)
    add_definitions(-DCHIP)
    add_definitions(-mcpu=cortex-a8 -mfpu=neon -mfloat-abi=hard -ftree-vectorize -fsingle-precision-constant -ffast-math)
endif()

# AmigaOS4
if(AMIGAOS4)
    set(CMAKE_C_COMPILER "ppc-amigaos-gcc")
    set(CMAKE_CXX_COMPILER "ppc-amigaos-g++")
    set(CMAKE_LINKER "ppc-amigaos-ld")
    set(CMAKE_AR "ppc-amigaos-ar")
    set(CMAKE_RANLIB "ppc-amigaos-ranlib")
    add_definitions(-DAMIGAOS4)
    set(NOX11 ON)
    set(NOEGL ON)
    set(NO_GBM ON)
    set(CMAKE_C_FLAGS_DEBUG "-O1 -gstabs")
    set(CMAKE_C_FLAGS_RELWITHDEBINFO "-O2 -gstabs")
endif()

#NOX11
if(NOX11)
    add_definitions(-DEGL_NO_X11)
    add_definitions(-DNOX11)
endif()

#NOEGL
if(NOEGL)
    add_definitions(-DNOEGL)
    add_definitions(-DNOX11)
endif()

if(NOT NO_GBM)
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(KMSDRM REQUIRED libdrm gbm egl)
    link_directories(${KMSDRM_LIBRARY_DIRS})
    include_directories(${KMSDRM_INCLUDE_DIRS})
endif()

if(NO_GBM)
    add_definitions(-DNO_GBM)
endif()

#NOX11
if(USE_CLOCK)
    add_definitions(-DUSE_CLOCK)
endif()

if(NO_LOADER)
    add_definitions(-DNO_LOADER)
endif()

if(NO_INIT_CONSTRUCTOR)
    add_definitions(-DNO_INIT_CONSTRUCTOR)
endif()

if(GLX_STUBS)
    add_definitions(-DGLX_STUBS)
endif()

#DEFAULT_ES=2
if(DEFAULT_ES EQUAL 2)
    add_definitions(-DDEFAULT_ES=2)
endif()
if(DEFAULT_ES EQUAL 1)
    add_definitions(-DDEFAULT_ES=1)
endif()
if(USE_CCACHE)
    find_program(CCACHE_FOUND ccache)
    if(CCACHE_FOUND)
        set_property(GLOBAL PROPERTY RULE_LAUNCH_COMPILE ccache)
        set_property(GLOBAL PROPERTY RULE_LAUNCH_LINK ccache)
    endif()
endif()

link_directories(${CMAKE_SOURCE_DIR}/lib)
if(NOT WIN32_MSVC)
    add_definitions(-std=gnu11 -funwind-tables)
    if(APPLE OR CMAKE_SYSTEM_NAME MATCHES "Darwin|iOS")
       add_definitions(-fvisibility=default)
    elseif(NOT WIN32_PLATFORM)
       add_definitions(-fvisibility=hidden)
    else()
       set(CMAKE_SHARED_LINKER_FLAGS "-Wl,--exclude-all-symbols,--kill-at")
    endif()
elseif(CMAKE_C_COMPILER_ID MATCHES "Clang")
    add_definitions(-Wno-deprecated-declarations) #strdup
    add_definitions(-Wno-unused-function -Wno-unused-variable -Wno-dangling-else)
    add_definitions(-Wno-implicit-const-int-float-conversion)
    add_definitions(-Wno-visibility)
else()
    if(CMAKE_C_COMPILER_ID MATCHES "Intel")
        add_definitions(-wd1786 -wd589 -wd537 -wd118 -wd2722)
    else()
        add_definitions(-wd4996 -wd4244 -wd4267 -wd4098 -wd4018)
    endif()
    add_definitions("-Dinline=__inline" "-D__func__=__FUNCTION__") # for VC<=13
endif()

if (CMAKE_C_COMPILER_ID MATCHES "Clang" OR CMAKE_SYSTEM_NAME MATCHES "Emscripten")
    add_definitions(-Wno-pointer-sign -Wno-dangling-else)
endif()

include_directories(include)
add_subdirectory(src)

enable_testing()

macro(create_test test_name test_filename calls_count tolerance)
    if (${ARGC} EQUAL 5)
        add_test(${test_name}
            ${CMAKE_COMMAND}
            -D LIBRARY_FOLDER=${CMAKE_LIBRARY_OUTPUT_DIRECTORY}
            -D TESTS_DIRECTORY=${CMAKE_SOURCE_DIR}/tests
            -D TEST_FILENAME=${test_filename}
            -D CALLS=${calls_count}
            -D TOLERANCE=${tolerance}
            -D EXTRACT_RANGE=${ARGV4}
            -P ${CMAKE_SOURCE_DIR}/test.cmake)
    elseif (${ARGC} EQUAL 6)
        if (${ARGV4} STREQUAL "NOEXTRACT_RANGE")
            add_test(${test_name}
                ${CMAKE_COMMAND}
                -D LIBRARY_FOLDER=${CMAKE_LIBRARY_OUTPUT_DIRECTORY}
                -D TESTS_DIRECTORY=${CMAKE_SOURCE_DIR}/tests
                -D TEST_FILENAME=${test_filename}
                -D CALLS=${calls_count}
                -D TOLERANCE_GLES1=${tolerance}
                -D TOLERANCE_GLES2=${ARGV5}
                -P ${CMAKE_SOURCE_DIR}/test.cmake)
        else (${ARGV4} STREQUAL "NOEXTRACT_RANGE")
            add_test(${test_name}
                ${CMAKE_COMMAND}
                -D LIBRARY_FOLDER=${CMAKE_LIBRARY_OUTPUT_DIRECTORY}
                -D TESTS_DIRECTORY=${CMAKE_SOURCE_DIR}/tests
                -D TEST_FILENAME=${test_filename}
                -D CALLS=${calls_count}
                -D TOLERANCE_GLES1=${tolerance}
                -D TOLERANCE_GLES2=${ARGV5}
                -D EXTRACT_RANGE=${ARGV4}
                -P ${CMAKE_SOURCE_DIR}/test.cmake)
        endif (${ARGV4} STREQUAL "NOEXTRACT_RANGE")
    else (${ARGC} EQUAL 5)
        add_test(${test_name}
            ${CMAKE_COMMAND}
            -D LIBRARY_FOLDER=${CMAKE_LIBRARY_OUTPUT_DIRECTORY}
            -D TESTS_DIRECTORY=${CMAKE_SOURCE_DIR}/tests
            -D TEST_FILENAME=${test_filename}
            -D CALLS=${calls_count}
            -D TOLERANCE=${tolerance}
            -P ${CMAKE_SOURCE_DIR}/test.cmake)
    endif (${ARGC} EQUAL 5)
endmacro(create_test)

macro(create_test_GLES test_name GLES test_filename calls_count tolerance)
    if (${ARGC} EQUAL 5)
        add_test(${test_name}_GLES${GLES}
            ${CMAKE_COMMAND}
            -D LIBRARY_FOLDER=${CMAKE_LIBRARY_OUTPUT_DIRECTORY}
            -D TESTS_DIRECTORY=${CMAKE_SOURCE_DIR}/tests
            -D TEST_FILENAME=${test_filename}
            -D CALLS=${calls_count}
            -D TOLERANCE=${tolerance}
            -D EXTRACT_RANGE=${ARGV4}
            -D GLES_FORCED=${GLES}
            -P ${CMAKE_SOURCE_DIR}/test.cmake)
    else (${ARGC} EQUAL 5)
        add_test(${test_name}_GLES${GLES}
            ${CMAKE_COMMAND}
            -D LIBRARY_FOLDER=${CMAKE_LIBRARY_OUTPUT_DIRECTORY}
            -D TESTS_DIRECTORY=${CMAKE_SOURCE_DIR}/tests
            -D TEST_FILENAME=${test_filename}
            -D CALLS=${calls_count}
            -D TOLERANCE=${tolerance}
            -D GLES_FORCED=${GLES}
            -P ${CMAKE_SOURCE_DIR}/test.cmake)
    endif (${ARGC} EQUAL 5)
endmacro(create_test_GLES)

create_test(GLXgears glxgears "0000008203" 25 "NOEXTRACT_RANGE" 700)
create_test(StuntCarRacer stuntcarracer "0000118817" 20 "638x478+1+1")
create_test(Neverball neverball "0000078750" 20 "798x478+1+1" 200)
create_test(FoobillardPlus foobillardplus "0000014748" 50 "798x478+1+1" 60)
create_test(Descent3 descent3 "0000284192" 20 "638x478+1+1")
create_test(PointSprite pointsprite "0000248810" 20)

#create_test_GLES(Neverball 2 neverball "0000078750" 200 "798x478+1+1")
create_test_GLES(OpenRA 2 openra "0000031249" 20 "638x478+1+1")
create_test_GLES(GLSL_lighting 2 glsl_lighting "0000505393" 20)
