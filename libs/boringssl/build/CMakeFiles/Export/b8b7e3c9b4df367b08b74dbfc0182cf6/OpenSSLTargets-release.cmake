#----------------------------------------------------------------
# Generated CMake target import file for configuration "Release".
#----------------------------------------------------------------

# Commands may need to know the format version.
set(CMAKE_IMPORT_FILE_VERSION 1)

# Import target "OpenSSL::Crypto" for configuration "Release"
set_property(TARGET OpenSSL::Crypto APPEND PROPERTY IMPORTED_CONFIGURATIONS RELEASE)
set_target_properties(OpenSSL::Crypto PROPERTIES
  IMPORTED_LINK_INTERFACE_LANGUAGES_RELEASE "ASM;C;CXX"
  IMPORTED_LOCATION_RELEASE "${_IMPORT_PREFIX}/lib64/libcrypto.a"
  )

list(APPEND _cmake_import_check_targets OpenSSL::Crypto )
list(APPEND _cmake_import_check_files_for_OpenSSL::Crypto "${_IMPORT_PREFIX}/lib64/libcrypto.a" )

# Import target "OpenSSL::SSL" for configuration "Release"
set_property(TARGET OpenSSL::SSL APPEND PROPERTY IMPORTED_CONFIGURATIONS RELEASE)
set_target_properties(OpenSSL::SSL PROPERTIES
  IMPORTED_LINK_INTERFACE_LANGUAGES_RELEASE "CXX"
  IMPORTED_LOCATION_RELEASE "${_IMPORT_PREFIX}/lib64/libssl.a"
  )

list(APPEND _cmake_import_check_targets OpenSSL::SSL )
list(APPEND _cmake_import_check_files_for_OpenSSL::SSL "${_IMPORT_PREFIX}/lib64/libssl.a" )

# Commands beyond this point should not need to know the version.
set(CMAKE_IMPORT_FILE_VERSION)
