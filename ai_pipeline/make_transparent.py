from PIL import Image
import sys

def make_transparent(img_path, output_path):
    print(f"Processing image: {img_path}...")
    img = Image.open(img_path).convert("RGBA")
    datas = img.getdata()

    newData = []
    for item in datas:
        # If the pixel is white or very close to white, make it transparent
        # Threshold: R > 245, G > 245, B > 245
        if item[0] > 245 and item[1] > 245 and item[2] > 245:
            newData.append((255, 255, 255, 0)) # Transparent
        else:
            newData.append(item)

    img.putdata(newData)
    img.save(output_path, "PNG")
    print(f"Saved transparent image to: {output_path}")

if __name__ == "__main__":
    src = "mobile/assets/App_Icon_Generation_3.png"
    if len(sys.argv) > 1:
        src = sys.argv[1]
    make_transparent(src, src)
