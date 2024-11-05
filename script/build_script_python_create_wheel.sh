set -e
 
# Variables
PYTHON_VERSION=$1
BUILD_SCRIPT_PATH=${2:-""}  # Build script for the package
EXTRA_ARGS="${@:4}"         # Capture all additional arguments passed to the script
CURRENT_DIR="${PWD}"        # Current directory
 
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
                make -j ${nproc}
                make altinstall
                cd .. && rm -rf Python-3.10.8.tgz
            fi
            ;;
        "3.11")
            yum install -y python${version} python${version}-devel python${version}-pip
            ;;
        "3.12")
            yum install -y python${version} python${version}-devel python${version}-pip
            ;;
        "3.13")
            if ! python3.13 --version &>/dev/null; then
                echo "Now installing python3.13..."
wget https://www.python.org/ftp/python/3.13.0/Python-3.13.0rc1.tgz
                tar xzf Python-3.13.0rc1.tgz
                cd Python-3.13.0rc1
                ./configure --prefix=/usr/local --enable-optimizations
                make -j ${nproc}
                make altinstall
                cd .. && rm -rf Python-3.13.0rc1.tgz
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
 
# Run command with a timeout and print updates if it’s running long
run_with_timeout() {
    local cmd="$1"
    local timeout_sec=300
    local interval=60  # Print status every 60 seconds
 
    (
        while :; do
            sleep $interval
            echo "Still running: $cmd"
        done
    ) &
    local progress_pid=$!
 
    timeout $timeout_sec bash -c "$cmd"
    local exit_code=$?
 
    kill $progress_pid
 
    return $exit_code
}
 
# Run major parts of the script with the timeout wrapper
run_with_timeout "install_python_version '$PYTHON_VERSION'"
run_with_timeout "format_build_script"
 
echo "Creating virtual environment..."
VENV_DIR="$CURRENT_DIR/pyvenv_$PYTHON_VERSION"
run_with_timeout "python$PYTHON_VERSION -m venv --system-site-packages '$VENV_DIR' && source '$VENV_DIR/bin/activate'"
 
echo "=============== Running package build-script starts =================="
if [ -n "$TEMP_BUILD_SCRIPT_PATH" ]; then
    package_name=$(grep -oP '(?<=^PACKAGE_NAME=).*' "$TEMP_BUILD_SCRIPT_PATH" | tr -d '"')
    run_with_timeout "python$PYTHON_VERSION -m pip install --upgrade pip setuptools wheel build pytest nox tox"
    run_with_timeout "sh '$TEMP_BUILD_SCRIPT_PATH' $EXTRA_ARGS"
else
    echo "No build script to run, skipping execution."
fi
echo "=============== Running package build-script ends =================="
 
# Check for any errors in the build script execution
if [ $? -ne 0 ]; then
    echo "Build script execution failed. Exiting."
    exit 1
fi
 
echo "Navigating to the specified directory"
cd $package_name
 
echo "*****************************************************************************"
echo "Building the wheel..."
if ! run_with_timeout "python -m build --wheel --outdir='$CURRENT_DIR/wheels_$PYTHON_VERSION/'"; then
    echo "Wheel creation failed for Python $PYTHON_VERSION."
    exit 1
fi
 
echo "Build and wheel creation completed successfully."
[ -n "$TEMP_BUILD_SCRIPT_PATH" ] && rm "$CURRENT_DIR/$TEMP_BUILD_SCRIPT_PATH"
 
exit 0
