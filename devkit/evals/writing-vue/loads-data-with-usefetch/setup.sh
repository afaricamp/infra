#!/usr/bin/env bash
set -euo pipefail
git init -q -b main
git config user.email eval@example.com
git config user.name Eval
mkdir -p app/components/ui app/pages server/api/users
cat > package.json <<'JSON'
{
  "name": "shop-web",
  "private": true,
  "type": "module",
  "packageManager": "pnpm@10.18.0",
  "scripts": { "dev": "nuxt dev", "build": "nuxt build", "typecheck": "nuxt typecheck", "test": "vitest run", "lint": "eslint ." },
  "dependencies": { "nuxt": "^4.1.0", "vue": "^3.5.0", "zod": "^4.1.0" },
  "devDependencies": { "typescript": "^5.9.0", "vue-tsc": "^3.1.0", "vitest": "^3.2.0", "@nuxt/test-utils": "^3.19.0", "@vue/test-utils": "^2.4.0" }
}
JSON
cat > nuxt.config.ts <<'TS'
export default defineNuxtConfig({
  compatibilityDate: '2025-07-15',
  typescript: { strict: true },
});
TS
cat > app/components/ui/BaseCard.vue <<'VUE'
<script setup lang="ts">
defineProps<{ title: string }>();
</script>

<template>
  <section class="card">
    <h2>{{ title }}</h2>
    <slot />
  </section>
</template>
VUE
cat > 'server/api/users/[id].get.ts' <<'TS'
export default defineEventHandler((event) => {
  const id = getRouterParam(event, 'id');
  return { id, name: 'Ada Lovelace', email: 'ada@example.com' };
});
TS
