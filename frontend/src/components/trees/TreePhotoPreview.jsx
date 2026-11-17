import { Dialog, DialogContent, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { cn } from "@/lib/utils";

export default function TreePhotoPreview({
  src,
  label = "Original tree photo",
  alt = label,
  className,
  thumbnailClassName,
}) {
  if (!src) return null;

  return (
    <Dialog>
      <DialogTrigger asChild>
        <button
          type="button"
          aria-label={`Expand ${label}`}
          className={cn("block cursor-zoom-in focus-visible:ring-2 focus-visible:ring-primary", className)}
        >
          <img src={src} alt={alt} className={thumbnailClassName} />
        </button>
      </DialogTrigger>
      <DialogContent
        aria-describedby={undefined}
        className="w-[calc(100%_-_2rem)] max-w-4xl rounded-xl p-4 sm:p-6"
      >
        <DialogTitle className="pr-8">{label}</DialogTitle>
        <img src={src} alt={alt} className="mx-auto max-h-[75dvh] max-w-full object-contain" />
      </DialogContent>
    </Dialog>
  );
}
