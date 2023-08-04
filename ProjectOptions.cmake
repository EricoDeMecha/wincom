include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(wincom_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(wincom_setup_options)
  option(wincom_ENABLE_HARDENING "Enable hardening" ON)
  option(wincom_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    wincom_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    wincom_ENABLE_HARDENING
    OFF)

  wincom_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR wincom_PACKAGING_MAINTAINER_MODE)
    option(wincom_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(wincom_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(wincom_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(wincom_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(wincom_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(wincom_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(wincom_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(wincom_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(wincom_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(wincom_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(wincom_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(wincom_ENABLE_PCH "Enable precompiled headers" OFF)
    option(wincom_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(wincom_ENABLE_IPO "Enable IPO/LTO" ON)
    option(wincom_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(wincom_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(wincom_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(wincom_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(wincom_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(wincom_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(wincom_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(wincom_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(wincom_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(wincom_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(wincom_ENABLE_PCH "Enable precompiled headers" OFF)
    option(wincom_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      wincom_ENABLE_IPO
      wincom_WARNINGS_AS_ERRORS
      wincom_ENABLE_USER_LINKER
      wincom_ENABLE_SANITIZER_ADDRESS
      wincom_ENABLE_SANITIZER_LEAK
      wincom_ENABLE_SANITIZER_UNDEFINED
      wincom_ENABLE_SANITIZER_THREAD
      wincom_ENABLE_SANITIZER_MEMORY
      wincom_ENABLE_UNITY_BUILD
      wincom_ENABLE_CLANG_TIDY
      wincom_ENABLE_CPPCHECK
      wincom_ENABLE_COVERAGE
      wincom_ENABLE_PCH
      wincom_ENABLE_CACHE)
  endif()

  wincom_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (wincom_ENABLE_SANITIZER_ADDRESS OR wincom_ENABLE_SANITIZER_THREAD OR wincom_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(wincom_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(wincom_global_options)
  if(wincom_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    wincom_enable_ipo()
  endif()

  wincom_supports_sanitizers()

  if(wincom_ENABLE_HARDENING AND wincom_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR wincom_ENABLE_SANITIZER_UNDEFINED
       OR wincom_ENABLE_SANITIZER_ADDRESS
       OR wincom_ENABLE_SANITIZER_THREAD
       OR wincom_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${wincom_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${wincom_ENABLE_SANITIZER_UNDEFINED}")
    wincom_enable_hardening(wincom_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(wincom_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(wincom_warnings INTERFACE)
  add_library(wincom_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  wincom_set_project_warnings(
    wincom_warnings
    ${wincom_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(wincom_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    configure_linker(wincom_options)
  endif()

  include(cmake/Sanitizers.cmake)
  wincom_enable_sanitizers(
    wincom_options
    ${wincom_ENABLE_SANITIZER_ADDRESS}
    ${wincom_ENABLE_SANITIZER_LEAK}
    ${wincom_ENABLE_SANITIZER_UNDEFINED}
    ${wincom_ENABLE_SANITIZER_THREAD}
    ${wincom_ENABLE_SANITIZER_MEMORY})

  set_target_properties(wincom_options PROPERTIES UNITY_BUILD ${wincom_ENABLE_UNITY_BUILD})

  if(wincom_ENABLE_PCH)
    target_precompile_headers(
      wincom_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(wincom_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    wincom_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(wincom_ENABLE_CLANG_TIDY)
    wincom_enable_clang_tidy(wincom_options ${wincom_WARNINGS_AS_ERRORS})
  endif()

  if(wincom_ENABLE_CPPCHECK)
    wincom_enable_cppcheck(${wincom_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(wincom_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    wincom_enable_coverage(wincom_options)
  endif()

  if(wincom_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(wincom_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(wincom_ENABLE_HARDENING AND NOT wincom_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR wincom_ENABLE_SANITIZER_UNDEFINED
       OR wincom_ENABLE_SANITIZER_ADDRESS
       OR wincom_ENABLE_SANITIZER_THREAD
       OR wincom_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    wincom_enable_hardening(wincom_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
