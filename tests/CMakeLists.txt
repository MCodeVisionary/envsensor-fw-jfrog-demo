add_executable(test_crc test_crc.c ${CMAKE_SOURCE_DIR}/src/crc.c)
target_include_directories(test_crc PRIVATE ${CMAKE_SOURCE_DIR}/include)
add_test(NAME crc16_known_vectors COMMAND test_crc)
