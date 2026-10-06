find_program(DBUS_RUN_SESSION dbus-run-session REQUIRED)
add_subdirectory(extension)

add_executable(artwork-tests helper/artwork-loader-test.cpp)
# The decoders themselves are tested in-process; the helper never links them.
target_link_libraries(artwork-tests PRIVATE island_core island_image Qt6::Test)
target_compile_definitions(artwork-tests PRIVATE DECODER_PATH="$<TARGET_FILE:nookisle-artwork-decoder>"
    FETCH_PATH="$<TARGET_FILE:nookisle-artwork-fetch>")
add_dependencies(artwork-tests nookisle-artwork-decoder nookisle-artwork-fetch)
add_test(NAME helper-artwork COMMAND artwork-tests)
set_tests_properties(helper-artwork PROPERTIES TIMEOUT 30)
add_test(NAME helper-artwork-network COMMAND bash
    ${CMAKE_CURRENT_SOURCE_DIR}/helper/run-artwork-network.sh $<TARGET_FILE:artwork-tests>)
set_tests_properties(helper-artwork-network PROPERTIES TIMEOUT 30 LABELS "needs-netns")

find_program(PYTHON3_EXECUTABLE python3 REQUIRED)
add_test(NAME source-contract COMMAND ${PYTHON3_EXECUTABLE}
    ${CMAKE_CURRENT_SOURCE_DIR}/source-contract.py)
set_tests_properties(source-contract PROPERTIES TIMEOUT 30)
add_test(NAME resource-verdicts COMMAND ${PYTHON3_EXECUTABLE}
    ${CMAKE_CURRENT_SOURCE_DIR}/test-analyze-resources.py)
set_tests_properties(resource-verdicts PROPERTIES TIMEOUT 30)
add_test(NAME media-keys-locale COMMAND ${PYTHON3_EXECUTABLE}
    ${CMAKE_CURRENT_SOURCE_DIR}/test-media-keys-locale.py)
set_tests_properties(media-keys-locale PROPERTIES TIMEOUT 30)
add_test(NAME shelf-private-writer COMMAND ${PYTHON3_EXECUTABLE}
    ${CMAKE_CURRENT_SOURCE_DIR}/test-private-shelf-writer.py)
set_tests_properties(shelf-private-writer PROPERTIES TIMEOUT 10)

# The decoder child decodes untrusted images: it links Core and Gui only, never
# the network or D-Bus stacks the helper itself needs. The helper, in turn,
# never links Gui: every image operation runs in that child.
find_program(READELF_EXECUTABLE readelf REQUIRED)
add_test(NAME decoder-links COMMAND bash -c
    "needed=$(\"$0\" -d \"$1\" | grep NEEDED) || exit 1; echo \"$needed\"; ! echo \"$needed\" | grep -Eq 'libQt6(Network|DBus)'"
    ${READELF_EXECUTABLE} $<TARGET_FILE:nookisle-artwork-decoder>)
add_test(NAME helper-links COMMAND bash -c
    "needed=$(\"$0\" -d \"$1\" | grep NEEDED) || exit 1; echo \"$needed\"; ! echo \"$needed\" | grep -Eq 'libQt6Gui'"
    ${READELF_EXECUTABLE} $<TARGET_FILE:nookisle-helper>)
