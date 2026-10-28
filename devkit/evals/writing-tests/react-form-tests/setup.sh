#!/usr/bin/env bash
set -euo pipefail
git init -q -b main
git config user.email eval@example.com
git config user.name Eval
mkdir -p src/components/ui src/features
cat > package.json <<'EOF'
{
  "name": "shop-ui",
  "private": true,
  "type": "module",
  "packageManager": "pnpm@10.18.0",
  "scripts": { "dev": "vite", "build": "tsc -b && vite build", "test": "vitest run", "lint": "eslint ." },
  "dependencies": { "react": "^19.2.0", "react-dom": "^19.2.0", "@tanstack/react-query": "^5.90.0", "zod": "^4.1.0" },
  "devDependencies": { "typescript": "^5.9.0", "vite": "^7.1.0", "vitest": "^3.2.0", "@testing-library/react": "^16.3.0", "@testing-library/user-event": "^14.6.0", "msw": "^2.11.0" }
}
EOF
cat > src/components/ui/Button.tsx <<'EOF'
import type { ComponentProps } from 'react';

type ButtonProps = ComponentProps<'button'> & { variant?: 'primary' | 'danger' | 'ghost' };

export function Button({ variant = 'primary', className = '', ...props }: ButtonProps) {
  return <button className={`btn btn-${variant} ${className}`} {...props} />;
}
EOF
cat > src/components/ui/Dialog.tsx <<'EOF'
import type { ReactNode } from 'react';

type DialogProps = { open: boolean; title: string; onClose: () => void; children: ReactNode };

// Accessible modal: traps focus, closes on Escape, restores focus on close.
export function Dialog({ open, title, onClose, children }: DialogProps) {
  if (!open) return null;
  return (
    <div role="dialog" aria-modal="true" aria-label={title} onKeyDown={(e) => e.key === 'Escape' && onClose()}>
      <h2>{title}</h2>
      {children}
    </div>
  );
}
EOF
cat > src/features/LoginForm.tsx <<'EOF'
import { useState, type FormEvent } from 'react';
import { Button } from '../components/ui/Button';

export function LoginForm({ onSuccess }: { onSuccess: () => void }) {
  const [error, setError] = useState<string | null>(null);
  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const data = new FormData(e.currentTarget);
    const res = await fetch('/api/login', { method: 'POST', body: data });
    if (res.ok) onSuccess();
    else setError('Wrong email or password');
  }
  return (
    <form onSubmit={submit}>
      <label>Email <input name="email" type="email" required /></label>
      <label>Password <input name="password" type="password" required /></label>
      {error && <p role="alert">{error}</p>}
      <Button type="submit">Log in</Button>
    </form>
  );
}
EOF
