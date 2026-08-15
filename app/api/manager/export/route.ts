import { NextResponse, type NextRequest } from "next/server";
import { getHostelContext, getSessionUser } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { getExpenses, getRevenues } from "@/lib/queries/manager";
import { exportSchema } from "@/lib/validators/manager";
import { formatPeriodMonth, titleCase } from "@/lib/utils";

export const dynamic = "force-dynamic";

/** Quote a CSV cell (RFC 4180) and neutralise spreadsheet formula injection. */
function csvCell(value: string | number | null | undefined): string {
  let s = value === null || value === undefined ? "" : String(value);
  if (/^[=+\-@\t\r]/.test(s)) s = `'${s}`;
  return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

const BOM = String.fromCharCode(0xfeff);

function toCsv(header: string[], rows: (string | number | null | undefined)[][]): string {
  const lines = [header, ...rows].map((r) => r.map(csvCell).join(","));
  // BOM so Excel opens the ₹ / UTF-8 content correctly.
  return `${BOM}${lines.join("\r\n")}\r\n`;
}

/**
 * GET /api/manager/export?type=expenses|revenue&month=YYYY-MM
 * Monthly CSV export for the manager (owner may also download their hostel's data).
 */
export async function GET(req: NextRequest) {
  const user = await getSessionUser();
  if (!user) return NextResponse.json({ error: "Not signed in." }, { status: 401 });
  if (user.role !== "manager" && user.role !== "owner") return NextResponse.json({ error: "Forbidden." }, { status: 403 });

  const ctx = await getHostelContext();
  if (!ctx) return NextResponse.json({ error: "No hostel is linked to your account." }, { status: 403 });

  const params = req.nextUrl.searchParams;
  const parsed = exportSchema.safeParse({ type: params.get("type") ?? "", month: params.get("month") ?? "" });
  if (!parsed.success) return NextResponse.json({ error: "Invalid export request. Expected ?type=expenses|revenue&month=YYYY-MM." }, { status: 400 });
  const { type, month } = parsed.data;

  try {
    const supabase = await createClient();
    let csv: string;
    if (type === "expenses") {
      const rows = await getExpenses(supabase, ctx.hostel.id, month);
      const total = rows.reduce((s, r) => s + Number(r.amount), 0);
      csv = toCsv(
        ["Date", "Category", "Amount (INR)", "Note", "Receipt attached", "Recorded at"],
        [
          ...rows.map((r) => [r.date, titleCase(r.category), Number(r.amount).toFixed(2), r.note ?? "", r.receipt_url ? "Yes" : "No", r.created_at]),
          ["Total", "", total.toFixed(2), `${rows.length} entries · ${formatPeriodMonth(month)}`, "", ""],
        ],
      );
    } else {
      const rows = await getRevenues(supabase, ctx.hostel.id, month);
      const total = rows.reduce((s, r) => s + Number(r.amount), 0);
      csv = toCsv(
        ["Date", "Source", "Amount (INR)", "Note", "Recorded at"],
        [
          ...rows.map((r) => [r.date, titleCase(r.source), Number(r.amount).toFixed(2), r.note ?? "", r.created_at]),
          ["Total", "", total.toFixed(2), `${rows.length} entries · ${formatPeriodMonth(month)}`, ""],
        ],
      );
    }

    const slug = ctx.hostel.name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "") || "hostel";
    const filename = `${slug}-${type}-${month}.csv`;
    return new NextResponse(csv, {
      status: 200,
      headers: {
        "Content-Type": "text/csv; charset=utf-8",
        "Content-Disposition": `attachment; filename="${filename}"`,
        "Cache-Control": "no-store",
      },
    });
  } catch (e) {
    const message = e instanceof Error ? e.message : "Export failed.";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
