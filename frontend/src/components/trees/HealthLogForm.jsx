import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

export default function HealthLogForm({ onSubmit, onCancel }) {
    const [form, setForm] = useState({
        condition: "Healthy",
        assessed_date: new Date().toISOString().split("T")[0],
        notes: "",
        dbh_cm: "",
        height_m: "",
    });
    const [errors, setErrors] = useState({});

    const set = (k, v) => {
        setForm(f => ({ ...f, [k]: v }));
        if (k === "dbh_cm" || k === "height_m") {
            setErrors(current => ({ ...current, [k]: undefined }));
        }
    };

    const validateOptionalMeasurement = (value, label) => {
        const text = value.trim();
        if (!text) return { value: undefined };

        const measurement = Number(text);
        if (!Number.isFinite(measurement) || measurement <= 0) {
            return { error: `${label} must be a finite positive number.` };
        }
        return { value: measurement };
    };

    const handleSubmit = (e) => {
        e.preventDefault();
        const dbh = validateOptionalMeasurement(form.dbh_cm, "DBH");
        const height = validateOptionalMeasurement(form.height_m, "Height");
        const nextErrors = {
            dbh_cm: dbh.error,
            height_m: height.error,
        };
        setErrors(nextErrors);
        if (dbh.error || height.error) return;

        const { dbh_cm, height_m, ...payload } = form;
        onSubmit({
            ...payload,
            ...(dbh.value !== undefined ? { dbh_cm: dbh.value } : {}),
            ...(height.value !== undefined ? { height_m: height.value } : {}),
        });
    };

    return (
        <form onSubmit={handleSubmit} className="space-y-4">
            <h3 className="font-fraunces text-lg font-medium">New Health Assessment</h3>
            <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                    <Label>Condition *</Label>
                    <Select value={form.condition} onValueChange={v => set("condition", v)}>
                        <SelectTrigger><SelectValue /></SelectTrigger>
                        <SelectContent>
                            <SelectItem value="Healthy">Healthy</SelectItem>
                            <SelectItem value="Fair">Fair</SelectItem>
                            <SelectItem value="Poor">Poor</SelectItem>
                        </SelectContent>
                    </Select>
                </div>
                <div className="space-y-2">
                    <Label>Assessment Date *</Label>
                    <Input type="date" value={form.assessed_date} onChange={e => set("assessed_date", e.target.value)} required />
                </div>
                <div className="space-y-2">
                    <Label>DBH (cm)</Label>
                    <Input type="number" step="0.01" value={form.dbh_cm} onChange={e => set("dbh_cm", e.target.value)} placeholder="Current DBH" aria-invalid={Boolean(errors.dbh_cm)} />
                    {errors.dbh_cm && <p className="text-sm text-destructive" role="alert">{errors.dbh_cm}</p>}
                </div>
                <div className="space-y-2">
                    <Label>Height (m)</Label>
                    <Input type="number" step="0.01" value={form.height_m} onChange={e => set("height_m", e.target.value)} placeholder="Current Height" aria-invalid={Boolean(errors.height_m)} />
                    {errors.height_m && <p className="text-sm text-destructive" role="alert">{errors.height_m}</p>}
                </div>
            </div>
            <div className="space-y-2">
                <Label>Observations</Label>
                <Textarea value={form.notes} onChange={e => set("notes", e.target.value)} placeholder="Describe the tree condition, pests, damage, changes…" rows={3} />
            </div>
            <div className="flex gap-2 justify-end">
                <Button type="button" variant="outline" onClick={onCancel}>Cancel</Button>
                <Button type="submit">Save Assessment</Button>
            </div>
        </form>
    );
}
