# - Try to find Foo
# Once done, this will define
#
#  Foo_FOUND - system has Foo
#  Foo_INCLUDE_DIRS - the Foo include directories
#  Foo_LIBRARIES - link these to use Foo

include(LibFindMacros)

# Use pkg-config to get hints about paths
libfind_pkg_check_modules(Foo_PKGCONF Foo)

# Include dir
find_path(Foo_INCLUDE_DIR
  NAMES Foo.h
  PATHS ${Foo_PKGCONF_INCLUDE_DIRS}
)

# Finally the library itself
find_library(Foo_LIBRARY
  NAMES Foo
  PATHS ${Foo_PKGCONF_LIBRARY_DIRS}
)

# Set the include dir variables and the libraries and let libfind_process do the rest.
# NOTE: Singular variables for this library, plural for libraries this this lib depends on.
set(Foo_PROCESS_INCLUDES Foo_INCLUDE_DIR)
set(Foo_PROCESS_LIBS Foo_LIBRARY)

libfind_process(Foo)