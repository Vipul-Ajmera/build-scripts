import os
import hashlib
import ibm_boto3
from ibm_botocore.client import Config
import logging
import sys

logging.basicConfig(level=logging.INFO,
    format="[%(levelname)s] %(asctime)s - %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    stream=sys.stderr,)

logger = logging.getLogger(__name__)

COS_API_KEY=""
COS_SERVICE_INSTANCE_ID=""
COS_ENDPOINT=""
COS_BUCKET=""

# ---------------- SHA256 ----------------
def sha256_file(path):
    try:
        logger.info(f"Computing SHA256 → {path}")
        h = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(8192), b""):
                h.update(chunk)
        sha = h.hexdigest()
        logger.info(f"SHA256 → {sha}")
        return sha
    except Exception as e:
        logger.exception(f"SHA256 computation failed → {e}")
        return None


# ---------------- COS CLIENT ----------------
def create_cos_client():
    try:
        logger.info("Creating IBM COS client")
        return ibm_boto3.client(
            "s3",
            ibm_api_key_id=COS_API_KEY,
            ibm_service_instance_id=COS_SERVICE_INSTANCE_ID,
            config=Config(signature_version="oauth"),
            endpoint_url=COS_ENDPOINT,
        )
    except Exception as e:
        logger.exception(f"COS client creation failed → {e}")
        return None


# ---------------- SUFFIX RESOLUTION ----------------
def resolve_suffix(client, base_key, wheel_name, local_sha):
    try:
        logger.info(f"Resolving suffix for → {wheel_name} with local SHA256 → {local_sha}")

        # Expect base_key like: package/version OR package/vversion
        parts = base_key.split("/", 1)
        if len(parts) != 2:
            logger.error(f"Invalid base_key format → {base_key}")
            return None

        package, version_part = parts
        clean_version = version_part.lstrip("v")

        # To check in cos support both folder styles
        possible_base_keys = [
            f"{package}/v{clean_version}",
            f"{package}/{clean_version}",
        ]

        name_parts = wheel_name.rstrip(".whl").split("-")
        if len(name_parts) < 5:
            logger.error(f"Unexpected wheel format → {wheel_name}")
            return None

        pkg = name_parts[0]
        version = name_parts[1]
        remainder = "-".join(name_parts[2:])

        n = 1

        while True:
            suffix = f"ppc64le{n}"

            # Insert suffix AFTER version
            candidate_name = f"{pkg}-{version}+{suffix}-{remainder}.whl"

            response = None
            found = False

            for key_prefix in possible_base_keys:
                cos_key = f"{key_prefix}/{candidate_name}"
                logger.info(f"Checking COS → {cos_key}")

                try:
                    response = client.head_object(
                        Bucket=COS_BUCKET,
                        Key=cos_key
                    )
                    logger.info(f"Found object in COS → {cos_key}")
                    found = True
                    break
                except Exception:
                    continue

            if not found:
                logger.info(f"Available suffix → '{suffix}'")
                return suffix

            remote_sha = (
                response.get("Metadata", {}).get("sha256")
                or response.get("Metadata", {}).get("Sha256")
            )

            logger.info(f"Cos store sha256 → {remote_sha}")

            if remote_sha and remote_sha.strip() == local_sha.strip():
                logger.info(f"Matching wheel found → suffix '{suffix}'")
                return suffix

            logger.info(f"SHA mismatch → trying suffix ppc64le{n+1}")
            n += 1

    except Exception:
        logger.exception("Suffix resolution failed")
        return None


# ---------------- METADATA HELPERS ----------------
def find_dist_info_dir(extracted_path):
    try:
        logger.info(f"Locating .dist-info in → {extracted_path}")
        for d in os.listdir(extracted_path):
            if d.endswith(".dist-info"):
                return os.path.join(extracted_path, d)
        return None
    except Exception:
        return None


def read_version(dist_info_dir):
    try:
        logger.info(f"Reading Version from → {dist_info_dir}")
        metadata_path = os.path.join(dist_info_dir, "METADATA")

        with open(metadata_path, "r", encoding="utf-8") as f:
            for line in f:
                if line.startswith("Version:"):
                    return line.split(":", 1)[1].strip()

        raise RuntimeError("Version not found in METADATA")

    except Exception as e:
        logger.exception(f"Failed reading Version → {e}")
        return None


