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

    const set = (k, v) => setForm(f => ({ ...f, [k]: v }));

    const handleSubmit = (e) => {
        e.preventDefault();
        onSubmit({
            ...form,
            dbh_cm: form.dbh_cm ? parseFloat(form.dbh_cm) : undefined,
            height_m: form.height_m ? parseFloat(form.height_m) : undefined,
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
                    <Input type="number" step="0.01" value={form.dbh_cm} onChange={e => set("dbh_cm", e.target.value)} placeholder="Current DBH" />
                </div>
                <div className="space-y-2">
                    <Label>Height (m)</Label>
                    <Input type="number" step="0.01" value={form.height_m} onChange={e => set("height_m", e.target.value)} placeholder="Current Height" />
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