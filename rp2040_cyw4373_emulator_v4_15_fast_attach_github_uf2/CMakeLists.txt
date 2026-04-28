cmake_minimum_required(VERSION 3.13)

# Инициализация Pico SDK
include($ENV{PICO_SDK_PATH}/external/pico_sdk_import.cmake)

project(rp2040_cyw4373_emulator_v4_15_fast_attach_github_uf2 C CXX ASM)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

pico_sdk_init()

add_executable(cyw4373_emulator_nohub_checked_v4_15
    src/main.c
    src/usb_descriptors.c
)

target_include_directories(cyw4373_emulator_nohub_checked_v4_15 PRIVATE src)

target_link_libraries(cyw4373_emulator_nohub_checked_v4_15
    pico_stdlib
    hardware_uart
    hardware_sync
    tinyusb_device
    tinyusb_board
)

pico_enable_stdio_usb(cyw4373_emulator_nohub_checked_v4_15 0)
pico_enable_stdio_uart(cyw4373_emulator_nohub_checked_v4_15 1)

pico_add_extra_outputs(cyw4373_emulator_nohub_checked_v4_15
