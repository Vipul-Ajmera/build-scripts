#!/bin/bash -e

sudo apt update -y && sudo apt-get install file -y
#pip3 install --upgrade requests
pip3 install --force-reinstall -v "requests==2.31.0"
pip3 install --upgrade docker

echo "Running build script execution in background for "$PKG_DIR_PATH$BUILD_SCRIPT" "$VERSION" "
echo "*************************************************************************************"

docker_image=""

# Function to build a custom Docker image for non-root users.
docker_build_non_root() {
    echo "building docker image for non-root user build"
    docker build --build-arg BASE_IMAGE="$1" -t docker_non_root_image -f script/dockerfile_non_root .
    docker_image="docker_non_root_image"
}

# Select base image based on `TESTED_ON` and `NON_ROOT_BUILD` flags.
if [[ "$TESTED_ON" == UBI:9* || "$TESTED_ON" == UBI9* ]]; then
    docker pull registry.access.redhat.com/ubi9/ubi:9.3
    docker_image="registry.access.redhat.com/ubi9/ubi:9.3"
    [[ "$NON_ROOT_BUILD" == "true" ]] && docker_build_non_root "registry.access.redhat.com/ubi9/ubi:9.3"
else
    docker pull registry.access.redhat.com/ubi8/ubi:8.7
    docker_image="registry.access.redhat.com/ubi8/ubi:8.7"
    [[ "$NON_ROOT_BUILD" == "true" ]] && docker_build_non_root "registry.access.redhat.com/ubi8/ubi:8.7"
fi

# Function to run validation scripts and handle logging.
run_and_log() {
    local -a script_args=($1) # Split the script arguments into an array
    local log_file="$2"

    python3 script/validate_builds_currency.py "${script_args[@]}" >"$log_file" &
    local pid=$!

    # Monitor the process
    while ps -p $pid >/dev/null; do
        echo "$pid is running"
        sleep 100
    done
    wait $pid
    local status=$?
    local log_size=$(stat -c %s "$log_file")

    if [ $status -ne 0 ]; then
        echo "Script execution failed for "$PKG_DIR_PATH$BUILD_SCRIPT" "$VERSION" "
        echo "*************************************************************************************"
        if [ $log_size -lt 1800000 ]; then
            cat "$log_file"
        else
            tail -100 "$log_file"
        fi
        exit 1
    else
        echo "Script execution completed successfully for "$PKG_DIR_PATH$BUILD_SCRIPT" "$VERSION" "
        echo "*************************************************************************************"
        if [ $log_size -lt 1800000 ]; then
            cat "$log_file"
        else
            tail -100 "$log_file"
        fi
    fi
}

# Run the required validation scripts
[[ "$VALIDATE_BUILD_SCRIPT" == "true" ]] && run_and_log "$PKG_DIR_PATH$BUILD_SCRIPT $VERSION $docker_image" "validate_build_log"

WHEEL_SCRIPT=script/build_script_python_create_wheel.sh
[[ "$WHEEL_BUILD" == "true" ]] && run_and_log "$WHEEL_SCRIPT $PYTHON_VERSION $PKG_DIR_PATH$BUILD_SCRIPT $VERSION $docker_image" "wheel_build_log"

exit 0
