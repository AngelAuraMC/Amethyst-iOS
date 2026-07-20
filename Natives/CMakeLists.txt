cmake_minimum_required(VERSION 3.6)
project(AngelAuraAmethyst)

configure_file(${CMAKE_CURRENT_LIST_DIR}/config.h.in ${CMAKE_CURRENT_LIST_DIR}/config.h)

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -target arm64-apple-ios -mcpu=apple-a8 -fcommon -fobjc-arc -ObjC -Wno-error=implicit-function-declaration -F'${CMAKE_OSX_SYSROOT}/System/Cryptexes/OS/System/Library/Frameworks' -mios-version-min=16.0")
set(CMAKE_C_FLAGS_DEBUG "-funwind-tables -g")

if("${CMAKE_HOST_SYSTEM_NAME}" MATCHES "Linux|^GNU$|Android")
set(GLOBAL_LDFLAGS "-isysroot ${CMAKE_OSX_SYSROOT} -Wl,-syslibroot,${CMAKE_OSX_SYSROOT} -fuse-ld=lld")
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${GLOBAL_LDFLAGS}")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${GLOBAL_LDFLAGS}")
endif()

include_directories(
  "."
  "external/AFNetworking/AFNetworking"
  "external/AFNetworking/UIKit+AFNetworking"
  "external/DBNumberedSlider/Classes"
  "external/NRFileManager"
  "external/UnzipKit/Source"
  "external/fishhook"
  "external/lzma"
  "external/mesa"
  "external/AltKit"
  "external/Apple"
  "external/ballpa1n"
  "external/ballpa1n/wrapped"
  "external/mach"
)

# For cacio support library
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -rpath @loader_path -rpath @executable_path/java_runtimes/java-8-openjdk/lib -rpath /usr/lib/jvm/java-8-openjdk/lib")

# EXT: stub library, delete after compile awt_xawt
add_library(awt_headless SHARED
  awt_xawt/empty.m
)
target_link_libraries(awt_headless)

# EXT: cacio support library
add_library(awt_xawt SHARED
  awt_xawt/xawt_fake.m
)
target_link_libraries(awt_xawt
  "-L'${CMAKE_CURRENT_LIST_DIR}/build'"
  awt_headless
)

set(CMAKE_FRAMEWORK_PATH "${CMAKE_CURRENT_LIST_DIR}/resources/Frameworks")

set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -rpath @executable_path/Frameworks -rpath @loader_path/Frameworks -Wl,-undefined,dynamic_lookup")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -rpath @executable_path/Frameworks -rpath @loader_path/Frameworks")

# ANGLE wrapper for 1.17+
add_library(tinygl4angle SHARED
  external/gl4es/string_utils.c
  external/gl4es/tinygl4angle.c
)
target_link_libraries(tinygl4angle
  "${GLOBAL_LDFLAGS}"
  "-F'${CMAKE_CURRENT_LIST_DIR}/resources/Frameworks'"
  "-framework libEGL"
  "-framework libGLESv2"
)

# LTW (Large Thin Wrapper) - OpenGL core-to-ES wrapper
set(LTW_DIR "${CMAKE_CURRENT_LIST_DIR}/external/LTW/ltw/src/main/tinywrapper")
set(LTW_INCLUDES
  "${LTW_DIR}"
  "${LTW_DIR}/GL"
  "${CMAKE_CURRENT_LIST_DIR}/cmake/ltw_compat"
  "${LTW_DIR}/glsl_optimizer/include"
  "${LTW_DIR}/glsl_optimizer/src"
  "${LTW_DIR}/vgpu_shaderconv"
  "${LTW_DIR}/unordered_map"
  "${CMAKE_CURRENT_LIST_DIR}/external/MobileGlues/src/main/cpp/include"
)

include(cmake/ltw_sources.cmake)

add_library(glsl_optimizer STATIC ${GLSL_OPTIMIZER_SRC})
target_include_directories(glsl_optimizer PRIVATE ${LTW_INCLUDES})
set_target_properties(glsl_optimizer PROPERTIES
  POSITION_INDEPENDENT_CODE ON
  CXX_STANDARD 17
  C_STANDARD 11
)
target_compile_definitions(glsl_optimizer PRIVATE
  _LIB NOMINMAX _USE_MATH_DEFINES __STDC_NO_THREADS__
  __STDC_LIMIT_MACROS __STDC_FORMAT_MACROS __STDC_CONSTANT_MACROS
  UTL_ARCH_LITTLE_ENDIAN UNIX
  HAVE_OPENGL HAVE_OPENGL_ES_1 HAVE_OPENGL_ES_2
  HAVE_TIMESPEC_GET HAVE_STRUCT_TIMESPEC
  VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK=VK_DESCRIPTOR_TYPE_INLINE_UNIFORM_BLOCK_EXT
)

add_library(ltw SHARED ${LTW_CORE_SRC})
target_include_directories(ltw PRIVATE ${LTW_INCLUDES})
target_link_libraries(ltw
  "${GLOBAL_LDFLAGS}"
  glsl_optimizer
  "-F'${CMAKE_CURRENT_LIST_DIR}/resources/Frameworks'"
  "-framework libEGL"
  "-framework libGLESv2"
)
set_target_properties(ltw PROPERTIES
  C_STANDARD 11
  C_STANDARD_REQUIRED ON
)
target_compile_definitions(ltw PRIVATE
  _LIB NOMINMAX _USE_MATH_DEFINES __STDC_NO_THREADS__
  __STDC_LIMIT_MACROS __STDC_FORMAT_MACROS __STDC_CONSTANT_MACROS
  UTL_ARCH_LITTLE_ENDIAN UNIX
  HAVE_OPENGL HAVE_OPENGL_ES_1 HAVE_OPENGL_ES_2
)

