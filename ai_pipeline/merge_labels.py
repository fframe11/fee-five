import os
import shutil
import yaml

# Unified 8-Class Mapping
UNIFIED_CLASSES = [
    "person", "pole", "pothole", "stairs", "ramp", "elevator", "door", "curb"
]
CLASS_MAP = {c: i for i, c in enumerate(UNIFIED_CLASSES)}

# Original dataset class mapping definitions
DATASETS = {
    "accessibility_obj": {
        "path": "datasets/accessibility_obj",
        "classes": {
            "person": "person",
            "pit_hole": "pothole",
            "stairs": "stairs",
            "ramps": "ramp",
            "elevator": "elevator",
            "doors": "door",
        }
    },
    "ds_pgsa": {
        "path": "datasets/ds_pgsa",
        "classes": {
            "person": "person",
            "pole": "pole",
            "electric pole": "pole",
            "stairs": "stairs",
            "pothole": "pothole",
            "curb": "curb",
            "footpath": "curb",
        }
    },
    "allen_atrium": {
        "path": "datasets/allen_atrium",
        "classes": {
            "door": "door",
            "elevator": "elevator",
            "slope": "ramp",
            "stairs": "stairs",
        }
    }
}

def merge_datasets():
    merged_path = "datasets/merged"
    for split in ["train", "valid", "test"]:
        os.makedirs(os.path.join(merged_path, split, "images"), exist_ok=True)
        os.makedirs(os.path.join(merged_path, split, "labels"), exist_ok=True)

    for name, config in DATASETS.items():
        base_path = config["path"]
        if not os.path.exists(base_path):
            print(f"Skipping {name}: directory not found.")
            continue

        # Load dataset YAML configuration
        data_yaml = os.path.join(base_path, "data.yaml")
        if not os.path.exists(data_yaml):
            continue
        with open(data_yaml, 'r') as f:
            meta = yaml.safe_load(f)
            orig_names = meta.get("names", [])

        # Process each data split
        for split in ["train", "valid", "val", "test"]:
            tgt_split = "valid" if split in ["val", "valid"] else split
            split_labels_dir = os.path.join(base_path, split, "labels")
            split_images_dir = os.path.join(base_path, split, "images")
            
            if not os.path.exists(split_labels_dir):
                continue

            for file in os.listdir(split_labels_dir):
                if not file.endswith(".txt"):
                    continue

                label_file = os.path.join(split_labels_dir, file)
                img_file = os.path.join(split_images_dir, file.replace(".txt", ".jpg"))
                if not os.path.exists(img_file):
                    img_file = os.path.join(split_images_dir, file.replace(".txt", ".png"))
                if not os.path.exists(img_file):
                    continue

                # Process labels and write to merged folder
                new_labels = []
                with open(label_file, 'r') as f:
                    for line in f:
                        parts = line.strip().split()
                        if not parts:
                            continue
                        class_idx = int(parts[0])
                        if class_idx >= len(orig_names):
                            continue
                        
                        orig_class_name = orig_names[class_idx]
                        mapped_class = config["classes"].get(orig_class_name)
                        
                        if mapped_class and mapped_class in CLASS_MAP:
                            new_class_idx = CLASS_MAP[mapped_class]
                            new_labels.append(f"{new_class_idx} {' '.join(parts[1:])}")

                if new_labels:
                    unique_id = f"{name}_{file}"
                    # Copy image
                    shutil.copy(img_file, os.path.join(merged_path, tgt_split, "images", unique_id.replace(".txt", os.path.splitext(img_file)[1])))
                    # Write merged label
                    with open(os.path.join(merged_path, tgt_split, "labels", unique_id), 'w') as out_f:
                        out_f.write("\n".join(new_labels) + "\n")

    # Generate merged data.yaml
    merged_yaml = {
        "path": os.path.abspath(merged_path),
        "train": "train/images",
        "val": "valid/images",
        "test": "test/images",
        "names": {i: name for i, name in enumerate(UNIFIED_CLASSES)}
    }
    with open(os.path.join(merged_path, "data.yaml"), 'w') as f:
        yaml.safe_dump(merged_yaml, f)
    print(f"Merged datasets created successfully at {merged_path}")

if __name__ == "__main__":
    merge_datasets()
