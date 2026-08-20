import { CameraOff, Keyboard, QrCode, ScanLine } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";

import { BigButton } from "@/components/Pieces";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";

interface DetectedBarcode {
  rawValue: string;
}

interface BarcodeDetectorLike {
  detect: (source: HTMLVideoElement) => Promise<DetectedBarcode[]>;
}

type BarcodeDetectorConstructor = new (options: { formats: string[] }) => BarcodeDetectorLike;

const getDetector = (): BarcodeDetectorLike | null => {
  const candidate = (window as unknown as { BarcodeDetector?: BarcodeDetectorConstructor }).BarcodeDetector;
  if (!candidate) return null;
  try {
    return new candidate({ formats: ["qr_code"] });
  } catch (error) {
    console.warn("BarcodeDetector no disponible", error);
    return null;
  }
};

/**
 * Live QR reader for the windshield sticker. Uses the native BarcodeDetector when
 * available and always keeps a manual code entry as fallback.
 */
export const QrScanner = ({
  onDetected,
  knownCodes,
}: {
  onDetected: (code: string) => void;
  knownCodes: string[];
}) => {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const [cameraError, setCameraError] = useState<string | null>(null);
  const [isManual, setIsManual] = useState<boolean>(false);
  const [manualCode, setManualCode] = useState<string>("");

  const stop = useCallback((): void => {
    streamRef.current?.getTracks().forEach((track) => track.stop());
    streamRef.current = null;
  }, []);

  useEffect(() => {
    let cancelled = false;
    let frameTimer = 0;

    const start = async (): Promise<void> => {
      try {
        const stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: { ideal: "environment" } },
          audio: false,
        });
        if (cancelled) {
          stream.getTracks().forEach((track) => track.stop());
          return;
        }
        streamRef.current = stream;
        if (videoRef.current) {
          videoRef.current.srcObject = stream;
          await videoRef.current.play();
        }

        const detector = getDetector();
        if (!detector) return;

        const scan = async (): Promise<void> => {
          if (cancelled || !videoRef.current) return;
          try {
            const results = await detector.detect(videoRef.current);
            const hit = results.find((result) => result.rawValue.trim().length > 0);
            if (hit) {
              onDetected(hit.rawValue.trim());
              return;
            }
          } catch {
            /* frame not ready — keep scanning */
          }
          frameTimer = window.setTimeout(() => void scan(), 350);
        };
        void scan();
      } catch (error) {
        console.warn("Cámara no disponible", error);
        if (!cancelled) setCameraError("Cámara no disponible en este dispositivo");
      }
    };

    void start();
    return () => {
      cancelled = true;
      window.clearTimeout(frameTimer);
      stop();
    };
  }, [onDetected, stop]);

  return (
    <div className="space-y-4">
      <div className="relative aspect-square w-full overflow-hidden rounded-3xl border border-border/70 bg-black">
        <video ref={videoRef} playsInline muted className="size-full object-cover" />

        {cameraError && (
          <div className="absolute inset-0 grid place-items-center gap-2 bg-secondary/40 text-center">
            <CameraOff className="mx-auto size-9 text-muted-foreground" />
            <p className="px-8 text-sm text-muted-foreground">{cameraError}</p>
          </div>
        )}

        {/* Framing guides */}
        <div className="pointer-events-none absolute inset-0 grid place-items-center">
          <div className="relative size-52">
            {["left-0 top-0 border-l-4 border-t-4", "right-0 top-0 border-r-4 border-t-4", "left-0 bottom-0 border-l-4 border-b-4", "right-0 bottom-0 border-r-4 border-b-4"].map(
              (corner) => (
                <span key={corner} className={cn("absolute size-10 rounded-md border-primary", corner)} />
              ),
            )}
            <span className="absolute left-2 right-2 h-0.5 animate-scan-sweep bg-primary shadow-[0_0_14px_hsl(var(--primary))]" />
          </div>
        </div>

        <div className="absolute inset-x-0 bottom-0 flex items-center justify-center gap-2 bg-gradient-to-t from-black/85 to-transparent p-4 text-xs font-semibold">
          <ScanLine className="size-4 text-primary" />
          Centra el código QR del parabrisas
        </div>
      </div>

      {isManual ? (
        <div className="space-y-3">
          <Input
            value={manualCode}
            onChange={(event) => setManualCode(event.target.value.toUpperCase())}
            placeholder="TEV-014"
            className="h-14 rounded-2xl text-center text-lg font-bold tracking-[0.2em]"
          />
          <BigButton
            onClick={() => onDetected(manualCode.trim())}
            disabled={manualCode.trim().length < 3}
            icon={<QrCode className="size-5" />}
          >
            Validar unidad
          </BigButton>
        </div>
      ) : (
        <button
          type="button"
          onClick={() => setIsManual(true)}
          className="press flex h-12 w-full items-center justify-center gap-2 rounded-2xl border border-border/70 bg-secondary/40 text-sm font-semibold"
        >
          <Keyboard className="size-4" />
          Capturar número interno
        </button>
      )}

      <div className="flex flex-wrap gap-2">
        {knownCodes.map((code) => (
          <button
            key={code}
            type="button"
            onClick={() => onDetected(code)}
            className="press rounded-full border border-border/70 bg-secondary/40 px-3 py-1.5 text-xs font-semibold text-muted-foreground"
          >
            {code}
          </button>
        ))}
      </div>
    </div>
  );
};