# AFNetworking
add_library(AFNetworking SHARED
  external/AFNetworking/AFNetworking/AFSecurityPolicy.m
  external/AFNetworking/AFNetworking/AFHTTPSessionManager.m
  external/AFNetworking/AFNetworking/AFURLRequestSerialization.m
  external/AFNetworking/AFNetworking/AFURLSessionManager.m
  external/AFNetworking/AFNetworking/AFNetworkReachabilityManager.m
  external/AFNetworking/AFNetworking/AFURLResponseSerialization.m
  external/AFNetworking/UIKit+AFNetworking/AFNetworkActivityIndicatorManager.m
  external/AFNetworking/UIKit+AFNetworking/AFAutoPurgingImageCache.m
  external/AFNetworking/UIKit+AFNetworking/AFImageDownloader.m
  external/AFNetworking/UIKit+AFNetworking/UIButton+AFNetworking.m
  external/AFNetworking/UIKit+AFNetworking/UIImageView+AFNetworking.m
)
target_link_libraries(AFNetworking
  "-framework CoreGraphics"
  "-framework CoreServices"
  "-framework Security"
  "-framework SystemConfiguration"
  "-framework UIKit"
)

# MinecraftAccount JNI
add_library(AmethystAccountJNI SHARED
  authenticator/MinecraftAccountJNI.m
)
target_link_libraries(AmethystAccountJNI)

# Audio capture JNI bridge
add_library(audio_capture SHARED
  audio_capture_bridge.m
)
target_link_libraries(audio_capture
  "-framework AVFoundation"
)

# Angel Aura Amethyst
add_executable(AngelAuraAmethyst
  dyld_bypass_validation.m
  dyld_patch_platform.m
  main.m
  main_hook.m
  JavaLauncher.m
  external/fishhook/fishhook.c
  UIKit+hook.m

  authenticator/BaseAuthenticator.m
  authenticator/LocalAuthenticator.m
  authenticator/MicrosoftAuthenticator.m

  ctxbridges/gl_bridge.m
  ctxbridges/osm_bridge.m
  ctxbridges/vk_bridge.m

  debug/DebugServer.m
 
  customcontrols/ControlButton.m
  customcontrols/ControlDrawer.m
  customcontrols/ControlJoystick.m
  customcontrols/ControlLayout.m
  customcontrols/ControlSubButton.m
  customcontrols/CustomControlsUtils.m
  customcontrols/NSPredicateUtilitiesExternal.m

  external/DBNumberedSlider/Classes/DBNumberedSlider.m
  external/NRFileManager/NSFileManager+NRFileManager.m
  external/ballpa1n/HostManager.c
  external/ballpa1n/wrapped/HostManagerBridge.m
  external/mach/mach_excServer.c

  installer/FabricInstallViewController.m
  installer/ForgeInstallViewController.m
  installer/ModpackInstallViewController.m
  installer/FabricUtils.m
  installer/modpack/ModpackUtils.m
  installer/modpack/ModpackAPI.m
  installer/modpack/CurseForgeAPI.m
  installer/modpack/ModrinthAPI.m

  input/ControllerInput.m
  input/GyroInput.m
  input/KeyboardInput.m

  AccountListViewController.m
  AppDelegate.m
  CustomControlsViewController.m
  CustomControlsViewController+UndoManager.m
  DownloadProgressViewController.m
  FileListViewController.m
  GameSurfaceView.m
  JavaGUIViewController.m
  LauncherMenuViewController.m
  LauncherNavigationController.m
  LauncherNewsViewController.m
  LauncherPreferences.m
  LauncherPreferencesViewController.m
  LauncherPrefContCfgViewController.m
  LauncherPrefGameDirViewController.m
  LauncherPrefManageJREViewController.m
  LauncherProfileEditorViewController.m
  LauncherProfilesViewController.m
  LauncherSplitViewController.m
  MinecraftResourceDownloadTask.m
  MinecraftResourceUtils.m
  PickTextField.m
  PLLogOutputView.m
  PLPickerView.m
  PLPreferences.m
  PLPrefTableViewController.m
  PLProfiles.m
  SceneDelegate.m
  SceneExternalDelegate.m
  SurfaceViewController.m
  SurfaceViewController+ExternalDisplay.m
  SurfaceViewController+LogView.m
  SurfaceViewController+Navigation.m
  TrackedTextField.m
   egl_bridge.m
   ZinkConfig.m
   input_bridge_v3.m
  ios_uikit_bridge.m
  utils.m
)

if("${CMAKE_HOST_SYSTEM_NAME}" MATCHES "Linux|^GNU$|Android")
target_sources(AngelAuraAmethyst PUBLIC non_darwin_utils.m)
endif()

target_link_libraries(AngelAuraAmethyst
  PUBLIC AFNetworking
  lzma
  "-F'${CMAKE_CURRENT_LIST_DIR}/build'"
  "-F'${CMAKE_CURRENT_LIST_DIR}/resources/Frameworks'"
  "-framework AltKit"
  "-framework AuthenticationServices"
  "-framework AVFoundation"
  "-framework CAltKit"
  "-framework CoreFoundation"
  "-framework CoreGraphics"
  "-framework CoreImage"
  "-framework CoreMotion"
  "-framework GameController"
  "-framework IOKit"
  "-framework QuartzCore"
  "-framework Security"
  "-framework UIKit"
  "-framework UniformTypeIdentifiers"
  "-framework UnzipKit"
  "-framework WebKit"
  "-weak_framework SafariServices"
)
set_target_properties(AngelAuraAmethyst PROPERTIES
  MACOSX_BUNDLE TRUE
  MACOSX_FRAMEWORK_IDENTIFIER org.cmake.ExecutableTarget
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_LIST_DIR}/Info.plist")
