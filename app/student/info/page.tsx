import { Building2, Info, MapPin, Phone, ScrollText, ShieldCheck, UserCog } from "lucide-react";
import { MobilePage } from "@/components/shell/role-shells";
import { GlassCard, GlassCardHeader } from "@/components/shared/glass-card";
import { EmptyState } from "@/components/shared/empty-state";
import { UserAvatar } from "@/components/ui/avatar";
import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { getHostelContacts } from "@/lib/queries/student";
import { cn } from "@/lib/utils";

function ContactCard({
  role,
  name,
  phone,
  tone,
  icon: Icon,
}: {
  role: string;
  name: string | null;
  phone: string | null;
  tone: "teal" | "navy";
  icon: typeof ShieldCheck;
}) {
  return (
    <GlassCard className="flex items-center gap-3 p-4">
      {name ? (
        <UserAvatar name={name} size="md" />
      ) : (
        <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-stone text-muted">
          <Icon className="h-[18px] w-[18px]" strokeWidth={1.75} />
        </span>
      )}
      <div className="min-w-0 flex-1">
        <div className="label-caps">{role}</div>
        <div className="mt-0.5 truncate text-sm font-semibold text-navy">{name ?? "Not assigned yet"}</div>
        {phone ? (
          <div className="mt-0.5 text-[12px] text-muted">{phone}</div>
        ) : (
          <div className="mt-0.5 text-[12px] text-muted">No phone on file</div>
        )}
      </div>
      {phone ? (
        <a
          href={`tel:${phone}`}
          aria-label={`Call ${role.toLowerCase()} ${name ?? ""}`}
          className={cn(
            "flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-white transition-transform active:scale-95",
            tone === "teal" ? "bg-teal" : "bg-navy",
          )}
        >
          <Phone className="h-4 w-4" />
        </a>
      ) : null}
    </GlassCard>
  );
}

export default async function StudentInfoPage() {
  const { ctx } = await requireHostelContext("student");
  const supabase = await createClient();
  const contacts = await getHostelContacts(supabase);

  const hostelName = contacts?.hostel_name ?? ctx.hostel.name;
  const address = contacts?.address ?? ctx.hostel.address;
  const rules = (contacts?.rules ?? ctx.hostel.rules ?? "").trim();
  const ruleLines = rules
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter(Boolean);

  return (
    <MobilePage role="student" title="Hostel info" subtitle={hostelName} backHref="/student">
      <div className="flex flex-col gap-4">
        {/* Hostel card */}
        <GlassCard strong className="p-5">
          <div className="flex items-start gap-3">
            <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-control bg-navy/10 text-navy">
              <Building2 className="h-5 w-5" strokeWidth={1.75} />
            </span>
            <div className="min-w-0 flex-1">
              <div className="label-caps">Your hostel</div>
              <div className="mt-0.5 text-[20px] font-bold leading-tight text-navy">{hostelName}</div>
              {address ? (
                <a
                  href={`https://maps.google.com/?q=${encodeURIComponent(address)}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="mt-1.5 flex items-start gap-1.5 text-[13px] leading-snug text-charcoal/80 active:opacity-70"
                >
                  <MapPin className="mt-0.5 h-3.5 w-3.5 shrink-0 text-muted" />
                  <span>{address}</span>
                </a>
              ) : (
                <div className="mt-1.5 text-[13px] text-muted">Address not added yet</div>
              )}
              {contacts?.owner_name ? (
                <div className="mt-2 text-[12px] text-muted">Owned by {contacts.owner_name}</div>
              ) : null}
            </div>
          </div>
        </GlassCard>

        {/* Contacts */}
        <section>
          <h2 className="mb-3 px-1 text-card-title font-semibold text-navy">Contacts</h2>
          <div className="flex flex-col gap-3">
            <ContactCard role="Warden" name={contacts?.warden_name ?? null} phone={contacts?.warden_phone ?? null} tone="navy" icon={ShieldCheck} />
            <ContactCard role="Manager" name={contacts?.manager_name ?? null} phone={contacts?.manager_phone ?? null} tone="teal" icon={UserCog} />
          </div>
          <p className="mt-2 px-1 text-[12px] text-muted">
            For room, fee or leave questions contact the warden; for mess and bills contact the manager.
          </p>
        </section>

        {/* Rules */}
        <GlassCard>
          <GlassCardHeader title="Hostel rules" description="Set by the hostel owner" />
          {ruleLines.length === 0 ? (
            <EmptyState compact icon={ScrollText} title="No rules published yet" description="Your hostel hasn't added rules. Ask your warden if unsure." />
          ) : (
            <ol className="flex flex-col gap-2.5">
              {ruleLines.map((line, i) => {
                const text = line.replace(/^\s*(\d+[.)]|[-•*])\s*/, "");
                return (
                  <li key={i} className="flex gap-3 text-sm leading-relaxed text-charcoal">
                    <span className="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-navy/5 text-[11px] font-semibold text-navy tabular">
                      {i + 1}
                    </span>
                    <span>{text}</span>
                  </li>
                );
              })}
            </ol>
          )}
        </GlassCard>

        <div className="flex items-start gap-2 px-1 text-[12px] text-muted">
          <Info className="mt-0.5 h-3.5 w-3.5 shrink-0" />
          <span>Contact details are shared by your hostel so you can reach staff quickly. Please use them respectfully.</span>
        </div>
      </div>
    </MobilePage>
  );
}
