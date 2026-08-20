import { BellRing, CheckCheck, CreditCard, MapPin, Wrench } from "lucide-react";

import { relativeTime } from "@/lib/format";
import type { NoticeKind } from "@/lib/types";
import { cn } from "@/lib/utils";
import { useFleet } from "@/store/fleet";

const KIND_META: Record<NoticeKind, { label: string; icon: typeof Wrench; className: string }> = {
  maintenance: { label: "Mantenimiento", icon: Wrench, className: "bg-info/12 text-info" },
  credit: { label: "Crédito", icon: CreditCard, className: "bg-warning/12 text-warning" },
  station: { label: "Estación", icon: MapPin, className: "bg-primary/12 text-primary" },
  reminder: { label: "Recordatorio", icon: BellRing, className: "bg-secondary text-foreground" },
};

const Avisos = () => {
  const { notices, now, unreadNotices, markNoticeRead, markAllNoticesRead } = useFleet();

  return (
    <div className="space-y-4 px-4 pb-4 pt-6">
      <header className="flex items-end justify-between">
        <div>
          <p className="label-caps">Comunicación de estación</p>
          <h1 className="text-2xl font-black tracking-tight">Avisos</h1>
        </div>
        {unreadNotices > 0 && (
          <button
            type="button"
            onClick={markAllNoticesRead}
            className="press flex items-center gap-1.5 rounded-full border border-border/70 bg-secondary/40 px-3 py-2 text-xs font-bold"
          >
            <CheckCheck className="size-4" />
            Marcar leídos
          </button>
        )}
      </header>

      <div className="space-y-3">
        {notices.map((notice) => {
          const meta = KIND_META[notice.kind];
          const Icon = meta.icon;
          return (
            <button
              key={notice.id}
              type="button"
              onClick={() => markNoticeRead(notice.id)}
              className={cn(
                "press w-full rounded-2xl border p-4 text-left",
                notice.read ? "border-border/60 bg-secondary/25" : "border-primary/30 bg-card",
              )}
            >
              <div className="flex items-start gap-3">
                <span className={cn("grid size-10 shrink-0 place-items-center rounded-xl", meta.className)}>
                  <Icon className="size-5" />
                </span>
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <p className="label-caps">{meta.label}</p>
                    {!notice.read && <span className="size-1.5 rounded-full bg-destructive" />}
                    <span className="ml-auto text-[0.68rem] text-muted-foreground">
                      {relativeTime(notice.createdAt, now)}
                    </span>
                  </div>
                  <p className="mt-1 text-sm font-bold leading-snug">{notice.title}</p>
                  <p className="mt-1 text-xs leading-relaxed text-muted-foreground">{notice.body}</p>
                </div>
              </div>
            </button>
          );
        })}
      </div>
    </div>
  );
};

export default Avisos;
