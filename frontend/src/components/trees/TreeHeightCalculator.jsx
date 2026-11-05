import { useState } from "react";
import { Ruler } from "lucide-react";
import { calculateTreeHeightMeters } from "@/lib/treeHeight";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";

export default function TreeHeightCalculator({ onAccept }) {
  const [open, setOpen] = useState(false);
  const [distance, setDistance] = useState("");
  const [topAngle, setTopAngle] = useState("");
  const [baseAngle, setBaseAngle] = useState("");
  const [estimatedHeight, setEstimatedHeight] = useState(null);
  const [correctedHeight, setCorrectedHeight] = useState("");
  const [error, setError] = useState("");

  const resetResult = () => {
    setEstimatedHeight(null);
    setCorrectedHeight("");
    setError("");
  };

  const calculate = (event) => {
    event.preventDefault();
    try {
      const height = calculateTreeHeightMeters({
        horizontalDistanceMeters: distance,
        topAngleDegrees: topAngle,
        baseAngleDegrees: baseAngle,
      });
      setEstimatedHeight(height);
      setCorrectedHeight(height.toFixed(2));
      setError("");
    } catch (calculationError) {
      resetResult();
      setError(calculationError.message);
    }
  };

  const accept = () => {
    const value = Number(correctedHeight);
    if (!Number.isFinite(value) || value <= 0) {
      setError("Enter a corrected height greater than zero.");
      return;
    }
    onAccept(value);
    setOpen(false);
  };

  const close = () => {
    setOpen(false);
    setError("");
  };

  return (
    <>
      <Button
        type="button"
        size="sm"
        variant="outline"
        onClick={() => setOpen(true)}
        className="mt-2 w-fit"
      >
        <Ruler aria-hidden="true" />
        Calculate Tree Height
      </Button>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Calculate Tree Height</DialogTitle>
            <DialogDescription>
              Enter horizontal distance and signed sight angles. Use a negative
              base angle when the tree base is below your horizontal line of
              sight. This is an estimate; verify it before using it.
            </DialogDescription>
          </DialogHeader>
          <form onSubmit={calculate} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="height-distance">Horizontal distance (m)</Label>
              <Input
                id="height-distance"
                type="number"
                min="0"
                step="any"
                value={distance}
                onChange={(event) => {
                  setDistance(event.target.value);
                  resetResult();
                }}
                required
              />
            </div>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <div className="space-y-2">
                <Label htmlFor="height-top-angle">Angle to tree top (°)</Label>
                <Input
                  id="height-top-angle"
                  type="number"
                  step="any"
                  value={topAngle}
                  onChange={(event) => {
                    setTopAngle(event.target.value);
                    resetResult();
                  }}
                  required
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="height-base-angle">Angle to tree base (°)</Label>
                <Input
                  id="height-base-angle"
                  type="number"
                  step="any"
                  value={baseAngle}
                  onChange={(event) => {
                    setBaseAngle(event.target.value);
                    resetResult();
                  }}
                  required
                />
              </div>
            </div>
            <Button type="submit" variant="outline">
              Calculate Estimate
            </Button>
            {error && (
              <p className="text-sm text-destructive" role="alert">
                {error}
              </p>
            )}
            {estimatedHeight !== null && (
              <div
                className="space-y-3 rounded-md border border-primary/20 bg-primary/5 p-3"
                data-testid="tree-height-estimate"
              >
                <p className="font-medium text-foreground">
                  Estimated Tree Height: {estimatedHeight.toFixed(2)} m
                </p>
                <div className="space-y-2">
                  <Label htmlFor="height-correction">
                    Correct height if needed (m)
                  </Label>
                  <Input
                    id="height-correction"
                    type="number"
                    min="0"
                    step="any"
                    value={correctedHeight}
                    onChange={(event) => {
                      setCorrectedHeight(event.target.value);
                      setError("");
                    }}
                  />
                </div>
                <DialogFooter>
                  <Button type="button" variant="outline" onClick={close}>
                    Cancel
                  </Button>
                  <Button type="button" onClick={accept}>
                    Accept Height
                  </Button>
                </DialogFooter>
              </div>
            )}
            {estimatedHeight === null && (
              <DialogFooter>
                <Button type="button" variant="outline" onClick={close}>
                  Cancel
                </Button>
              </DialogFooter>
            )}
          </form>
        </DialogContent>
      </Dialog>
    </>
  );
}
