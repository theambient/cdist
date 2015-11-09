
cmake_minimum_required(VERSION 2.8)

project(bar)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}/cmake_modules/")

message(STATUS "CMAKE_SYSTEM_INCLUDE_PATH: ${CMAKE_SYSTEM_INCLUDE_PATH}")
message(STATUS "CMAKE_SYSTEM_LIBRARY_PATH: ${CMAKE_SYSTEM_LIBRARY_PATH}")

find_package(Foo REQUIRED)

include_directories(${Foo_INCLUDE_DIRS})

add_executable(
	bar

	src/bar.cpp
)

target_link_libraries(bar ${Foo_LIBRARIES})
