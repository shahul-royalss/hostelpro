import * as React from "react";
import { ExternalLink, FileText, Phone } from "lucide-react";
import type { StudentDirectoryRow } from "@/lib/queries/owner";
import { formatDate, formatINR, formatPeriodMonth, toPeriodMonth } from "@/lib/utils";
import { UserAvatar } from "@/components/ui/avatar";
import { StatusPill, Chip } from "@/components/shared/status-pill";
import { Button } from "@/components/ui/button";

/** Read-only student profile — used inside the OW-5 slide-over and the /owner/students/[id] page. */
export function StudentProfile({
  student,
  photoUrl,
  idProofUrl,
  filesLoading = false,
}: {
  student: StudentDirectoryRow;
  photoUrl: string | null;
  idProofUrl: string | null;
  filesLoading?: boolean;
}) {
  const s = student;
  const period = formatPeriodMonth(toPeriodMonth());
  const balance = Math.max(s.amount_due - s.amount_paid, 0);

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col items-center text-center">
        <UserAvatar name={s.full_name} src={photoUrl} size="xl" className="h-24 w-24 text-2xl" />
        <h3 className="mt-3 text-lg font-semibold text-navy">{s.full_name}</h3>
        <a href={`tel:${s.phone}`} className="mt-0.5 inline-flex items-center gap-1.5 text-sm text-charcoal hover:underline">
          <Phone className="h-3.5 w-3.5 text-muted" /> {s.phone}
        </a>
        {s.email ? <p className="text-[13px] text-muted">{s.email}</p> : null}
        <div className="mt-2 flex flex-wrap items-center justify-center gap-2">
          <StatusPill status={s.status} dot />
          {s.room_number ? <Chip tone="navy">Room {s.room_number}</Chip> : <Chip>No room</Chip>}
        </div>
      </div>

      {/* Room & fee */}
      <div className="grid grid-cols-2 gap-3">
        <InfoTile label="Room" value={s.room_number ? `${s.room_number}` : "—"} caption={s.floor_number != null ? `Floor ${s.floor_number}` : undefined} />
        <InfoTile label={`Fee · ${period}`} value={<StatusPill status={s.fee_status} />} caption={s.fee_status === "paid" ? `Paid ${formatINR(s.amount_paid)}` : `Due ${formatINR(balance)}`} />
      </div>

      <Section title="Stay">
        <Row label="Joined" value={formatDate(s.date_of_joining)} />
        <Row label="Monthly fee" value={<span className="font-semibold text-navy tabular">{formatINR(s.monthly_fee)}</span>} />
        <Row label="Status" value={<StatusPill status={s.status} size="sm" />} />
      </Section>

      <Section title="Guardian">
        <Row label="Name" value={s.guardian_name || "—"} />
        <Row
          label="Phone"
          value={
            s.guardian_phone ? (
              <a href={`tel:${s.guardian_phone}`} className="hover:underline">
                {s.guardian_phone}
              </a>
            ) : (
              "—"
            )
          }
        />
      </Section>

      <Section title="Address">
        <p className="whitespace-pre-line text-sm text-charcoal">{s.permanent_address?.trim() || <span className="text-muted">Not provided</span>}</p>
      </Section>

      <Section title="ID proof">
        <Row
          label="Type"
          value={s.id_proof_type ? <Chip>{s.id_proof_type}</Chip> : "—"}
          right={
            s.id_proof_url ? (
              idProofUrl ? (
                <Button asChild variant="secondary" size="sm">
                  <a href={idProofUrl} target="_blank" rel="noreferrer">
                    <FileText /> View <ExternalLink className="h-3 w-3" />
                  </a>
                </Button>
              ) : (
                <span className="text-xs text-muted">{filesLoading ? "Loading…" : "Preview unavailable"}</span>
              )
            ) : (
              <span className="text-xs text-muted">Not uploaded</span>
            )
          }
        />
      </Section>
    </div>
  );
}

function InfoTile({ label, value, caption }: { label: string; value: React.ReactNode; caption?: React.ReactNode }) {
  return (
    <div className="rounded-control border border-line/70 bg-white/60 px-3.5 py-3">
      <div className="label-caps">{label}</div>
      <div className="mt-1 text-lg font-semibold text-navy">{value}</div>
      {caption ? <div className="mt-0.5 text-[12px] text-muted">{caption}</div> : null}
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section>
      <div className="label-caps mb-2">{title}</div>
      <div className="divide-y divide-line/60 rounded-control border border-line/70 bg-white/60 px-3.5">{children}</div>
    </section>
  );
}

function Row({ label, value, right }: { label: string; value: React.ReactNode; right?: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-3 py-2.5 text-sm">
      <span className="text-muted">{label}</span>
      <span className="flex min-w-0 items-center gap-2 text-right text-charcoal">
        <span className="truncate">{value}</span>
        {right}
      </span>
    </div>
  );
}
