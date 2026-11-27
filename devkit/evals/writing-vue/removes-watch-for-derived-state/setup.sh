#!/usr/bin/env bash
set -euo pipefail
git init -q -b main
git config user.email eval@example.com
git config user.name Eval
mkdir -p src/components/ui src/features
cat > package.json <<'JSON'
{
  "name": "shop-web",
  "private": true,
  "type": "module",
  "packageManager": "pnpm@10.18.0",
  "scripts": { "dev": "vite", "build": "vue-tsc -b && vite build", "test": "vitest run", "lint": "eslint ." },
  "dependencies": { "vue": "^3.5.0", "pinia": "^3.0.0", "zod": "^4.1.0" },
  "devDependencies": { "typescript": "^5.9.0", "vite": "^7.1.0", "@vitejs/plugin-vue": "^6.0.0", "vue-tsc": "^3.1.0", "vitest": "^3.2.0", "@vue/test-utils": "^2.4.0" }
}
JSON
cat > src/components/ui/BaseButton.vue <<'VUE'
<script setup lang="ts">
const { variant = 'primary' } = defineProps<{ variant?: 'primary' | 'danger' | 'ghost' }>();
</script>

<template>
  <button :class="['btn', `btn-${variant}`]"><slot /></button>
</template>
VUE
cat > src/features/ProductList.vue <<'VUE'
<script setup lang="ts">
import { ref, watch } from 'vue';

type Product = { id: string; name: string; hidden: boolean };

const props = defineProps<{ products: Product[] }>();

const query = ref('');
const visible = ref<Product[]>(props.products);

watch(query, (q) => {
  visible.value = props.products.filter((p) => p.name.toLowerCase().includes(q.toLowerCase()));
});
</script>

<template>
  <div>
    <input v-model="query" />
    <ul>
      <li v-for="(p, i) in visible" v-if="!p.hidden" :key="i">{{ p.name }}</li>
    </ul>
  </div>
</template>
VUE
