---
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

oye, ¿este ticket lo ha escrito una IA? me lo ha pasado alguien nuevo del equipo y no sé, me suena raro. Te lo pego:

SHOP-1402 - el endpoint de facturas devuelve 500 a algunos clientes de empresa

Desde el deploy del martes (release 22.35.0) vemos en Sentry unos 40 errores a la hora en GET /v2/invoices. Solo pasa con clientes que tienen la cuenta pausada (paused_days > 0), al menos en los 6 casos que he mirado. El stacktrace acaba en InvoiceCalculator::daysBetween con un TypeError porque paused_at llega null.

Creo que viene del cambio de SHOP-1388 pero no lo he confirmado. Lo he reproducido en local con el usuario de fixtures company_paused@test.local.

Lo que no sé es si hay que arreglarlo en el calculador o en la migración que dejó ese campo a null. Lo hablamos en la daily?
