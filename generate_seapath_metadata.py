#!/usr/bin/env python3

from pathlib import Path
import xml.etree.ElementTree as ET
import hashlib
from os import environ

working_dir = environ.get("output_dir", "")
bmap_file = f"{environ.get('OUTPUT', '')}.bmap"

ImageName = ""
ImageDescription = ""

role = environ.get("role", "")
role = role.lower()

if "standalone" in role:
    ImageName = "SEAPATH Debian hypervisor"
    ImageDescription = "A production hypervisor image for a SEAPATH standalone setup"
    setup = "Standalone"
elif "cluster" in role:
    ImageName = "SEAPATH Debian hypervisor"
    ImageDescription = "A production hypervisor image for a SEAPATH cluster setup"
    setup = "Cluster"
elif "observer" in role:
    ImageName = "SEAPATH Debian observer"
    ImageDescription = "A production observer image for a SEAPATH cluster setup"
    setup = "Cluster"


bmap_path = Path(working_dir) / bmap_file
if not bmap_path.exists():
    raise FileNotFoundError("Missing bmap file: %s" % bmap_path)

bmap_tree = ET.parse(str(bmap_path))
root = bmap_tree.getroot()

seapath_version = environ.get("SEAPATH_VERSION", "unknown")

for tag, value in [
    ("ImageName", ImageName),
    ("ImageVersion", seapath_version),
    ("ImageDescription", ImageDescription),
    ("ImageSetup", setup),
    ("ImageFlavor", "Debian"),
]:
    node = ET.SubElement(root, tag)
    node.text = f" {value} "
    node.tail = "\n"

bmap_file_checksum = root.find("BmapFileChecksum")
len_bmap_file_checksum = len(str.strip(bmap_file_checksum.text))

bmap_file_checksum.text = "0" * len_bmap_file_checksum
root.tail = "\n"

bmap_tree.write(str(bmap_path), encoding="utf-8", xml_declaration=False)

checksum_type = root.find("ChecksumType")

block_size = root.find("BlockSize")
block_size_value = int(str.strip(block_size.text))
hash_obj = hashlib.new(str.strip(checksum_type.text))

with open(bmap_path, "rb") as file:
    while chunk := file.read(block_size_value):
        hash_obj.update(chunk)

bmap_file_updated_hash = hash_obj.hexdigest()
bmap_file_checksum.text = bmap_file_updated_hash

bmap_tree.write(str(bmap_path), encoding="utf-8", xml_declaration=False)
