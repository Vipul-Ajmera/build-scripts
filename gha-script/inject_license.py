import os
import re
import subprocess
import hashlib
import base64
import logging
import sys

logging.basicConfig(level=logging.INFO,
    format="[%(levelname)s] %(asctime)s - %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    stream=sys.stdout,)

logger = logging.getLogger(__name__)

LICENSE_PATTERN = re.compile(r"^(LICENSE|COPYING)(\..*)?$")
LICENSE_SEPARATOR = "----"


def run_command(cmd):
    try:
        return subprocess.run(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False
        )
    except Exception as e:
        logger.exception(f"Command failed: {' '.join(cmd)} → {e}")
        return None


def find_libs_dirs(root):
    libs_dirs = []
    try:
        for dirpath, dirnames, _ in os.walk(root):
            for d in dirnames:
                if d.endswith(".libs"):
                    libs_dirs.append(os.path.join(dirpath, d))
    except Exception as e:
        logger.exception(f"Failed scanning .libs dirs → {e}")

    return libs_dirs


def collect_so_files(libs_dir):
    so_files = []
    try:
        for f in os.listdir(libs_dir):
            if f.startswith("lib") and ".so" in f:
                so_files.append(os.path.join(libs_dir, f))
    except Exception as e:
        logger.exception(f"Failed collecting .so files → {e}")

    return so_files


def normalize_so_name(so_name):
    return re.sub(r"-[0-9a-f]{8,}(?=(?:\.so|\.\d))", "", so_name)


def find_all_so_anywhere(so_name):
    try:
        result = run_command(["find", ".", "-type", "f", "-name", so_name])
        if result and result.stdout.strip():
            return result.stdout.strip().splitlines()

        result = run_command(["find", "/", "-type", "f", "-name", so_name])
        if result:
            return result.stdout.strip().splitlines()

    except Exception as e:
        logger.exception(f"find_all_so_anywhere failed → {e}")

    return []


def get_rpm_package(so_path):
    try:
        result = run_command(["rpm", "-qf", so_path])
        if result and result.returncode == 0:
            return result.stdout.strip()
        return None
    except Exception:
        logger.debug(f"RPM package lookup failed for {so_path}", exc_info=True)
        return None


def get_rpm_license(pkg_name):
    try:
        result = run_command(["rpm", "-q", "--qf", "%{LICENSE}\n", pkg_name])
        if result and result.returncode == 0:
            return result.stdout.strip()
        return None
    except Exception:
        logger.debug(f"RPM license query failed for {pkg_name}", exc_info=True)
        return None


def find_project_root(so_path, max_up=10):
    try:
        current = os.path.dirname(so_path)

        for _ in range(max_up):
            if not current:
                break

            for f in os.listdir(current):
                if LICENSE_PATTERN.match(f):
                    return current

            parent = os.path.dirname(current)
            if parent == current:
                break

            current = parent
        return None
    except Exception:
        logger.debug("Failed to find project root", exc_info=True)
        return None


def find_license_in_directory(directory):
    try:
        for f in os.listdir(directory):
            if LICENSE_PATTERN.match(f):
                return os.path.join(directory, f)
        return None
    except Exception:
        logger.debug(f"Failed to find license in directory {directory}", exc_info=True)
        return None


def find_dist_info_dir(root):
    try:
        for item in os.listdir(root):
            if item.endswith(".dist-info"):
                return os.path.join(root, item)
    except Exception as e:
        logger.exception(f"Failed locating dist-info → {e}")

    return None


def append_license_entry(file_path, so_names, license_text):
    try:
        if os.path.exists(file_path) and os.path.getsize(file_path) > 0:
            with open(file_path, "a", encoding="utf-8") as f:
                f.write(f"\n\n{LICENSE_SEPARATOR}\n\n")

        with open(file_path, "a", encoding="utf-8") as f:
            f.write(f"Files: {', '.join(so_names)}\n")

            lines = license_text.strip("\n").splitlines()
            if len(lines) > 1:
                f.write("\n")
                f.write(license_text)
                if not license_text.endswith("\n"):
                    f.write("\n")
            else:
                f.write(f"License: {license_text.strip()}\n")

    except Exception as e:
        logger.exception(f"Failed writing license entry → {e}")


def compute_hash_and_size(file_path):
    try:
        with open(file_path, "rb") as f:
            data = f.read()

        digest = hashlib.sha256(data).digest()
        hash_b64 = base64.urlsafe_b64encode(digest).rstrip(b"=").decode("utf-8")
        size = len(data)

        return f"sha256={hash_b64}", size

    except Exception as e:
        logger.exception(f"Hash computation failed → {e}")
        return None, None


def update_record(dist_info_dir, file_paths):
    try:
        record_file = os.path.join(dist_info_dir, "RECORD")

        if not os.path.exists(record_file):
            logger.warning("RECORD file missing → skipping update")
            return

        with open(record_file, "r", encoding="utf-8") as f:
            lines = f.read().splitlines()

        record_map = {line.split(",")[0]: line.split(",") for line in lines}

        for path in file_paths:
            if not os.path.exists(path):
                continue

            relative_path = os.path.relpath(path, os.path.dirname(dist_info_dir))
            hash_val, size_val = compute_hash_and_size(path)

            if hash_val:
                record_map[relative_path] = [relative_path, hash_val, str(size_val)]

        with open(record_file, "w", encoding="utf-8", newline="\n") as f:
            for parts in record_map.values():
                f.write(",".join(parts) + "\n")

        logger.info("RECORD updated successfully")

    except Exception as e:
        logger.exception(f"RECORD update failed → {e}")


def process_so_file(so_path, rpm_licenses, bundled_licenses):
    try:
        original_name = os.path.basename(so_path)
        normalized_name = normalize_so_name(original_name)

        for match_so in find_all_so_anywhere(normalized_name):
            if not match_so:
                continue

            pkg = get_rpm_package(match_so)
            if pkg:
                license_text = get_rpm_license(pkg)
                if license_text:
                    rpm_licenses.setdefault(license_text, []).append(original_name)
                    return

            project_root = find_project_root(match_so)
            if project_root:
                license_file = find_license_in_directory(project_root)
                if license_file:
                    with open(license_file, "r", encoding="utf-8", errors="ignore") as f:
                        bundled_licenses.setdefault(f.read(), []).append(original_name)
                        return

        bundled_licenses.setdefault(f"{original_name}_license_not_found", []).append(original_name)

    except Exception as e:
        logger.exception(f".so processing failed → {e}")


def inject_licenses(extracted_path):
    try:
        logger.info(f"Starting license injection → {extracted_path}")

        rpm_licenses = {}
        bundled_licenses = {}

        libs_dirs = find_libs_dirs(extracted_path)

        if not libs_dirs:
            logger.warning("No .libs directories found")

        for libs_dir in libs_dirs:
            so_files = collect_so_files(libs_dir)

            for so_file in so_files:
                logger.info(f"Processing SO → {so_file}")
                process_so_file(so_file, rpm_licenses, bundled_licenses)

        dist_info = find_dist_info_dir(extracted_path)

        if not dist_info:
            logger.warning(".dist-info directory missing")
            return False

        ubi_path = os.path.join(dist_info, "UBI_BUNDLED_LICENSES.txt")
        bundled_path = os.path.join(dist_info, "BUNDLED_LICENSES.txt")

        for license_text, files in rpm_licenses.items():
            append_license_entry(ubi_path, files, license_text)

        for license_text, files in bundled_licenses.items():
            append_license_entry(bundled_path, files, license_text)

        update_record(dist_info, [ubi_path, bundled_path])

        logger.info("License injection completed successfully")
        return True

    except Exception as e:
        logger.exception(f"License injection crashed → {e}")
        return False


if __name__ == "__main__":
    if len(sys.argv) != 2:
        logger.error("Usage: python inject_license.py <extracted_dir>")
        sys.exit(1)

    if not inject_licenses(sys.argv[1]):
        sys.exit(1)