add_executable(protocol-tests helper/ipc-protocol-test.cpp)
target_link_libraries(protocol-tests PRIVATE island_core Qt6::Test)
add_test(NAME helper-protocol COMMAND protocol-tests)
if(NOOKISLE_CALENDAR)
    add_executable(calendar-tests helper/calendar-test.cpp)
    target_link_libraries(calendar-tests PRIVATE island_core Qt6::Test)
    target_compile_definitions(calendar-tests PRIVATE FIXTURE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/helper/fixtures")
    add_test(NAME helper-calendar COMMAND calendar-tests)
    set_tests_properties(helper-calendar PROPERTIES TIMEOUT 60)
endif()

add_executable(registry-tests helper/mpris-registry-test.cpp)
target_link_libraries(registry-tests PRIVATE island_core Qt6::Test)
target_compile_definitions(registry-tests PRIVATE SILENT_OWNER="${CMAKE_CURRENT_SOURCE_DIR}/helper/silent-mpris-owner.py")
add_test(NAME helper-registry COMMAND ${DBUS_RUN_SESSION} -- $<TARGET_FILE:registry-tests>)

add_executable(lifecycle-tests helper/lifecycle-test.cpp)
target_link_libraries(lifecycle-tests PRIVATE island_core Qt6::Test)
target_compile_definitions(lifecycle-tests PRIVATE HELPER_PATH="$<TARGET_FILE:nookisle-helper>")
add_dependencies(lifecycle-tests nookisle-helper)
add_test(NAME helper-lifecycle COMMAND ${DBUS_RUN_SESSION} -- $<TARGET_FILE:lifecycle-tests>)
set_tests_properties(helper-protocol helper-registry helper-lifecycle PROPERTIES TIMEOUT 30)

add_executable(system-watch-tests helper/system-watch-test.cpp)
target_link_libraries(system-watch-tests PRIVATE island_core Qt6::Test)
add_test(NAME helper-system-watch COMMAND system-watch-tests)
set_tests_properties(helper-system-watch PROPERTIES TIMEOUT 30)

add_executable(backlight-tests helper/backlight-monitor-test.cpp)
target_link_libraries(backlight-tests PRIVATE island_core Qt6::Test)
add_test(NAME helper-backlight COMMAND backlight-tests)
set_tests_properties(helper-backlight PROPERTIES TIMEOUT 30)

add_executable(spectrum-tests helper/spectrum-test.cpp)
target_link_libraries(spectrum-tests PRIVATE spectrum_core Qt6::Test)
add_test(NAME helper-spectrum COMMAND spectrum-tests)
set_tests_properties(helper-spectrum PROPERTIES TIMEOUT 30)

option(NOOKISLE_HOST_TESTS "Test against the installed Omarchy host contract" ON)
if(NOOKISLE_HOST_TESTS)
    # Quickshell confines local imports to the test configuration's project tree.
    # This harness resolves source and staged modules relative to that tree.
    if(NOT CMAKE_BINARY_DIR STREQUAL "${PROJECT_SOURCE_DIR}/build")
        message(FATAL_ERROR "Host contract tests require the release preset's build/ directory. Use -DNOOKISLE_HOST_TESTS=OFF for helper-only tests in another build directory.")
    endif()
    find_program(QML_TEST_RUNNER qmltestrunner HINTS /usr/lib/qt6/bin REQUIRED)
    find_program(QUICKSHELL_EXECUTABLE quickshell REQUIRED)
    find_program(BASH_EXECUTABLE bash REQUIRED)
    add_test(NAME qml-protocol COMMAND ${CMAKE_COMMAND} -E env
        --unset=DISPLAY --unset=WAYLAND_DISPLAY
        QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1
        QML_DISABLE_DISK_CACHE=1
        ${DBUS_RUN_SESSION} --config-file=${CMAKE_CURRENT_SOURCE_DIR}/qml/session-bus.conf --
        ${QML_TEST_RUNNER} -input ${CMAKE_CURRENT_SOURCE_DIR}/qml/tst-protocol.qml)
    add_test(NAME qml-lifecycle COMMAND ${BASH_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/qml/run-lifecycle.sh)
    # The in-repo fixture holds the patched host's service loader; stock hosts
    # without the reload fix cannot run this check.
    set(NOOKISLE_PATCHED_HOST_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/qml/fixtures/patched-service-loader.qml" CACHE FILEPATH "Patched Omarchy service loader to verify with the production Service; empty disables this check")
    if(NOOKISLE_PATCHED_HOST_SOURCE)
        find_program(NODE_EXECUTABLE node REQUIRED)
        find_program(PGREP_EXECUTABLE pgrep REQUIRED)
        add_test(NAME qml-patched-host-lifecycle COMMAND ${BASH_EXECUTABLE}
            ${CMAKE_CURRENT_SOURCE_DIR}/qml/run-patched-host-lifecycle.sh ${NOOKISLE_PATCHED_HOST_SOURCE})
        set_tests_properties(qml-patched-host-lifecycle PROPERTIES TIMEOUT 40 RUN_SERIAL TRUE)
    endif()
    set_tests_properties(qml-protocol PROPERTIES TIMEOUT 30)
    add_test(NAME qml-source-state COMMAND ${CMAKE_COMMAND} -E env
        --unset=DISPLAY --unset=WAYLAND_DISPLAY
        QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1
        QML_DISABLE_DISK_CACHE=1
        ${DBUS_RUN_SESSION} --config-file=${CMAKE_CURRENT_SOURCE_DIR}/qml/session-bus.conf --
        ${QML_TEST_RUNNER} -input ${CMAKE_CURRENT_SOURCE_DIR}/qml/tst-source-state.qml)
    set_tests_properties(qml-source-state PROPERTIES TIMEOUT 30)
    find_program(NODE_EXECUTABLE node REQUIRED)
    add_test(NAME qml-panel-screen-selection COMMAND ${NODE_EXECUTABLE}
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/run-panel-screen-selection.js ${QML_TEST_RUNNER})
    set_tests_properties(qml-panel-screen-selection PROPERTIES TIMEOUT 30)
    # The complete installed Panel.qml under Quickshell: any QML error or
    # warning while it loads and builds fails.
    add_test(NAME qml-panel-load COMMAND ${BASH_EXECUTABLE}
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/run-panel-load.sh)
    set_tests_properties(qml-panel-load PROPERTIES TIMEOUT 60)
    add_test(NAME qml-panel-power COMMAND ${NODE_EXECUTABLE}
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/run-panel-power.js ${QML_TEST_RUNNER})
    set_tests_properties(qml-panel-power PROPERTIES TIMEOUT 30)
    add_test(NAME qml-panel-mode-tree COMMAND ${NODE_EXECUTABLE}
        ${CMAKE_CURRENT_SOURCE_DIR}/qml/run-panel-mode-tree.js ${QML_TEST_RUNNER})
    set_tests_properties(qml-panel-mode-tree PROPERTIES TIMEOUT 30)
    if(NOOKISLE_CALENDAR)
        add_test(NAME qml-calendar-integration COMMAND ${NODE_EXECUTABLE}
            ${CMAKE_CURRENT_SOURCE_DIR}/qml/run-calendar-integration.js
            $<TARGET_FILE:calendar-tests> ${QML_TEST_RUNNER})
        set_tests_properties(qml-calendar-integration PROPERTIES TIMEOUT 30)
    endif()
    file(MAKE_DIRECTORY "${PROJECT_SOURCE_DIR}/build/ui-preview")
    foreach(ui_test IN ITEMS controls island-state bar-widget shelf shelf-model shelf-view island-surface hud hud-bar hud-styles tint peek island-input settings motion camera-gate settings-window onboarding fullscreen-policy mic-state catch-zone battery notch-shape closed-model activity-model privacy device-events timers idle home calendar spectrum-frames displays window-move)
        add_test(NAME qml-${ui_test} COMMAND ${CMAKE_COMMAND} -E env
            --unset=DISPLAY --unset=WAYLAND_DISPLAY
            QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_PLATFORMTHEME=generic NO_AT_BRIDGE=1
            QML_DISABLE_DISK_CACHE=1
            ${DBUS_RUN_SESSION} --config-file=${CMAKE_CURRENT_SOURCE_DIR}/qml/session-bus.conf --
            ${QML_TEST_RUNNER} -input ${CMAKE_CURRENT_SOURCE_DIR}/qml/tst-${ui_test}.qml)
        set_tests_properties(qml-${ui_test} PROPERTIES TIMEOUT 30)
    endforeach()
    # The surface suite waits on real hover, grace and spring timings.
    set_tests_properties(qml-island-surface PROPERTIES TIMEOUT 60)
    # Against a local fixture server the wrapper starts and stops; the
    # lyrics source never reaches the real network in tests.
    add_test(NAME qml-lyrics COMMAND ${BASH_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/qml/run-lyrics.sh
        ${QML_TEST_RUNNER} ${PROJECT_SOURCE_DIR}/build)
    set_tests_properties(qml-lyrics PROPERTIES TIMEOUT 30)
    set_tests_properties(qml-lifecycle PROPERTIES TIMEOUT 40 RUN_SERIAL TRUE)
    # ShelfActions needs Quickshell's Process, so it runs under quickshell
    # like the lifecycle suite, with real but harmless commands.
    add_test(NAME qml-shelf-actions COMMAND ${BASH_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/qml/run-shelf-actions.sh)
    set_tests_properties(qml-shelf-actions PROPERTIES TIMEOUT 40)
    # LyricsFetch wraps Quickshell's Process, so it runs under quickshell
    # against a fake child script verifying lifecycle, argv, and signal isolation.
    add_test(NAME qml-lyrics-fetch COMMAND ${BASH_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/qml/run-lyrics-fetch.sh)
    set_tests_properties(qml-lyrics-fetch PROPERTIES TIMEOUT 40)
endif()
