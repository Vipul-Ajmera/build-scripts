set -e  
 
PYTHON_VERSION=$1
BUILD_SCRIPT_PATH=${2:-""}
TARGET_DIRECTORY=${3:-""}  # Directory name provided by the user (default is current directory)
EXTRA_ARGS="${@:4}"  # Capture all additional arguments passed to the script
 
CURRENT_DIR="${PWD}"  # Current directory
 
#required dependencies for building python
yum install -y gcc gcc-c++ make openssl-devel bzip2-devel libffi-devel zlib-devel wget

# Function to install a specific Python version
install_python_version() {
    local version=$1
    case $version in
        "3.9" | "3.11" | "3.12")
            yum install -y python${version} python${version}-devel
            ;;
        "3.10")
            if ! python3.10 --version &> /dev/null; then
                cd /usr/src && \
		wget https://www.python.org/ftp/python/3.10.14/Python-3.10.14.tgz && \
		tar xzf Python-3.10.14.tgz && \
		cd Python-3.10.14 && \
		./configure --enable-optimizations && \
		make altinstall && \
		ln -s /usr/local/bin/python3.10 /usr/bin/python3.10 && \
		cd /usr/src && \
		rm -rf Python-3.10.14.tgz Python-3.10.14
            fi
            ;;
        "3.13")
            if ! python3.13 --version &> /dev/null; then
                cd /usr/src
		wget https://www.python.org/ftp/python/3.13.0/Python-3.13.0rc1.tgz
                tar xzf Python-3.13.0rc1.tgz
                cd Python-3.13.0rc1
                ./configure --enable-optimizations
                make altinstall
                ln -s /usr/local/bin/python3.13 /usr/bin/python3.13
                rm -rf Python-3.13.0rc1*
            fi
            ;;
        *)
            echo "Unsupported Python version: $version"
            exit 1
            ;;
    esac
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
 
# Install the specified Python version
install_python_version "$PYTHON_VERSION"
 
# Create and activate virtual environment
VENV_DIR="$CURRENT_DIR/pyvenv_$PYTHON_VERSION"
create_venv "$VENV_DIR" "$PYTHON_VERSION"
 
# If a build script path is provided, run it inside the virtual environment
if [ -n "$BUILD_SCRIPT_PATH" ]; then
    echo "Running the build script..."
    sh "$BUILD_SCRIPT_PATH" $EXTRA_ARGS
fi
 
# If the build script fails, exit with an error
if [ $? -ne 0 ]; then
    echo "Build script execution failed. Exiting."
    cleanup "$VENV_DIR"
    exit 1
fi
 
# Navigate to the user-provided directory or stay in the current directory
if [ -n "$TARGET_DIRECTORY" ]; then
    echo "Navigating to the specified directory: $TARGET_DIRECTORY"
    cd "$TARGET_DIRECTORY" || { echo "Directory not found: $TARGET_DIRECTORY"; exit 1; }
else
    echo "No directory specified. Staying in the current directory."
fi
 
 
# Build the wheel
echo "Building the wheel..."
if ! python -m build --wheel --outdir="$CURRENT_DIR/wheels/$PYTHON_VERSION/"; then
    echo "Wheel creation failed for Python $PYTHON_VERSION."
    cleanup "$VENV_DIR"
    exit 1
fi
 
# Clean up the virtual environment
cleanup "$VENV_DIR"
 
echo "Build and wheel creation completed successfully."
exit 0
