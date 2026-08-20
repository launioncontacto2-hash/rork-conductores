const PREFIX = "turnoev";

/** localStorage wrapper that never throws (private mode, quota, SSR). */
export const loadState = <T,>(key: string): T | null => {
  try {
    const raw = window.localStorage.getItem(`${PREFIX}.${key}`);
    return raw ? (JSON.parse(raw) as T) : null;
  } catch (error) {
    console.warn("No se pudo leer el estado local", error);
    return null;
  }
};

export const saveState = <T,>(key: string, value: T): void => {
  try {
    window.localStorage.setItem(`${PREFIX}.${key}`, JSON.stringify(value));
  } catch (error) {
    console.warn("No se pudo guardar el estado local", error);
  }
};

export const clearState = (key: string): void => {
  try {
    window.localStorage.removeItem(`${PREFIX}.${key}`);
  } catch (error) {
    console.warn("No se pudo limpiar el estado local", error);
  }
};

/**
 * Downscales a captured photo to a compact JPEG data URL so evidence can be
 * stored locally without blowing the storage quota. Ready to be swapped for a
 * real upload + OCR pipeline later.
 */
export const compressImage = async (file: File, maxSize = 720): Promise<string> => {
  const bitmapUrl = URL.createObjectURL(file);
  try {
    const image = await new Promise<HTMLImageElement>((resolve, reject) => {
      const element = new Image();
      element.onload = () => resolve(element);
      element.onerror = () => reject(new Error("Imagen inválida"));
      element.src = bitmapUrl;
    });

    const scale = Math.min(1, maxSize / Math.max(image.width, image.height));
    const canvas = document.createElement("canvas");
    canvas.width = Math.round(image.width * scale);
    canvas.height = Math.round(image.height * scale);
    const context = canvas.getContext("2d");
    if (!context) return bitmapUrl;
    context.drawImage(image, 0, 0, canvas.width, canvas.height);
    return canvas.toDataURL("image/jpeg", 0.72);
  } finally {
    URL.revokeObjectURL(bitmapUrl);
  }
};
