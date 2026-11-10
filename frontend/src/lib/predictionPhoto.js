// Derivative for display-only AI uploads. Never replaces the inventory photo
// or supplies EXIF/calibration data to a measured DBH path.
export async function preparePredictionPhoto(file) {
  if (!['image/jpeg', 'image/png', 'image/webp'].includes(file?.type)) {
    throw new Error('Choose a JPEG, PNG or WebP photo.');
  }
  if (file.size <= 1_800_000) return file;
  let image;
  let objectUrl;
  try {
    if (typeof createImageBitmap === 'function') image = await createImageBitmap(file);
    else {
      objectUrl = URL.createObjectURL(file);
      image = await new Promise((resolve, reject) => {
        const img = new Image();
        img.onload = () => resolve(img);
        img.onerror = () => reject(new Error('This image could not be opened.'));
        img.src = objectUrl;
      });
    }
    if (image.width * image.height > 20_000_000) throw new Error('Choose a photo smaller than 20 megapixels.');
    const canvas = document.createElement('canvas');
    let scale = Math.min(1, 1600 / Math.max(image.width, image.height));
    for (let attempt = 0; attempt < 4; attempt++) {
      canvas.width = Math.max(1, Math.round(image.width * scale));
      canvas.height = Math.max(1, Math.round(image.height * scale));
      canvas.getContext('2d').drawImage(image, 0, 0, canvas.width, canvas.height);
      const blob = await new Promise(resolve => canvas.toBlob(resolve, 'image/jpeg', 0.85 - attempt * 0.1));
      if (blob && blob.size <= 1_800_000) return new File([blob], 'prediction.jpg', { type: 'image/jpeg' });
      scale *= 0.75;
    }
    throw new Error('This photo is too large. Choose a smaller image.');
  } finally {
    image?.close?.();
    if (objectUrl) URL.revokeObjectURL(objectUrl);
  }
}