def build_new_version(old_version, suffix):
    if not suffix:
        return old_version

    if "+" in old_version:
        base, local = old_version.split("+", 1)
        return f"{base}+{local}.{suffix}"

    return f"{old_version}+{suffix}"


def update_version(dist_info_dir, new_version):
    try:
        metadata_path = os.path.join(dist_info_dir, "METADATA")

        with open(metadata_path, "r", encoding="utf-8") as f:
            lines = f.readlines()

        with open(metadata_path, "w", encoding="utf-8") as f:
            for line in lines:
                if line.startswith("Version:"):
                    f.write(f"Version: {new_version}\n")
                else:
                    f.write(line)

        logger.info(f"Updated Version → {new_version}")
        return True

    except Exception as e:
        logger.exception(f"Failed updating Version → {e}")
        return False


def rename_dist_info(extracted_path, old_version, new_version):
    try:
        logger.info(f"Renaming .dist-info from version {old_version} to {new_version}")
        for entry in os.listdir(extracted_path):
            if entry.endswith(".dist-info") and old_version in entry:
                old_path = os.path.join(extracted_path, entry)
                new_entry = entry.replace(old_version, new_version)
                new_path = os.path.join(extracted_path, new_entry)

                os.rename(old_path, new_path)

                logger.info(f"Renamed dist-info → {new_entry}")
                return new_path

        raise RuntimeError("Matching dist-info not found")

    except Exception as e:
        logger.exception(f"dist-info rename failed → {e}")
        return None


# ---------------- RECORD REGEN ----------------
def hash_file(path):
    try:
        h = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(8192), b""):
                h.update(chunk)
        return "sha256=" + h.digest().hex()
    except Exception:
        return None


def regenerate_record(extract_path, dist_info_dir):
    try:
        logger.info("Regenerating RECORD file")
        record_path = os.path.join(dist_info_dir, "RECORD")

        records = []

        for root, _, files in os.walk(extract_path):
            for fname in files:
                full_path = os.path.join(root, fname)
                rel_path = os.path.relpath(full_path, extract_path).replace(os.sep, "/")

                if rel_path.endswith("RECORD"):
                    records.append(f"{rel_path},,")
                    continue

                size = os.path.getsize(full_path)
                digest = hash_file(full_path)

                if not digest:
                    logger.error(f"Failed hashing → {rel_path}")
                    return False

                records.append(f"{rel_path},{digest},{size}")

        with open(record_path, "w", encoding="utf-8") as f:
            f.write("\n".join(records))

        logger.info("RECORD regenerated")
        return True

    except Exception as e:
        logger.exception(f"RECORD regeneration failed → {e}")
        return False


# ---------------- MAIN ----------------
def main():
    try:
        if len(sys.argv) != 5:
            logger.error("Usage: python resolve_suffix_cos.py <wheel_path> <extracted_dir> <package> <version>")
            sys.exit(1)

        wheel_path = sys.argv[1]
        extracted_dir = sys.argv[2]
        package = sys.argv[3]
        version = sys.argv[4]

        logger.info(f"Resolving suffix for → {wheel_path}")

        local_sha = sha256_file(wheel_path)
        if not local_sha:
            sys.exit(1)

        client = create_cos_client()
        if not client:
            sys.exit(1)

        wheel_name = os.path.basename(wheel_path)
        base_key = f"{package}/{version}"

        suffix = resolve_suffix(client, base_key, wheel_name, local_sha)

        if suffix is None:
            sys.exit(1)

        if suffix:
            logger.info(f"Applying suffix → {suffix}")

            dist_info_dir = find_dist_info_dir(extracted_dir)
            if not dist_info_dir:
                logger.error(".dist-info not found")
                sys.exit(1)

            old_version = read_version(dist_info_dir)
            if not old_version:
                sys.exit(1)

            new_version = build_new_version(old_version, suffix)

            if not update_version(dist_info_dir, new_version):
                sys.exit(1)

            dist_info_dir = rename_dist_info(extracted_dir, old_version, new_version)
            if not dist_info_dir:
                sys.exit(1)

            if not regenerate_record(extracted_dir, dist_info_dir):
                sys.exit(1)

        else:
            logger.info("No suffix needed")

        logger.info(f"Final suffix value → {suffix}")
        print(suffix)
    except Exception as e:
        logger.exception(f"Unexpected failure → {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
