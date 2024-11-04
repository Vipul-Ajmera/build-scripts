set -e

# Variables
PYTHON_VERSION=$1
BUILD_SCRIPT_PATH=${2:-""} # it's the build_script for the package
EXTRA_ARGS="${@:4}"        # Capture all additional arguments passed to the script
CURRENT_DIR="${PWD}"       # Current directory

# If a build script is provided, create a temporary copy for modification
if [ -n "$BUILD_SCRIPT_PATH" ]; then
    TEMP_BUILD_SCRIPT_PATH="temp_build_script.sh"
else
    TEMP_BUILD_SCRIPT_PATH=""
fi

yum install -y gcc gcc-c++ make openssl-devel bzip2-devel libffi-devel zlib-devel wget

# Function to install a specific Python version
install_python_version() {
    local version=$1
    case $version in
    "3.9")
        yum install -y python${version} python${version}-devel python${version}-pip
        ;;
    "3.10")
        if ! python3.10 --version &>/dev/null; then
            wget https://www.python.org/ftp/python/3.10.8/Python-3.10.8.tgz
            tar xzf Python-3.10.8.tgz
            cd Python-3.10.8
            ./configure --prefix=/usr/local --enable-optimizations
            make -j 
            make altinstall
            cd .. && rm Python-3.10.8.tgz
        fi
        ;;
    "3.11" | "3.12")
        yum install -y python${version} python${version}-devel python${version}-pip
        ;;
    "3.13")
        if ! python3.13 --version &>/dev/null; then
            echo "Now installing python3.13..."
            wget https://www.python.org/ftp/python/3.13.0/Python-3.13.0rc1.tgz
            tar xzf Python-3.13.0rc1.tgz
            cd Python-3.13.0rc1
            ./configure --prefix=/usr/local --enable-optimizations
            make -j 
            make altinstall
            cd .. && rm Python-3.13.0rc1.tgz
        fi
        ;;
    *)
        echo "Unsupported Python version: $version"
        exit 1
        ;;
    esac
}

# Function to copy and format the build script
format_build_script() {
    if [ -n "$BUILD_SCRIPT_PATH" ]; then
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
        echo "No build script specified, skipping copying."
    fi
}

# Function to create a virtual environment
create_venv() {
    local VENV_DIR=$1
    local python_version=$2
    "python$python_version" -m venv --system-site-packages "$VENV_DIR"
    source "$VENV_DIR/bin/activate"
}

# Function to clean up virtual environment
cleanup() {
    local VENV_DIR=$1
    deactivate
    rm -rf "$VENV_DIR"
}

# Format the build script if it's non-empty
if [ -n "$BUILD_SCRIPT_PATH" ]; then
    format_build_script
fi

echo "Installing Python..."
# Install the specified Python version with monitoring
install_python_version "$PYTHON_VERSION" & # Run the installation in the background
INSTALL_PID=$!

# Monitor the installation
while ps -p $INSTALL_PID >/dev/null; do
    echo "$INSTALL_PID is running"
    sleep 30
done

# Wait for the installation to finish and capture the exit status
wait $INSTALL_PID
install_status=$?

# Check if the installation succeeded
if [ $install_status -ne 0 ]; then
    echo "Python installation failed. Exiting."
    exit 1
fi

# Create and activate virtual environment
VENV_DIR="$CURRENT_DIR/pyvenv_$PYTHON_VERSION"
create_venv "$VENV_DIR" "$PYTHON_VERSION"

echo "=============== Running package build-script starts =================="

if [ -n "$TEMP_BUILD_SCRIPT_PATH" ]; then
    # Check if TEMP_BUILD_SCRIPT_PATH is non-empty
    package_name=$(grep -oP '(?<=^PACKAGE_NAME=).*' "$TEMP_BUILD_SCRIPT_PATH" | tr -d '"')

    # Run the build script in the background
    sh "$TEMP_BUILD_SCRIPT_PATH" $EXTRA_ARGS &
    SCRIPT_PID=$!

    # Monitor the script execution
    while ps -p $SCRIPT_PID >/dev/null; do
        echo "$SCRIPT_PID is running"
        sleep 30
    done

    # Wait for the script to finish and capture the exit status
    wait $SCRIPT_PID
    my_pid_status=$?
else
    echo "No build script to run, skipping execution."
fi

echo "=============== Running package build-script ends =================="

# If the build script fails, exit with an error
if [ $my_pid_status -ne 0 ]; then
    echo "Build script execution failed. Exiting."
    cleanup "$VENV_DIR"
    exit 1
fi

echo "Navigating to the specified directory"
cd $package_name

# Build the wheel
echo ""
echo "*****************************************************************************"
echo "Building the wheel..."
if ! python -m build --wheel --outdir="$CURRENT_DIR/wheels_$PYTHON_VERSION/"; then
    echo "Wheel creation failed for Python $PYTHON_VERSION."
    cleanup "$VENV_DIR"
    [ -n "$TEMP_BUILD_SCRIPT_PATH" ] && rm "$CURRENT_DIR/$TEMP_BUILD_SCRIPT_PATH"
    exit 1
fi

# Clean up the virtual environment
cleanup "$VENV_DIR"
echo "Build and wheel creation completed successfully."
[ -n "$TEMP_BUILD_SCRIPT_PATH" ] && rm "$CURRENT_DIR/$TEMP_BUILD_SCRIPT_PATH"
exit 0
