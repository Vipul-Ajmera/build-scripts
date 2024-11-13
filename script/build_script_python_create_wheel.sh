#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Function to log with timestamp
log_with_timestamp() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

PYTHON_VERSION=$1
BUILD_SCRIPT_PATH=${2:-""}
if [ -n "$BUILD_SCRIPT_PATH" ]; then
    TEMP_BUILD_SCRIPT_PATH="temp_build_script.sh"
else
    TEMP_BUILD_SCRIPT_PATH=""
fi
EXTRA_ARGS="${@:3}" # Capture all additional arguments passed to the script
CURRENT_DIR="${PWD}"

# install required dependencies
log_with_timestamp "Installing dependencies required for python installation..."
yum install -y sudo zlib-devel wget ncurses git gcc gcc-c++ make cmake || {
    log_with_timestamp "Failed to install basic dependencies"
    exit 1
}

log_with_timestamp "Installing additional dependencies..."
yum install -y libffi libffi-devel sqlite sqlite-devel sqlite-libs openssl-devel || {
    log_with_timestamp "Failed to install additional dependencies"
    exit 1
}

# Function to install a specific Python version with progress reporting
install_python_version() {
    local version=$1
    case $version in
    "3.9" | "3.11" | "3.12")
        log_with_timestamp "Installing Python ${version} using yum..."
        yum install -y python${version} python${version}-devel python${version}-pip
        ;;
    "3.10")
        if ! python3.10 --version &>/dev/null; then
            log_with_timestamp "Downloading Python 3.10..."
            wget https://www.python.org/ftp/python/3.10.14/Python-3.10.14.tgz
            tar xf Python-3.10.14.tgz
            cd Python-3.10.14
            log_with_timestamp "Configuring Python 3.10..."
            ./configure --prefix=/usr/local --enable-optimizations

            log_with_timestamp "Building Python 3.10 (this may take a while)..."
            # Use a loop to show progress during make
            make -j2 &
            make_pid=$!
            while kill -0 $make_pid 2>/dev/null; do
                log_with_timestamp "Still building Python 3.10..."
                sleep 60
            done
            wait $make_pid

            log_with_timestamp "Installing Python 3.10..."
            make altinstall
            python3.10 --version
            cd ..
        fi
        ;;
    "3.13")
        if ! python3.13 --version &>/dev/null; then
            log_with_timestamp "Downloading Python 3.13..."
            wget https://www.python.org/ftp/python/3.13.0/Python-3.13.0rc1.tgz
            tar xzf Python-3.13.0rc1.tgz
            cd Python-3.13.0rc1
            log_with_timestamp "Configuring Python 3.13..."
            ./configure --prefix=/usr/local --enable-optimizations

            log_with_timestamp "Building Python 3.13 (this may take a while)..."
            # Use a loop to show progress during make
            make -j2 &
            make_pid=$!
            while kill -0 $make_pid 2>/dev/null; do
                log_with_timestamp "Still building Python 3.13..."
                sleep 60
            done
            wait $make_pid

            log_with_timestamp "Installing Python 3.13..."
            make altinstall
            cd .. && rm -rf Python-3.13.0rc1.tgz
        fi
        ;;
    *)
        log_with_timestamp "Unsupported Python version: $version"
        exit 1
        ;;
    esac
}

# Install the specified Python version
log_with_timestamp "Starting Python ${PYTHON_VERSION} installation..."
install_python_version "$PYTHON_VERSION"

