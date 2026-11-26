cmake_minimum_required(VERSION 3.5)
if(POLICY CMP0048)
    cmake_policy(SET CMP0048 NEW)
endif()

project(gl4es116_e2e_tests LANGUAGES C)

option(ENABLE_SANITIZERS "Enable ASan and UBSan on supported compilers" ON)
option(GL4ES_PRE_M1_SMOKE "Build pre-M1 smoke subset without gl4es_mem.h" OFF)

set(STATICLIB ON CACHE BOOL "" FORCE)
set(DEFAULT_ES 2 CACHE STRING "" FORCE)
set(NOX11 ON CACHE BOOL "" FORCE)
set(NOEGL ON CACHE BOOL "" FORCE)
set(NO_LOADER ON CACHE BOOL "" FORCE)
set(NO_INIT_CONSTRUCTOR ON CACHE BOOL "" FORCE)
set(GBM OFF CACHE BOOL "" FORCE)
set(NO_GBM ON CACHE BOOL "" FORCE)

set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")

set(GL4ES_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../Natives/external/gl4es_116")

add_definitions(
    -DSTATICLIB=1
    -DDEFAULT_ES=2
    -DNOX11=1
    -DNOEGL=1
    -DEGL_NO_X11=1
    -DNO_GBM=1
    -DNO_LOADER=1
    -DNO_INIT_CONSTRUCTOR=1
    -std=gnu11
)

if(CMAKE_C_COMPILER_ID MATCHES "Clang|GNU")
    add_compile_options(-Wno-pointer-sign -Wno-dangling-else -Wno-deprecated-declarations -Wno-date-time)
    if(CMAKE_C_COMPILER_ID MATCHES "Clang")
        add_compile_options(-Wno-error=implicit-function-declaration)
    endif()
    if(ENABLE_SANITIZERS AND NOT WIN32)
        add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer -g -O1)
        add_link_options(-fsanitize=address,undefined)
    elseif(ENABLE_SANITIZERS AND WIN32)
        add_compile_options(-fsanitize=undefined -fno-omit-frame-pointer -g -O1)
        add_link_options(-fsanitize=undefined)
    endif()
endif()

include_directories(
    "${GL4ES_ROOT}/include"
    "${GL4ES_ROOT}/src/gl"
    "${GL4ES_ROOT}/src/glx"
    "${GL4ES_ROOT}/src/util"
    "${CMAKE_CURRENT_SOURCE_DIR}"
)

if(WIN32 AND CMAKE_C_COMPILER_ID MATCHES "Clang|GNU")
    add_compile_options(-DWIN_ALLOC_SHIM_WRAP=1 -include "${CMAKE_CURRENT_SOURCE_DIR}/win_alloc_shim.h")
endif()

add_subdirectory("${GL4ES_ROOT}/src" "${CMAKE_BINARY_DIR}/gl4es_116_src" EXCLUDE_FROM_ALL)

set_target_properties(GL PROPERTIES
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

add_executable(gl4es116_test_harness
    "${CMAKE_CURRENT_SOURCE_DIR}/gl4es116_test_harness.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/mock_gles2.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/win_alloc_shim.c"
)

if(GL4ES_PRE_M1_SMOKE)
    target_compile_definitions(gl4es116_test_harness PRIVATE GL4ES_PRE_M1_SMOKE=1)
endif()

target_link_libraries(gl4es116_test_harness PRIVATE GL m pthread)
if(CMAKE_SYSTEM_NAME MATCHES "Linux")
    target_link_libraries(gl4es116_test_harness PRIVATE dl)
endif()

enable_testing()
file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/psa")

if(GL4ES_PRE_M1_SMOKE)
    set(HARNESS_SUITES
        tier1_leaks
        tier1_fpe_invariants
        tier1_ibo_stream
        tier2_bounds
        tier3_pairwise
    )
else()
    set(HARNESS_SUITES
        tier1_mem_low
        tier1_mem_medium
        tier1_mem_high
        tier1_mem_auto
        tier1_mem_budget
        tier1_trim
        tier1_leaks
        tier1_caps
        tier1_fpe_cache
        tier1_fpe_invariants
        tier1_ibo_stream
        tier1_draw_upload
        tier2_bounds
        tier3_pairwise
        tier4_village_low
        tier4_village_high
        tier4_multicontext
        tier4_entity_hotpath
    )
endif()

foreach(SUITE ${HARNESS_SUITES})
    add_test(NAME "${SUITE}" COMMAND $<TARGET_FILE:gl4es116_test_harness> --suite "${SUITE}")
    set_tests_properties("${SUITE}" PROPERTIES
        ENVIRONMENT "LIBGL_NOBANNER=1;AMETHYST_GL4ES_ERROR_TRACE=0;LIBGL_BEGINEND=1;LIBGL_PSA_FOLDER=${CMAKE_BINARY_DIR}/psa"
    )
endforeach()
