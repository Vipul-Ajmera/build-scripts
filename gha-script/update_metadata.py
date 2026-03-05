import os
import hashlib
import logging
import sys

logging.basicConfig(level=logging.INFO,
    format="[%(levelname)s] %(asctime)s - %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    stream=sys.stdout,)

logger = logging.getLogger(__name__)

CLASSIFIER = "Classifier: Environment :: MetaData :: IBM Python Ecosystem"


def find_dist_info_dir(extracted_path):
    try:
        logger.info(f"Locating .dist-info in {extracted_path}")
        for d in os.listdir(extracted_path):
            if d.endswith(".dist-info"):
                dist_info = os.path.join(extracted_path, d)
                logger.info(f"Found dist-info → {dist_info}")
                return dist_info

        logger.warning(".dist-info directory not found")
        return None

    except Exception as e:
        logger.exception(f"Failed scanning dist-info → {e}")
        return None


def modify_metadata_classifier(dist_info_dir):
    try:
        logger.info("Modifying METADATA to inject IBM classifier")
        metadata_file = os.path.join(dist_info_dir, "METADATA")
        if not os.path.exists(metadata_file):
            logger.warning(f"METADATA file missing → {metadata_file}")
            return False

        logger.debug(f"Modifying METADATA → {metadata_file}")

        with open(metadata_file, "r", encoding="utf-8") as f:
            lines = f.readlines()

        if any(line.strip() == CLASSIFIER for line in lines):
            logger.info("Classifier already present → skipping")
            return True

        classifier_indexes = [i for i, l in enumerate(lines) if l.startswith("Classifier:")]
        project_url_indexes = [i for i, l in enumerate(lines) if l.startswith("Project-URL:")]

        insert_at = 0
        if classifier_indexes:
            insert_at = classifier_indexes[-1] + 1
        elif project_url_indexes:
            insert_at = project_url_indexes[-1] + 1

        lines.insert(insert_at, f"{CLASSIFIER}\n")

        with open(metadata_file, "w", encoding="utf-8") as f:
            f.writelines(lines)

        logger.info("IBM classifier injected successfully")
        return True

    except Exception as e:
        logger.exception(f"Classifier injection failed → {e}")
        return False


def hash_file_sha256(path):
    try:
        h = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(8192), b""):
                h.update(chunk)
        return "sha256=" + h.digest().hex()
    except Exception as e:
        logger.exception(f"SHA256 hash failed → {e}")
        return None


def regenerate_record(extract_path, dist_info_dir):
    try:
        record_path = os.path.join(dist_info_dir, "RECORD")
        if not os.path.exists(record_path):
            logger.warning(f"RECORD file missing → {record_path}")
            return False

        logger.info("Regenerating RECORD")

        records = []

        for root, _, files in os.walk(extract_path):
            for fname in files:
                full_path = os.path.join(root, fname)
                rel_path = os.path.relpath(full_path, extract_path).replace(os.sep, "/")

                if rel_path.endswith("RECORD"):
                    records.append(f"{rel_path},,")
                    continue

                size = os.path.getsize(full_path)
                digest = hash_file_sha256(full_path)

                if not digest:
                    logger.error(f"Failed hashing → {rel_path}")
                    return False

                records.append(f"{rel_path},{digest},{size}")

        with open(record_path, "w", encoding="utf-8") as f:
            f.write("\n".join(records))

        logger.info("RECORD regenerated successfully")
        return True

    except Exception as e:
        logger.exception(f"RECORD regeneration failed → {e}")
        return False


def update_metadata(extracted_path):
    try:
        logger.info(f"Starting metadata update → {extracted_path}")

        dist_info_dir = find_dist_info_dir(extracted_path)
        if not dist_info_dir:
            return False

        if not modify_metadata_classifier(dist_info_dir):
            return False

        if not regenerate_record(extracted_path, dist_info_dir):
            return False

        logger.info("Metadata update completed successfully")
        return True

    except Exception as e:
        logger.exception(f"Metadata update crashed → {e}")
        return False


if __name__ == "__main__":
    if len(sys.argv) != 2:
        logger.error("Usage: python update_metadata.py <extracted_dir>")
        sys.exit(1)

    extracted_dir = sys.argv[1]

    if not update_metadata(extracted_dir):
        sys.exit(1)