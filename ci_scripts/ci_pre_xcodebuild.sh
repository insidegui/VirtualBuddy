#!/usr/bin/env zsh

set -e

CONFIG_FILE_PATH="${CI_PRIMARY_REPOSITORY_PATH}/VirtualBuddy/Config/CIProjectVersion.xcconfig"

if [ -n "${CI_BUILD_NUMBER}" ]; then
    echo "Writing CURRENT_PROJECT_VERSION with Xcode Cloud build: ${CI_BUILD_NUMBER} in ${CONFIG_FILE_PATH}"
    echo "CURRENT_PROJECT_VERSION = ${CI_BUILD_NUMBER}" > "${CONFIG_FILE_PATH}"
fi