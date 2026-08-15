"use client";

import * as React from "react";
import { LogOut } from "lucide-react";
import { Button } from "@/components/ui/button";
import { signOut } from "@/lib/actions/session";

/** Red ghost "Log out" row at the bottom of ST-2. */
export function LogoutButton() {
  const [pending, start] = React.useTransition();
  return (
    <Button
      type="button"
      variant="ghost"
      size="xl"
      loading={pending}
      onClick={() => start(async () => { await signOut(); })}
      className="text-red hover:bg-red-soft hover:text-red"
    >
      <LogOut />
      Log out
    </Button>
  );
}