# Function to check for setup.py or *.toml files in a directory
check_files_in_directory() {
    local dir=$1
    if [ -f "$dir/setup.py" ] || ls "$dir"/*.toml 1>/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Function to format the build script
format_build_script() {
    if [ -n "$BUILD_SCRIPT_PATH" ]; then
        log_with_timestamp "Formatting build script..."
        cp "$BUILD_SCRIPT_PATH" "$TEMP_BUILD_SCRIPT_PATH"
        sed -i 's/pip3 /pip /g' "$TEMP_BUILD_SCRIPT_PATH"
        sed -i 's/\bpython[0-9]\+\.[0-9]\+ -m pip /pip /g' "$TEMP_BUILD_SCRIPT_PATH"
        sed -i '/-m venv/d' "$TEMP_BUILD_SCRIPT_PATH"
        sed -i '/bin\/activate/d' "$TEMP_BUILD_SCRIPT_PATH"
        sed -i '/^deactivate$/d' "$TEMP_BUILD_SCRIPT_PATH"
        sed -i 's/python[0-9]\+\.[0-9]\+-devel//g' "$TEMP_BUILD_SCRIPT_PATH"
        sed -i 's/python[0-9]\+\.[0-9]\+-pip//g' "$TEMP_BUILD_SCRIPT_PATH"
        sed -i 's/python3\.[0-9]\+/python/g' "$TEMP_BUILD_SCRIPT_PATH"
        sed -i 's/python3/python/g' "$TEMP_BUILD_SCRIPT_PATH"
        sed -i '/yum install/{s/\<python-devel\>//g; s/\<python-pip\>//g}' "$TEMP_BUILD_SCRIPT_PATH"
        sed -i '/yum install/{s/\<python\>//g}' "$TEMP_BUILD_SCRIPT_PATH"
    else
        log_with_timestamp "No build script specified, skipping copying."
    fi
}

# Function to create a virtual environment
create_venv() {
    local VENV_DIR=$1
    local python_version=$2
    log_with_timestamp "Creating virtual environment..."
    "python$python_version" -m venv --system-site-packages "$VENV_DIR"
    source "$VENV_DIR/bin/activate"
}

# Function to clean up virtual environment
cleanup() {
    local VENV_DIR=$1
    log_with_timestamp "Cleaning up virtual environment..."
    deactivate
    rm -rf "$VENV_DIR"
}

# Format the build script if it's non-empty
if [ -n "$BUILD_SCRIPT_PATH" ]; then
    format_build_script
fi

log_with_timestamp "Processing Package with Python $PYTHON_VERSION"

# Create and activate virtual environment
VENV_DIR="$CURRENT_DIR/pyvenv_$PYTHON_VERSION"
create_venv "$VENV_DIR" "$PYTHON_VERSION"

log_with_timestamp "=============== Running package build-script starts =================="
if [ -n "$TEMP_BUILD_SCRIPT_PATH" ]; then
    log_with_timestamp "Installing build dependencies..."
    python$PYTHON_VERSION -m pip install --upgrade pip setuptools wheel build pytest nox tox
    package_name=$(grep -oP '(?<=^PACKAGE_NAME=).*' "$TEMP_BUILD_SCRIPT_PATH" | tr -d '"')

    log_with_timestamp "Executing build script..."
    # Execute build script with progress monitoring
    sh "$TEMP_BUILD_SCRIPT_PATH" $EXTRA_ARGS &
    build_pid=$!
    while kill -0 $build_pid 2>/dev/null; do
        log_with_timestamp "Build script still running..."
        sleep 60
    done
    wait $build_pid
else
    log_with_timestamp "No build script to run, skipping execution."
fi
log_with_timestamp "=============== Running package build-script ends =================="

if [ $? -ne 0 ]; then
    log_with_timestamp "Build script execution failed. Skipping wheel creation."
    cleanup "$VENV_DIR"
    [ -n "$TEMP_BUILD_SCRIPT_PATH" ] && rm "$CURRENT_DIR/$TEMP_BUILD_SCRIPT_PATH"
    exit 1
fi

log_with_timestamp "Navigating to the package directory"
cd $package_name

log_with_timestamp "=============== Building wheel =================="
if [ ! -f "setup.py" ] && ! ls *.toml 1>/dev/null 2>&1; then
    log_with_timestamp "setup.py or *.toml not found in the current directory. Checking subdirectories..."
    dir=$(find . -type f -name "setup.py" -o -name "*.toml" -print -quit | xargs -I {} dirname "{}")
    if [ -n "$dir" ]; then
        log_with_timestamp "setup.py or *.toml found in $dir"
        cd "$dir"
    else
        log_with_timestamp "No setup.py or *.toml found in any subdirectory."
    fi
else
    log_with_timestamp "========= setup.py or *.toml found in the package directory ========="
fi

# Build wheel with progress monitoring
log_with_timestamp "Starting wheel build..."
python -m build --wheel --outdir="$CURRENT_DIR/" &
build_pid=$!
while kill -0 $build_pid 2>/dev/null; do
    log_with_timestamp "Wheel build in progress..."
    sleep 60
done
wait $build_pid

if [ $? -ne 0 ]; then
    log_with_timestamp "============ Wheel Creation Failed for Python $PYTHON_VERSION ================="
    cleanup "$VENV_DIR"
    [ -n "$TEMP_BUILD_SCRIPT_PATH" ] && rm "$CURRENT_DIR/$TEMP_BUILD_SCRIPT_PATH"
    exit 1
fi

cleanup "$VENV_DIR"
[ -n "$TEMP_BUILD_SCRIPT_PATH" ] && rm "$CURRENT_DIR/$TEMP_BUILD_SCRIPT_PATH"

log_with_timestamp "Build process completed successfully"
exit 0
